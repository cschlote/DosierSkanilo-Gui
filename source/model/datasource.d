/** Shared data-source adapter for JSON files and SQLite repositories. */
module model.datasource;

import core.atomic : atomicOp;
import std.algorithm.searching : canFind;
import std.base64 : Base64;
import std.file : exists, isDir;
import std.format : format;
import std.conv : to;
import std.datetime.systime : Clock;
import std.exception : enforce;
import std.path : absolutePath, baseName, buildPath, dirName, isAbsolute;
import std.string : empty;

import dosierarkivo.archive : ArchiveEntryDescriptor, ArchivePasswordCallback,
    ArchivePasswordCancelledException, appendArchiveVirtualPath,
    escapeArchiveVirtualPath, normalizeArchiveEntryPath,
    ParsedArchiveVirtualPath,
    parseArchiveVirtualPath;
import dosierarkivo.factory : fileArchive;
import dosierskanilo;
import dosierskanilo.catalogbackend : ArchiveEntryId, CatalogArchiveEntry,
    CatalogContentFingerprint, CatalogContentQuery, CatalogContentRow,
    CatalogContentSnapshot, CatalogDetailMask,
    CatalogFile, CatalogFileQuery, CatalogFilter, CatalogMediaKind, CatalogMediaStream,
    CatalogPageCursor, CatalogPageRequest, CatalogReferenceAvailability,
    CatalogTorrentManifestEntry, ContentId, ContentLocator, DirectoryId, ReferenceId;
import dosierskanilo.membercontentcache : MemberContentLease,
    sharedMemberContentCache;
import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob,
    DATA_CLASS_VERSION3, NamedBinaryBlobCatalog, deserializeDataClassJsonFile,
    updateArchives;
import model.blobrow : BlobRow;
import model.catalogsource : CatalogDirectorySource, openCatalogBackend,
    openJsonCatalogBackend;
import dosierskanilo.service.storageio : writeStorageJsonFile;
import dosierskanilo.operationlease : TargetCatalogReplacementLease,
    TargetReadLease, TargetWriteLease;
import dosierskanilo.operationrunner : runOperation;
import dosierskanilo.operations : MetadataOperationRequest, OperationControl,
    OperationState, OperationTarget;
import ui.contextpaths : resolveDocumentSourcePath;
import model.treeprojection : DirectoryNode, DirectorySource, FileCursor, FileFilter, FileInput, FileNode,
    FilePage, FileSortOrder, NestedFileNode, DirectoryTree, ProjectedDirectorySource,
    buildDirectoryTree, isArchivePathCandidate;

/** One lazy archive member projected into the main Directory Tree. */
struct ArchiveMemberTreeEntry
{
    string referenceId;
    string contentId;
    string name;
    string relativePath;
    string virtualPath;
    ulong size;
    bool hasArchive;
}

/** Bounded archive-member page and continuation position. */
struct ArchiveMemberTreePage
{
    ArchiveMemberTreeEntry[] entries;
    size_t nextOffset;
    bool hasMore;
}

/** Extracted bytes and logical path for one archive-member preview. */
struct AcquiredArchiveMemberPreview
{
    MemberContentLease lease;
    string virtualPath;
    ulong size;
}

/** Filter state translated into repository query options. */
struct SourceQuery
{
    string text;
    bool caseSensitive;
    bool video;
    bool audio;
    bool image;
    bool textStream;
    bool mediaNegated;
    bool fileType;
    bool archive;
    bool torrent;
}

/** Return whether `path` is inside a DosierSkanilo repository. */
bool isRepositorySource(string path)
{
    return exists(path) && isDir(path) && !Repository.findRoot(path).empty;
}

/** Build the directory projection for a JSON or repository source. */
DirectoryTree loadDocumentTree(string path)
{
    auto blobs = loadDocumentSource(path);
    FileInput[] inputs;
    foreach (blob; blobs)
    {
        if (blob is null)
            continue;
        foreach (spec; blob.fileSpecs)
        {
            if (spec !is null && spec.fileName.length > 0)
            {
                auto physicalPath = spec.fileName;
                if (blob.fileSpecsUseArchiveVirtualGrammar)
                {
                    auto parsed = parseArchiveVirtualPath(physicalPath);
                    if (parsed.isVirtual)
                        continue;
                    physicalPath = parsed.physicalPath;
                }
                FileInput input;
                input.path = physicalPath;
                input.size = cast(ulong) blob.fileSize;
                input.hasArchive = blob.archiveSpecs.length > 0
                    || isArchivePathCandidate(physicalPath);
                inputs ~= input;
            }
        }
        if (blob.fileSpecs.length == 0 && blob.getFirstFileName.length > 0)
            inputs ~= FileInput(blob.getFirstFileName, cast(ulong) blob.fileSize);
    }
    return buildDirectoryTree(inputs);
}

/** Directory source backed by bounded SQLite repository queries. */
/** Open a repository-backed directory source for the GUI tree. */
DirectorySource openRepositoryDirectorySource(string path)
{
    return new CatalogDirectorySource(openCatalogBackend(path));
}

private class ConcurrentSourceQueryResults
{
    size_t directoryCount;
    size_t fileCount;
    size_t detailLoads;
    string treeError;
    string detailError;
}

/** One page of deduplicated catalog content rows for table projections. */
struct CatalogRowPage
{
    BlobRow[] rows;
    CatalogPageCursor nextCursor;
    size_t total;
    bool hasMore;
}

private CatalogFilter catalogFilterFor(SourceQuery query)
{
    CatalogFilter filter;
    filter.pathText = query.text;
    filter.caseSensitive = query.caseSensitive;
    filter.video = query.video;
    filter.audio = query.audio;
    filter.image = query.image;
    filter.text = query.textStream;
    filter.mediaNegated = query.mediaNegated;
    filter.fileType = query.fileType;
    filter.archive = query.archive;
    filter.torrent = query.torrent;
    return filter;
}

private string digestBase64(const CatalogContentFingerprint fingerprint,
    string algorithm)
{
    foreach (digest; fingerprint.digests)
        if (digest.algorithm == algorithm)
            return cast(string) Base64.encode(digest.value);
    return "";
}

private string renderMediaDetails(const CatalogMediaStream[] streams)
{
    string result;
    foreach (stream; streams)
    {
        string kind;
        final switch (stream.kind)
        {
        case CatalogMediaKind.image:
            kind = "image";
            break;
        case CatalogMediaKind.video:
            kind = "video";
            break;
        case CatalogMediaKind.audio:
            kind = "audio";
            break;
        case CatalogMediaKind.text:
            kind = "text";
            break;
        }
        result ~= format("%s %d: %s", kind, stream.index, stream.format);
        if (stream.width > 0 || stream.height > 0)
            result ~= format(" %dx%d", stream.width, stream.height);
        if (stream.channels > 0)
            result ~= format(" %d channels", stream.channels);
        if (stream.frameRate > 0)
            result ~= format(" %.3f fps", stream.frameRate);
        if (stream.bitRate > 0)
            result ~= format(" %d bit/s", stream.bitRate);
        if (stream.duration.length > 0)
            result ~= " " ~ stream.duration;
        if (stream.language.length > 0)
            result ~= " (" ~ stream.language ~ ")";
        result ~= "\n";
    }
    return result;
}

private BlobRow blobRowForContent(const CatalogContentRow row)
{
    BlobRow result;
    result.sourceKey = row.displayPath;
    result.primaryFileName = row.displayName;
    result.fileSize = row.size;
    result.fileCount = row.referenceCount;
    result.hasSummaryFlags = true;
    result.summaryHasFileType = row.hasFileType;
    result.summaryHasMedia = row.hasMedia;
    result.summaryHasVideo = row.hasVideo;
    result.summaryHasAudio = row.hasAudio;
    result.summaryHasImage = row.hasImage;
    result.summaryHasText = row.hasText;
    result.summaryHasArchive = row.hasArchive;
    result.summaryHasTorrent = row.hasTorrent;
    result.detailsLoaded = false;
    result.md5 = digestBase64(row.fingerprint, "md5");
    result.sha1 = digestBase64(row.fingerprint, "sha1");
    result.xxh64 = digestBase64(row.fingerprint, "xxh64");
    return result;
}

/** Load one content-row page through the storage-neutral catalog backend. */
CatalogRowPage loadCatalogRowPage(string path, CatalogPageCursor cursor,
    size_t limit, SourceQuery query = SourceQuery())
{
    auto backend = openCatalogBackend(path);
    scope (exit)
        backend.close();
    return loadCatalogRowPage(backend, cursor, limit, query);
}

/** Load one content-row page from an already opened catalog backend. */
CatalogRowPage loadCatalogRowPage(CatalogBackend backend,
    CatalogPageCursor cursor, size_t limit, SourceQuery query = SourceQuery())
{
    CatalogContentQuery contentQuery;
    contentQuery.filter = catalogFilterFor(query);
    CatalogPageRequest request;
    request.limit = limit;
    request.cursor = cursor;
    const page = backend.listContents(contentQuery, request);
    CatalogRowPage result;
    result.rows.reserve(page.rows.length);
    foreach (row; page.rows)
        result.rows ~= blobRowForContent(row);
    result.nextCursor = page.nextCursor;
    result.hasMore = page.hasMore;
    result.total = page.total;
    return result;
}

/** Load an offset-addressed content-row page through the catalog backend. */
CatalogRowPage loadCatalogRowOffsetPage(string path, size_t offset,
    size_t limit, SourceQuery query = SourceQuery())
{
    auto backend = openCatalogBackend(path);
    scope (exit)
        backend.close();
    return loadCatalogRowOffsetPage(backend, offset, limit, query);
}

/** Load an offset-addressed page from an already opened catalog backend. */
CatalogRowPage loadCatalogRowOffsetPage(CatalogBackend backend, size_t offset,
    size_t limit, SourceQuery query = SourceQuery())
{
    CatalogContentQuery contentQuery;
    contentQuery.filter = catalogFilterFor(query);
    CatalogPageRequest request;
    request.limit = limit;
    CatalogPageCursor cursor;
    size_t seen;
    CatalogRowPage result;
    while (true)
    {
        request.cursor = cursor;
        const page = backend.listContents(contentQuery, request);
        result.total = page.total;
        result.nextCursor = page.nextCursor;
        result.hasMore = page.hasMore;
        foreach (index, row; page.rows)
        {
            const position = seen + index;
            if (position >= offset && result.rows.length < limit)
                result.rows ~= blobRowForContent(row);
        }
        seen += page.rows.length;
        if (!page.hasMore || result.rows.length >= limit)
            break;
        cursor = page.nextCursor;
    }
    return result;
}

/** Load full display details for one catalog reference path. */
BlobRow loadCatalogFileDetails(string path, string relativePath)
{
    auto backend = openCatalogBackend(path);
    scope (exit)
        backend.close();
    return loadCatalogFileDetails(backend, relativePath);
}

/** Load full display details from an already opened catalog backend. */
BlobRow loadCatalogFileDetails(CatalogBackend backend, string relativePath)
{
    const referenceId = backend.resolveReference(relativePath);
    if (!referenceId.isValid)
        throw new Exception("The selected file no longer exists.");
    const file = backend.loadReference(referenceId);
    CatalogDetailMask mask;
    mask.fingerprint = true;
    mask.fileType = true;
    mask.media = true;
    mask.archiveSummary = true;
    mask.torrentSummary = true;
    const snapshot = backend.loadContent(file.contentId, mask);
    BlobRow row;
    row.sourceKey = file.relativePath;
    row.primaryFileName = file.name;
    row.fileSize = file.size;
    row.fileCount = 1;
    row.hasSummaryFlags = true;
    row.summaryHasFileType = snapshot.fileType.length > 0;
    row.summaryHasMedia = snapshot.mediaStreams.length > 0;
    row.summaryHasArchive = snapshot.hasArchive;
    row.summaryHasTorrent = snapshot.hasTorrent;
    foreach (stream; snapshot.mediaStreams)
        final switch (stream.kind)
        {
        case CatalogMediaKind.image:
            row.summaryHasImage = true;
            break;
        case CatalogMediaKind.video:
            row.summaryHasVideo = true;
            break;
        case CatalogMediaKind.audio:
            row.summaryHasAudio = true;
            break;
        case CatalogMediaKind.text:
            row.summaryHasText = true;
            break;
        }
    row.md5 = digestBase64(snapshot.fingerprint, "md5");
    row.sha1 = digestBase64(snapshot.fingerprint, "sha1");
    row.xxh64 = digestBase64(snapshot.fingerprint, "xxh64");
    row.catalogFileType = snapshot.fileType;
    row.catalogMediaDetails = renderMediaDetails(snapshot.mediaStreams);
    if (snapshot.hasArchive)
        row.catalogArchiveDetails = format(
            "Archive index: %s\nEntries: %s\nComplete fingerprints: %s",
            snapshot.archiveSummary.indexKnown ? "known" : "unknown",
            snapshot.archiveSummary.entryCount,
            snapshot.archiveSummary.entriesWithCompleteFingerprints);
    if (snapshot.hasTorrent)
        row.catalogTorrentDetails = format(
            "Name: %s\nTotal size: %s\nMulti-file: %s\nInfo hash: %s\nAnnounce: %s",
            snapshot.torrentSummary.name, snapshot.torrentSummary.totalSize,
            snapshot.torrentSummary.isMultiFile ? "yes" : "no",
            snapshot.torrentSummary.infoHashHex, snapshot.torrentSummary.announce);
    row.catalogSourceDetails = format("Path: %s\nSize: %s bytes\nMD5: %s\nSHA1: %s\nXXH64: %s",
        file.relativePath, file.size, row.md5, row.sha1, row.xxh64);
    row.catalogFileNames = file.relativePath;
    row.detailsLoaded = true;
    return row;
}

/** Load a bounded page of JSON-v5 virtual members for one archive reference. */
ArchiveMemberTreePage loadJsonArchiveMemberTreePage(string containerVirtualPath,
    const(BlobRow)[] catalogRows, size_t offset = 0, size_t limit = 250,
    bool containerIsVirtual = false)
{
    enforce(limit > 0, "Archive-member page size must be greater than zero.");
    ParsedArchiveVirtualPath container;
    if (containerIsVirtual)
        container = parseArchiveVirtualPath(containerVirtualPath);
    else
        container.physicalPath = containerVirtualPath;
    ArchiveMemberTreeEntry[] allEntries;
    ArchiveMemberTreePage page;
    bool[string] seenPaths;
    foreach (row; catalogRows)
    {
        if (row.sourceBlob is null)
            continue;
        foreach (spec; row.sourceBlob.fileSpecs)
        {
            if (spec is null || spec.fileName.length == 0)
                continue;
            ParsedArchiveVirtualPath parsed;
            try
                parsed = parseArchiveVirtualPath(spec.fileName);
            catch (Exception)
                continue;
            if (!isDirectArchiveChild(container, parsed))
                continue;
            if (spec.fileName in seenPaths)
                continue;
            seenPaths[spec.fileName] = true;
            const auto layer = parsed.entries[$ - 1];
            ArchiveMemberTreeEntry member;
            member.referenceId = spec.fileName;
            member.contentId = row.sourceId >= 0 ? row.sourceId.to!string : "";
            member.name = layer.relativePath;
            member.relativePath = layer.relativePath;
            member.virtualPath = spec.fileName;
            member.size = row.fileSize;
            member.hasArchive = row.hasArchive
                || isArchivePathCandidate(layer.relativePath);
            allEntries ~= member;
        }
    }

    if (allEntries.length == 0 && !container.isVirtual)
    {
        foreach (row; catalogRows)
        {
            if (row.sourceBlob is null)
                continue;
            bool ownsContainer;
            foreach (spec; row.sourceBlob.fileSpecs)
            {
                if (spec is null || spec.fileName.length == 0)
                    continue;
                try
                {
                    auto parsedSpec = parseArchiveVirtualPath(spec.fileName);
                    if (!parsedSpec.isVirtual
                        && parsedSpec.physicalPath == container.physicalPath)
                    {
                        ownsContainer = true;
                        break;
                    }
                }
                catch (Exception)
                {
                }
            }
            if (!ownsContainer)
                continue;
            foreach (entry; row.sourceBlob.archiveSpecs)
            {
                if (entry is null || entry.fileName.length == 0)
                    continue;
                bool safe;
                bool isDirectory;
                const auto normalized = normalizeArchiveEntryPath(entry.fileName,
                    safe, isDirectory);
                if (!safe || isDirectory || normalized != entry.fileName)
                    continue;
                ArchiveMemberTreeEntry member;
                member.referenceId = entry.occurrence.to!string;
                member.name = entry.fileName;
                member.relativePath = entry.fileName;
                const auto encodedContainerPath = containerIsVirtual
                    ? containerVirtualPath
                    : escapeArchiveVirtualPath(container.physicalPath);
                member.virtualPath = appendArchiveVirtualPath(
                    encodedContainerPath, entry.fileName, entry.occurrence);
                member.size = entry.fileSize;
                member.hasArchive = isArchivePathCandidate(entry.fileName);
                allEntries ~= member;
            }
            break;
        }
    }

    auto start = offset < allEntries.length ? offset : allEntries.length;
    auto count = allEntries.length - start;
    if (count > limit)
    {
        count = limit;
        page.hasMore = true;
    }
    page.entries = allEntries[start .. start + count].dup;
    page.nextOffset = offset + count;
    return page;
}

private bool isDirectArchiveChild(ParsedArchiveVirtualPath container,
    ParsedArchiveVirtualPath candidate)
{
    if (!candidate.isVirtual || candidate.physicalPath != container.physicalPath
        || candidate.entries.length != container.entries.length + 1)
        return false;
    foreach (index, layer; container.entries)
    {
        const auto candidateLayer = candidate.entries[index];
        if (candidateLayer.relativePath != layer.relativePath
            || candidateLayer.occurrence != layer.occurrence
            || candidateLayer.hasOccurrence != layer.hasOccurrence)
            return false;
    }
    return true;
}

/** Acquire one member from a JSON archive using its physical container path. */
AcquiredArchiveMemberPreview acquireJsonArchiveMemberPreview(string documentPath,
    string containerPath, string memberPath, size_t occurrence = 0,
    string password = "")
{
    enforce(containerPath.length > 0 && memberPath.length > 0,
        "Archive member preview requires a container and member path.");
    auto physicalContainer = isAbsolute(containerPath)
        ? absolutePath(containerPath)
        : resolveDocumentSourcePath(documentPath, containerPath);
    auto virtualPath = appendArchiveVirtualPath(
        escapeArchiveVirtualPath(physicalContainer), memberPath, occurrence);
    return acquireJsonVirtualArchiveMemberPreview(documentPath, virtualPath,
        password);
}

/** Acquire a JSON-v5 archive member by its complete virtual path. */
AcquiredArchiveMemberPreview acquireJsonVirtualArchiveMemberPreview(
    string documentPath, string virtualPath, string password = "")
{
    auto logicalVirtualPath = virtualPath;
    auto parsed = parseArchiveVirtualPath(virtualPath);
    if (!isAbsolute(parsed.physicalPath))
    {
        virtualPath = escapeArchiveVirtualPath(resolveDocumentSourcePath(
            documentPath, parsed.physicalPath));
        foreach (layer; parsed.entries)
            virtualPath = appendArchiveVirtualPath(virtualPath,
                layer.relativePath,
                layer.hasOccurrence ? layer.occurrence : size_t.max);
    }
    AcquiredArchiveMemberPreview preview;
    preview.lease = acquireVirtualArchiveMember("", virtualPath,
        "json:" ~ absolutePath(documentPath), 0, password);
    preview.virtualPath = logicalVirtualPath;
    import std.file : getSize;
    preview.size = getSize(preview.lease.path);
    return preview;
}

private MemberContentLease acquireVirtualArchiveMember(string sourceRoot,
    string virtualPath, string sourceIdentity, ulong expectedSize,
    string password)
{
    auto parsed = parseArchiveVirtualPath(virtualPath);
    enforce(parsed.isVirtual, "Archive preview requires a virtual member path.");
    auto containerPath = isAbsolute(parsed.physicalPath)
        ? parsed.physicalPath : buildPath(sourceRoot, parsed.physicalPath);
    auto cache = sharedMemberContentCache();
    auto containerPathIdentity = parsed.physicalPath;
    MemberContentLease previousLease;

    try
    {
        foreach (index, layer; parsed.entries)
        {
            auto archive = fileArchive(containerPath);
            enforce(archive !is null,
                "The archive member's container format is unavailable.");
            auto descriptors = archive.getEntryDescriptors(password);
            enforce(descriptors !is null,
                "The archive adapter could not list member descriptors.");

            ArchiveEntryDescriptor selected;
            bool found;
            const auto requestedOccurrence = layer.hasOccurrence
                ? layer.occurrence : 0;
            foreach (descriptor; descriptors)
            {
                if (descriptor.hasSafePath && !descriptor.isDirectory
                    && descriptor.relativePath == layer.relativePath
                    && descriptor.occurrence == requestedOccurrence)
                {
                    selected = descriptor;
                    found = true;
                    break;
                }
            }
            enforce(found, "The selected archive member no longer exists.");

            const auto locator = ContentLocator.init;
            const auto fallbackIdentity = sourceIdentity ~ ":container:"
                ~ containerPathIdentity ~ "!/" ~ layer.relativePath ~ "!~"
                ~ requestedOccurrence.to!string;
            const auto sizeLimit = selected.hasSize ? selected.size
                : index + 1 == parsed.entries.length ? expectedSize : 0;
            auto lease = cache.acquire(locator, ContentId.init,
                fallbackIdentity, layer.relativePath, sizeLimit,
                (string destinationDirectory) {
                    return archive.extractEntry(selected, destinationDirectory,
                        password);
                });

            if (previousLease !is null)
                previousLease.release();
            previousLease = lease;
            containerPath = lease.path;
            containerPathIdentity = appendArchiveVirtualPath(
                containerPathIdentity, layer.relativePath,
                layer.hasOccurrence ? layer.occurrence : size_t.max);
        }
    }
    catch (Throwable failure)
    {
        if (previousLease !is null)
            previousLease.release();
        throw failure;
    }

    return previousLease;
}

/** Load a bounded page of catalog archive entries for one container reference. */
NestedFileNode[] loadCatalogArchiveEntries(string path, string containerPath,
    size_t offset = 0, size_t limit = 250)
{
    auto backend = openCatalogBackend(path);
    scope (exit)
        backend.close();
    return loadCatalogArchiveEntries(backend, containerPath, offset, limit);
}

/** Load archive entries from an already opened catalog backend. */
NestedFileNode[] loadCatalogArchiveEntries(CatalogBackend backend,
    string containerPath, size_t offset = 0, size_t limit = 250)
{
    const referenceId = backend.resolveReference(containerPath);
    if (!referenceId.isValid)
        throw new Exception("The archive container no longer exists.");
    const container = backend.loadReference(referenceId);
    /* Container paths are already in display grammar, so member identities
     * append the escaped entry layer to the path as-is. */
    const basePath = containerPath;

    const(CatalogArchiveEntry)[] entries;
    CatalogPageCursor cursor;
    while (true)
    {
        CatalogPageRequest request;
        request.limit = 250;
        request.cursor = cursor;
        const page = backend.listArchiveEntries(container.contentId, request);
        entries ~= page.entries;
        if (!page.hasMore)
            break;
        cursor = page.nextCursor;
    }

    size_t[string] occurrenceCounts;
    foreach (entry; entries)
        occurrenceCounts[entry.relativePath] = occurrenceCounts.get(
            entry.relativePath, 0) + 1;

    NestedFileNode[] result;
    foreach (index, entry; entries)
    {
        if (index < offset || result.length >= limit)
            continue;
        string identity;
        if (entry.hasSafePath && !entry.isDirectory)
        {
            const auto occurrence = occurrenceCounts.get(entry.relativePath, 1) > 1
                ? entry.occurrence : size_t.max;
            identity = appendArchiveVirtualPath(basePath, entry.relativePath,
                occurrence);
        }
        result ~= NestedFileNode(identity, entry.name, entry.name, entry.size,
            entry.modifiedAt);
    }
    return result;
}

/** Load a bounded page of catalog torrent entries for one container reference. */
NestedFileNode[] loadCatalogTorrentEntries(string path, string containerPath,
    size_t offset = 0, size_t limit = 250)
{
    auto backend = openCatalogBackend(path);
    scope (exit)
        backend.close();
    return loadCatalogTorrentEntries(backend, containerPath, offset, limit);
}

/** Load torrent entries from an already opened catalog backend. */
NestedFileNode[] loadCatalogTorrentEntries(CatalogBackend backend,
    string containerPath, size_t offset = 0, size_t limit = 250)
{
    const referenceId = backend.resolveReference(containerPath);
    if (!referenceId.isValid)
        throw new Exception("The torrent reference no longer exists.");
    const container = backend.loadReference(referenceId);
    NestedFileNode[] result;
    size_t seen;
    CatalogPageCursor cursor;
    while (result.length < limit)
    {
        CatalogPageRequest request;
        request.limit = 250;
        request.cursor = cursor;
        const page = backend.listTorrentEntries(container.contentId, request);
        foreach (entry; page.entries)
        {
            if (seen >= offset && result.length < limit)
            {
                string relativePath;
                foreach (index, component; entry.pathComponents)
                {
                    if (index > 0)
                        relativePath ~= "/";
                    relativePath ~= component;
                }
                result ~= NestedFileNode(containerPath ~ "!/" ~ relativePath,
                    relativePath, relativePath, entry.size, "");
            }
            ++seen;
        }
        if (!page.hasMore)
            break;
        cursor = page.nextCursor;
    }
    return result;
}

/** Load direct catalog archive members for one container reference path. */
ArchiveMemberTreePage loadCatalogArchiveMemberTreePage(string path,
    string containerPath, size_t offset = 0, size_t limit = 250)
{
    auto backend = openCatalogBackend(path);
    scope (exit)
        backend.close();
    return loadCatalogArchiveMemberTreePage(backend, containerPath, offset, limit);
}

/** Load direct archive members from an already opened catalog backend. */
ArchiveMemberTreePage loadCatalogArchiveMemberTreePage(CatalogBackend backend,
    string containerPath, size_t offset = 0, size_t limit = 250)
{
    enforce(limit > 0, "Archive-member page size must be greater than zero.");
    const referenceId = backend.resolveReference(containerPath);
    if (!referenceId.isValid)
        return ArchiveMemberTreePage.init;
    const container = backend.loadReference(referenceId);
    const containerLayers = parseArchiveVirtualPath(containerPath).entries.length;

    CatalogFileQuery query;
    query.directoryId = container.directoryId;
    query.filter.includeArchiveMembers = true;
    query.filter.pathText = containerPath ~ "!/";

    ArchiveMemberTreeEntry[] direct;
    CatalogPageCursor cursor;
    while (true)
    {
        CatalogPageRequest request;
        request.limit = 250;
        request.cursor = cursor;
        const page = backend.listFiles(query, request);
        foreach (file; page.files)
        {
            ParsedArchiveVirtualPath parsed;
            try
                parsed = parseArchiveVirtualPath(file.relativePath);
            catch (Exception)
                continue;
            if (!parsed.isVirtual
                || parsed.entries.length != containerLayers + 1)
                continue;
            ArchiveMemberTreeEntry entry;
            entry.referenceId = file.relativePath;
            entry.name = file.name;
            entry.relativePath = file.name;
            entry.virtualPath = file.relativePath;
            entry.size = file.size;
            entry.hasArchive = file.hasArchive
                || isArchivePathCandidate(file.name);
            direct ~= entry;
        }
        if (!page.hasMore)
            break;
        cursor = page.nextCursor;
    }

    ArchiveMemberTreePage result;
    const start = offset < direct.length ? offset : direct.length;
    auto count = direct.length - start;
    if (count > limit)
    {
        count = limit;
        result.hasMore = true;
    }
    result.entries = direct[start .. start + count].dup;
    result.nextOffset = offset + count;
    return result;
}

/** Acquire one catalog archive member into the shared preview cache. */
AcquiredArchiveMemberPreview acquireCatalogArchiveMemberPreview(string path,
    string memberRelativePath)
{
    auto backend = openCatalogBackend(path);
    scope (exit)
        backend.close();
    return acquireCatalogArchiveMemberPreview(backend, memberRelativePath);
}

/** Acquire a member preview from an already opened catalog backend. */
AcquiredArchiveMemberPreview acquireCatalogArchiveMemberPreview(
    CatalogBackend backend, string memberRelativePath)
{
    const referenceId = backend.resolveReference(memberRelativePath);
    if (!referenceId.isValid)
        throw new Exception("The selected archive member no longer exists.");
    const member = backend.loadReference(referenceId);
    AcquiredArchiveMemberPreview preview;
    preview.lease = backend.acquireMemberContent(referenceId);
    preview.virtualPath = member.relativePath;
    preview.size = member.size;
    return preview;
}

/** Load one JSON catalog document. */
NamedBinaryBlob[] loadDocumentSource(string path)
{
    return readJsonCatalog(path);
}

/** Store or remove one password after resolving the user's filename to a blob. */
void setDocumentArchivePassword(string sourcePath, string fileName, string password)
{
    auto backend = isRepositorySource(sourcePath)
        ? openCatalogBackend(sourcePath) : openJsonCatalogBackend(sourcePath);
    scope (exit)
        backend.close();
    backend.setArchivePassword(fileName, password);
}

private shared ulong nextArchiveScanOperationId;

/** Run an archive rescan against a repository through the operation API. */
private MetadataSummary runRepositoryArchiveScan(string sourcePath,
    string filePath, ArchivePasswordCallback passwordCallback)
{
    MetadataScanOptions options;
    options.scanArchives = true;
    options.deepArchiveScan = true;
    options.rescan = true;
    options.archivePasswordCallback = passwordCallback;
    options.filePath = filePath;
    MetadataOperationRequest request;
    request.operationId = atomicOp!"+="(nextArchiveScanOperationId, 1UL) + 1;
    request.target = OperationTarget.repositoryTarget(sourcePath);
    request.options = options;
    auto result = runOperation(request, new OperationControl());
    if (result.state != OperationState.completed)
        throw new Exception(result.error.length > 0
            ? result.error : "Repository archive scan did not complete.");
    return result.metadataSummary;
}

/** Scan archive entries in a JSON catalog or SQLite repository. */
MetadataSummary scanDocumentArchives(string sourcePath,
    ArchivePasswordCallback passwordCallback)
{
    if (isRepositorySource(sourcePath))
        return runRepositoryArchiveScan(sourcePath, "", passwordCallback);

    auto targetLease = TargetWriteLease.acquire(
        OperationTarget.jsonTarget(sourcePath));
    scope (exit)
        targetLease.release();
    auto blobs = deserializeDataClassJsonFile(sourcePath);
    MetadataSummary summary;
    summary.blobsVisited = blobs.length;
    foreach (blob; blobs)
    {
        string[] originalPaths;
        foreach (spec; blob.fileSpecs)
        {
            if (spec is null)
            {
                originalPaths ~= "";
                continue;
            }
            originalPaths ~= spec.fileName;
            spec.fileName = resolveDocumentSourcePath(sourcePath,
                spec.fileName);
        }
        scope (exit)
        {
            foreach (index, spec; blob.fileSpecs)
                if (spec !is null)
                    spec.fileName = originalPaths[index];
        }
        try
        {
            updateArchives(blob, true, true, null, null, passwordCallback);
            if (blob.archiveSpecs !is null)
                ++summary.archivesUpdated;
        }
        catch (ArchivePasswordCancelledException)
        {
            ++summary.failed;
            break;
        }
        catch (Exception)
        {
            ++summary.failed;
        }
    }
    writeJsonCatalog(sourcePath, blobs, targetLease);
    return summary;
}

/** Scan archive entries for the single file selected in a source context menu. */
MetadataSummary scanDocumentArchive(string sourcePath, string filePath,
    ArchivePasswordCallback passwordCallback)
{
    if (isRepositorySource(sourcePath))
    {
        auto summary = runRepositoryArchiveScan(sourcePath, filePath,
            passwordCallback);
        if (summary.blobsVisited == 0)
            throw new Exception("No repository file matches: " ~ filePath);
        return summary;
    }

    auto targetLease = TargetWriteLease.acquire(
        OperationTarget.jsonTarget(sourcePath));
    scope (exit)
        targetLease.release();
    auto blobs = deserializeDataClassJsonFile(sourcePath);
    auto requestedPath = resolveDocumentSourcePath(sourcePath, filePath);
    size_t[] matches;
    foreach (index, blob; blobs)
    {
        foreach (spec; blob.fileSpecs)
        {
            if (spec !is null
                && (resolveDocumentSourcePath(sourcePath, spec.fileName)
                    == requestedPath || spec.fileName == filePath))
            {
                matches ~= index;
                break;
            }
        }
    }
    if (matches.length == 0)
        throw new Exception("No catalog file matches: " ~ filePath);
    if (matches.length > 1)
        throw new Exception("Filename is ambiguous in this catalog: " ~ filePath);

    auto blob = blobs[matches[0]];
    MetadataSummary summary;
    summary.blobsVisited = 1;
    {
        string[] originalPaths;
        foreach (spec; blob.fileSpecs)
        {
            if (spec is null)
            {
                originalPaths ~= "";
                continue;
            }
            originalPaths ~= spec.fileName;
            spec.fileName = resolveDocumentSourcePath(sourcePath,
                spec.fileName);
        }
        scope (exit)
        {
            foreach (index, spec; blob.fileSpecs)
                if (spec !is null)
                    spec.fileName = originalPaths[index];
        }
        try
        {
            updateArchives(blob, true, true, null, null, passwordCallback);
            if (blob.archiveSpecs !is null)
                ++summary.archivesUpdated;
        }
        catch (ArchivePasswordCancelledException)
            ++summary.failed;
        catch (Exception)
            ++summary.failed;
    }
    writeJsonCatalog(sourcePath, blobs, targetLease);
    return summary;
}

private NamedBinaryBlob[] readJsonCatalog(string sourcePath)
{
    auto readLease = TargetReadLease.acquireJsonCatalog(sourcePath);
    scope (exit)
        readLease.release();
    return deserializeDataClassJsonFile(sourcePath);
}

private void writeJsonCatalog(string sourcePath, NamedBinaryBlob[] blobs,
    TargetWriteLease targetLease)
{
    enforce(targetLease.owns(OperationTarget.jsonTarget(sourcePath)),
        "JSON write lease does not match catalog path.");
    auto wrapper = NamedBinaryBlobCatalog(DATA_CLASS_VERSION3, blobs);
    auto replacementLease = TargetCatalogReplacementLease.acquireJsonCatalog(
        sourcePath);
    scope (exit)
        replacementLease.release();
    enforce(writeStorageJsonFile(sourcePath, wrapper, ".json",
        Clock.currTime.toISOExtString, dirName(sourcePath)),
        "Failed to safely save JSON archive metadata to " ~ sourcePath);
}

@("repository source detection")
unittest
{
    import std.conv : to;
    import std.file : mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto root = buildPath(tempDir(), "gui-source-" ~ randomUUID().toString());
    mkdirRecurse(root);
    scope (exit)
        rmdirRecurse(root);

    assert(!isRepositorySource(root));
    assert(!isRepositorySource(buildPath(root, "missing")));
    auto repository = Repository.initialize(root);
    repository.close();
    assert(isRepositorySource(root));
    auto nested = buildPath(root, "nested", "directory");
    mkdirRecurse(nested);
    assert(isRepositorySource(nested));
    auto page = loadCatalogRowOffsetPage(root, 0, 10);
    assert(page.total == 0);
    assert(page.rows.length == 0);

    repository = Repository.open(root);
    write(buildPath(root, "one.txt"), "one");
    write(buildPath(root, "two.txt"), "two");
    write(buildPath(root, "three.txt"), "three");
    repository.scan();
    assert(repository.blobCount == 3, "blobs=" ~ to!string(repository.blobCount));
    assert(repository.countCatalogQuery(RepositoryQueryOptions()) == 3,
        "query=" ~ to!string(repository.countCatalogQuery(RepositoryQueryOptions())));
    repository.close();
    auto backend = openCatalogBackend(root);
    scope (exit)
        backend.close();
    auto populated = loadCatalogRowOffsetPage(backend, 0, 2);
    assert(populated.total == 3, "total=" ~ to!string(populated.total));
    assert(populated.rows.length == 2);
    assert(!populated.rows[0].hasMedia);
    auto directorySource = openRepositoryDirectorySource(root);
    assert(directorySource.root().id == "root");
    assert(directorySource.root().name == baseName(root));
    assert(directorySource.root().fileCount == 3);
    assert(directorySource.root().aggregateSize == 11);
    assert(directorySource.listFiles("root").length == 3);
    assert(directorySource.listFiles("root", 0, 250, "one.txt").length == 1);
    auto catalogPage = loadCatalogRowPage(backend, CatalogPageCursor.init, 1);
    assert(catalogPage.rows.length == 1);
    assert(catalogPage.hasMore);
    auto nextCatalogPage = loadCatalogRowPage(backend, catalogPage.nextCursor, 1);
    assert(nextCatalogPage.rows.length == 1);
    assert(nextCatalogPage.rows[0].sourceKey != catalogPage.rows[0].sourceKey);
    auto finalCatalogPage = loadCatalogRowPage(backend, nextCatalogPage.nextCursor, 1);
    assert(finalCatalogPage.rows.length == 1);
    assert(!finalCatalogPage.hasMore);
    auto firstPage = directorySource.listFilesPage("root", FileCursor(), 1);
    assert(firstPage.files.length == 1);
    assert(firstPage.hasMore);
    auto secondPage = directorySource.listFilesPage("root", firstPage.nextCursor, 1);
    assert(secondPage.files.length == 1);
    assert(secondPage.hasMore);
    auto thirdPage = directorySource.listFilesPage("root", secondPage.nextCursor, 1);
    assert(thirdPage.files.length == 1);
    assert(!thirdPage.hasMore);

    FileNode twoFile;
    foreach (file; directorySource.listFiles("root"))
        if (file.name == "two.txt")
            twoFile = file;
    assert(twoFile.cursorId.length > 0);
    FileFilter caseSensitiveFilter;
    caseSensitiveFilter.text = "ONE.TXT";
    caseSensitiveFilter.caseSensitive = true;
    auto previousCaseSensitivePage = directorySource.listPreviousFilteredFilesPage(
        "root", FileCursor(twoFile.relativePath, twoFile.cursorId, twoFile.size),
        10, caseSensitiveFilter);
    assert(previousCaseSensitivePage.files.length == 0);

    directorySource.close();
    SourceQuery filteredQuery;
    filteredQuery.text = "one.txt";
    auto filtered = loadCatalogRowOffsetPage(backend, 0, 250, filteredQuery);
    assert(filtered.total == 1);
    assert(filtered.rows.length == 1);
}

@("repository tree and detail queries use independent concurrent connections")
unittest
{
    import core.thread : Thread;
    import std.file : exists, mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.format : format;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto root = buildPath(tempDir(), "gui-concurrent-source-" ~ randomUUID().toString());
    mkdirRecurse(root);
    scope (exit)
    {
        if (exists(root))
            rmdirRecurse(root);
    }

    foreach (index; 0 .. 80)
        write(buildPath(root, format("file-%03d.txt", index)),
            format("payload-%03d", index));
    auto nestedDirectory = buildPath(root, "nested");
    mkdirRecurse(nestedDirectory);
    write(buildPath(nestedDirectory, "nested.txt"), "nested payload");

    auto repository = Repository.initialize(root);
    repository.scan();
    repository.close();

    auto source = openRepositoryDirectorySource(root);
    scope (exit)
        source.close();
    auto selectedFile = source.listFilesPage("root", FileCursor(), 1).files[0];
    auto filePath = selectedFile.cursorId;
    auto concurrentResults = new ConcurrentSourceQueryResults();
    auto treeThread = new Thread({
        try
        {
            foreach (_; 0 .. 16)
            {
                concurrentResults.directoryCount = source.listDirectories("root").length;
                concurrentResults.fileCount = source.listFilesPage("root",
                    FileCursor(), 16).files.length;
            }
        }
        catch (Exception ex)
            concurrentResults.treeError = ex.msg;
    });
    auto detailThread = new Thread({
        try
        {
            foreach (_; 0 .. 16)
                if (loadCatalogFileDetails(root, filePath).sourceKey.length > 0)
                    ++concurrentResults.detailLoads;
        }
        catch (Exception ex)
            concurrentResults.detailError = ex.msg;
    });
    treeThread.start();
    detailThread.start();
    treeThread.join();
    detailThread.join();

    assert(concurrentResults.treeError.length == 0, concurrentResults.treeError);
    assert(concurrentResults.detailError.length == 0,
        concurrentResults.detailError);
    assert(concurrentResults.directoryCount == 1);
    assert(concurrentResults.fileCount == 16);
    assert(concurrentResults.detailLoads == 16);
}

@("JSON and repository sources preserve filtered sorted navigation parity")
unittest
{
    import std.file : exists, mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto fixture = buildPath(tempDir(), "gui-source-parity-" ~ randomUUID().toString());
    auto root = buildPath(fixture, "repository");
    auto jsonPath = buildPath(fixture, "catalog.json");
    mkdirRecurse(buildPath(root, "album"));
    scope (exit)
    {
        if (exists(fixture))
            rmdirRecurse(fixture);
    }

    write(buildPath(root, "album", "small.dat"), "a");
    write(buildPath(root, "album", "medium.dat"), "abcd");
    write(buildPath(root, "album", "large.dat"), "abcdef");
    write(buildPath(root, "album", "largest.dat"), "abcdefgh");
    write(buildPath(root, "outside.dat"), "outside");

    auto repository = Repository.initialize(root);
    repository.scan();
    repository.exportJson(jsonPath);
    repository.close();

    DirectorySource jsonSource = new ProjectedDirectorySource(loadDocumentTree(jsonPath));
    auto repositorySource = openRepositoryDirectorySource(root);
    scope (exit)
    {
        jsonSource.close();
        repositorySource.close();
    }

    FileFilter filter;
    filter.text = "album/";
    filter.caseSensitive = true;
    string jsonDirectoryId;
    foreach (directory; jsonSource.listDirectories("root", filter))
        if (directory.relativePath == "album")
            jsonDirectoryId = directory.id;
    string repositoryDirectoryId;
    foreach (directory; repositorySource.listDirectories("root", filter))
        if (directory.relativePath == "album")
            repositoryDirectoryId = directory.id;
    assert(jsonDirectoryId.length > 0);
    assert(repositoryDirectoryId.length > 0);

    void assertSameFiles(FileNode[] expected, FileNode[] actual)
    {
        assert(expected.length == actual.length);
        foreach (index, file; expected)
        {
            assert(file.relativePath == actual[index].relativePath);
            assert(file.size == actual[index].size);
        }
    }

    auto jsonFirst = jsonSource.listFilteredFilesPage(jsonDirectoryId,
        FileCursor(), 2, filter, FileSortOrder.sizeAscending);
    auto repositoryFirst = repositorySource.listFilteredFilesPage(repositoryDirectoryId,
        FileCursor(), 2, filter, FileSortOrder.sizeAscending);
    assertSameFiles(jsonFirst.files, repositoryFirst.files);
    assert(jsonFirst.hasMore && repositoryFirst.hasMore);

    auto jsonSecond = jsonSource.listFilteredFilesPage(jsonDirectoryId,
        jsonFirst.nextCursor, 2, filter, FileSortOrder.sizeAscending);
    auto repositorySecond = repositorySource.listFilteredFilesPage(repositoryDirectoryId,
        repositoryFirst.nextCursor, 2, filter, FileSortOrder.sizeAscending);
    assertSameFiles(jsonSecond.files, repositorySecond.files);
    assert(!jsonSecond.hasMore && !repositorySecond.hasMore);

    auto jsonPrevious = jsonSource.listPreviousFilteredFilesPage(jsonDirectoryId,
        FileCursor(jsonSecond.files[0].relativePath, jsonSecond.files[0].cursorId,
            jsonSecond.files[0].size), 2, filter, FileSortOrder.sizeAscending);
    auto repositoryPrevious = repositorySource.listPreviousFilteredFilesPage(
        repositoryDirectoryId,
        FileCursor(repositorySecond.files[0].relativePath,
            repositorySecond.files[0].cursorId, repositorySecond.files[0].size),
        2, filter, FileSortOrder.sizeAscending);
    assertSameFiles(jsonFirst.files, jsonPrevious.files);
    assertSameFiles(jsonPrevious.files, repositoryPrevious.files);
}

@("repository archive scans run through the shared operation API")
unittest
{
    import std.file : exists, mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.process : Config, execute;
    import std.uuid : randomUUID;

    auto root = buildPath(tempDir(), "gui-scan-operation-"
        ~ randomUUID().toString());
    mkdirRecurse(root);
    scope (exit)
    {
        if (exists(root))
            rmdirRecurse(root);
    }
    write(buildPath(root, "payload.txt"), "archive payload\n");
    assert(execute(["zip", "-q", "-j", "payload.zip", "payload.txt"], null,
        Config.none, size_t.max, root).status == 0);

    auto repository = Repository.initialize(root);
    repository.scan();
    repository.close();

    auto summary = scanDocumentArchives(root, null);
    assert(summary.blobsVisited == 2, "visited=" ~ summary.blobsVisited.to!string);
    assert(summary.archivesUpdated == 1,
        "updated=" ~ summary.archivesUpdated.to!string
        ~ " failed=" ~ summary.failed.to!string);
    auto single = scanDocumentArchive(root, "payload.zip", null);
    assert(single.blobsVisited == 1);
    assert(single.archivesUpdated == 1);
}

@("repository detail adapter keeps archive and torrent entries lazy")
unittest
{
    import std.file : copy, exists, mkdirRecurse, readText, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.process : execute;
    import std.uuid : randomUUID;

    auto root = buildPath(tempDir(), "gui-lazy-details-" ~ randomUUID().toString());
    mkdirRecurse(root);
    scope (exit)
    {
        if (exists(root))
            rmdirRecurse(root);
    }

    auto archivePayload = buildPath(root, "payload.txt");
    auto archivePath = buildPath(root, "payload.zip");
    write(archivePayload, "archive payload\n");
    assert(execute(["zip", "-q", "-j", archivePath, archivePayload]).status == 0);
    auto torrentPath = buildPath(root, "sample.torrent");
    copy("../DosierSkanilo/test/example.torrent", torrentPath);

    auto repository = Repository.initialize(root);
    repository.scan();
    MetadataScanOptions metadataOptions;
    metadataOptions.scanArchives = true;
    metadataOptions.scanTorrents = true;
    metadataOptions.deepArchiveScan = true;
    repository.updateMetadata(metadataOptions);
    RepositoryFileQuery archiveQuery;
    archiveQuery.archive = true;
    auto archiveFile = repository.listFiles(archiveQuery)[0];
    RepositoryFileQuery torrentQuery;
    torrentQuery.torrent = true;
    auto torrentFile = repository.listFiles(torrentQuery)[0];
    repository.close();

    auto archiveDetails = loadCatalogFileDetails(root, archiveFile.relativePath);
    assert(archiveDetails.hasArchive);
    assert(archiveDetails.hasSummaryFlags);
    auto archiveMembers = loadCatalogArchiveEntries(root,
        archiveFile.relativePath);
    assert(archiveMembers.length > 0);
    auto memberTreePage = loadCatalogArchiveMemberTreePage(root,
        archiveFile.relativePath);
    assert(memberTreePage.entries.length == 1);
    assert(memberTreePage.entries[0].referenceId == archiveMembers[0].id);
    assert(memberTreePage.entries[0].virtualPath.canFind("!/payload.txt"));
    auto memberPreview = acquireCatalogArchiveMemberPreview(root,
        memberTreePage.entries[0].referenceId);
    scope (exit)
        if (memberPreview.lease !is null)
            memberPreview.lease.release();
    assert(memberPreview.virtualPath.canFind("!/payload.txt"));
    assert(memberPreview.size == "archive payload\n".length);
    assert(readText(memberPreview.lease.path) == "archive payload\n");

    auto torrentDetails = loadCatalogFileDetails(root, torrentFile.relativePath);
    assert(torrentDetails.hasTorrent);
    assert(loadCatalogTorrentEntries(root, torrentFile.relativePath).length > 0);
}

@("archive and torrent detail adapters continue beyond 250 entries")
unittest
{
    import std.file : exists, mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.format : format;
    import std.path : buildPath;
    import std.process : Config, execute;
    import std.string : endsWith;
    import std.uuid : randomUUID;

    auto fixture = buildPath(tempDir(), "gui-large-nested-details-"
        ~ randomUUID().toString());
    auto root = buildPath(fixture, "repository");
    auto archiveInput = buildPath(fixture, "archive-input");
    auto nestedInput = buildPath(archiveInput, "folder");
    mkdirRecurse(nestedInput);
    mkdirRecurse(root);
    scope (exit)
    {
        if (exists(fixture))
            rmdirRecurse(fixture);
    }

    string[] zipArguments = ["zip", "-q", buildPath(root, "many.zip")];
    string torrentData = "d4:infod5:filesl";
    foreach (index; 0 .. 251)
    {
        auto name = format("entry-%03d.txt", index);
        write(buildPath(nestedInput, name), "payload");
        zipArguments ~= buildPath("folder", name);
        torrentData ~= "d6:lengthi1e4:pathl6:folder13:" ~ name ~ "ee";
    }
    torrentData ~= "e4:name4:test12:piece lengthi16384e6:pieces20:"
        ~ "01234567890123456789ee";
    auto torrentPath = buildPath(root, "many.torrent");
    write(torrentPath, torrentData);
    assert(execute(zipArguments, null, Config.none, size_t.max, archiveInput).status == 0);

    auto repository = Repository.initialize(root);
    repository.scan();
    MetadataScanOptions metadataOptions;
    metadataOptions.scanArchives = true;
    metadataOptions.scanTorrents = true;
    metadataOptions.deepArchiveScan = false;
    repository.updateMetadata(metadataOptions);
    RepositoryFileQuery archiveQuery;
    archiveQuery.archive = true;
    auto archiveFile = repository.listFiles(archiveQuery)[0];
    RepositoryFileQuery torrentQuery;
    torrentQuery.torrent = true;
    auto torrentFile = repository.listFiles(torrentQuery)[0];
    repository.close();

    auto archiveProbe = loadCatalogArchiveEntries(root, archiveFile.relativePath,
        0, 251);
    assert(archiveProbe.length == 251);
    auto archivePage = archiveProbe[0 .. 250];
    assert(archivePage.length == 250);
    auto archiveContinuation = loadCatalogArchiveEntries(root,
        archiveFile.relativePath, archivePage.length, 251);
    assert(archiveContinuation.length == 1);
    assert(archiveContinuation[0].relativePath.endsWith("folder/entry-250.txt"));

    auto torrentProbe = loadCatalogTorrentEntries(root, torrentFile.relativePath,
        0, 251);
    assert(torrentProbe.length == 251);
    auto torrentPage = torrentProbe[0 .. 250];
    assert(torrentPage.length == 250);
    auto torrentContinuation = loadCatalogTorrentEntries(root,
        torrentFile.relativePath, torrentPage.length, 251);
    assert(torrentContinuation.length == 1);
    assert(torrentContinuation[0].relativePath == "test/folder/entry-250.txt");
}

@("catalog archive ids cover escaping, duplicate occurrences, and unsafe paths")
unittest
{
    import std.algorithm.searching : endsWith;
    import std.file : exists, mkdirRecurse, readText, rmdirRecurse, tempDir;
    import std.path : buildPath;
    import std.process : execute;
    import std.string : endsWith;
    import std.uuid : randomUUID;

    auto root = buildPath(tempDir(), "gui-catalog-member-ids-"
        ~ randomUUID().toString());
    mkdirRecurse(root);
    scope (exit)
    {
        if (exists(root))
            rmdirRecurse(root);
    }

    auto archivePath = buildPath(root, "name.zip");
    const createArchive = "import sys, zipfile; "
        ~ "z = zipfile.ZipFile(sys.argv[1], 'w'); "
        ~ "z.writestr('dup.txt', 'first'); "
        ~ "z.writestr('dup.txt', 'second'); "
        ~ "z.writestr('bang!.txt', 'bang'); "
        ~ "z.writestr('../escape.txt', 'bad'); z.close()";
    assert(execute(["python3", "-c", createArchive, archivePath]).status == 0);

    auto repository = Repository.initialize(root);
    repository.scan();
    MetadataScanOptions metadataOptions;
    metadataOptions.scanArchives = true;
    metadataOptions.deepArchiveScan = true;
    repository.updateMetadata(metadataOptions);
    repository.close();

    const containerPath = escapeArchiveVirtualPath("name.zip");
    auto entries = loadCatalogArchiveEntries(root, containerPath);
    string[] duplicateIds;
    bool sawBang;
    foreach (entry; entries)
    {
        if (entry.name == "dup.txt")
            duplicateIds ~= entry.id;
        else if (entry.name == "bang!.txt")
            sawBang = entry.id.endsWith("!/bang!!.txt");
    }
    assert(duplicateIds.length == 2);
    bool sawFirst;
    bool sawSecond;
    foreach (id; duplicateIds)
    {
        sawFirst = sawFirst || id.endsWith("!/dup.txt!~0");
        sawSecond = sawSecond || id.endsWith("!/dup.txt!~1");
    }
    assert(sawFirst && sawSecond);
    assert(sawBang);
    foreach (entry; entries)
        assert(entry.id.length > 0);

    auto memberTree = loadCatalogArchiveMemberTreePage(root, containerPath);
    assert(memberTree.entries.length == 3);
    string secondId;
    foreach (entry; memberTree.entries)
        if (entry.referenceId.endsWith("!/dup.txt!~1"))
            secondId = entry.referenceId;
    assert(secondId.length > 0);
    auto preview = acquireCatalogArchiveMemberPreview(root, secondId);
    scope (exit)
        if (preview.lease !is null)
            preview.lease.release();
    assert(readText(preview.lease.path) == "second");
}

@("JSON archive scanning prompts once and persists the password mapping")
unittest
{
    import dosierskanilo.model.namedbinaryblob : serializeDataClassArrayFile;
    import std.datetime.systime : SysTime;
    import std.file : exists, getSize, mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.process : Config, execute;
    import std.uuid : randomUUID;

    auto root = buildPath(tempDir(), "gui-json-archive-password-"
        ~ randomUUID().toString());
    mkdirRecurse(root);
    scope (exit)
    {
        if (exists(root))
            rmdirRecurse(root);
    }

    write(buildPath(root, "payload.txt"), "archive payload\n");
    auto archivePath = buildPath(root, "private.zip");
    assert(execute(["zip", "-q", "-P", "catalog-secret", "private.zip",
        "payload.txt"], null, Config.none, size_t.max, root).status == 0);
    auto jsonPath = buildPath(root, "catalog.json");
    auto blob = new NamedBinaryBlob("private.zip", archivePath.getSize,
        SysTime(1_234_567));
    serializeDataClassArrayFile(jsonPath, [blob]);

    size_t prompts;
    ArchivePasswordCallback callback = (string requestedPath, string reason,
        out string password) {
        assert(requestedPath == archivePath);
        assert(reason.length > 0);
        ++prompts;
        password = "catalog-secret";
        return true;
    };
    auto summary = scanDocumentArchives(jsonPath, callback);
    assert(prompts == 1);
    assert(summary.archivesUpdated == 1);
    assert(summary.failed == 0);

    auto scanned = deserializeDataClassJsonFile(jsonPath);
    import std.string : startsWith;
    NamedBinaryBlob scannedArchive;
    bool hasVirtualMember;
    foreach (scannedBlob; scanned)
    {
        foreach (spec; scannedBlob.fileSpecs)
        {
            if (spec is null)
                continue;
            if (spec.fileName == "private.zip")
                scannedArchive = scannedBlob;
            else if (spec.fileName.startsWith("private.zip!/payload.txt"))
                hasVirtualMember = true;
        }
    }
    assert(scannedArchive !is null);
    assert(scannedArchive.archivePassword == "catalog-secret");
    assert(hasVirtualMember);

    setDocumentArchivePassword(jsonPath, "private.zip", "");
    auto cleared = deserializeDataClassJsonFile(jsonPath);
    foreach (clearedBlob; cleared)
        foreach (spec; clearedBlob.fileSpecs)
            if (spec !is null && spec.fileName == "private.zip")
                assert(clearedBlob.archivePassword.length == 0);

    size_t selectedPrompts;
    ArchivePasswordCallback selectedCallback = (string requestedPath,
        string reason, out string password) {
        ++selectedPrompts;
        password = "catalog-secret";
        return true;
    };
    auto selectedSummary = scanDocumentArchive(jsonPath, "private.zip",
        selectedCallback);
    // The first scan's shared-cache extraction avoids a redundant password prompt.
    assert(selectedPrompts == 0);
    assert(selectedSummary.blobsVisited == 1);
    assert(selectedSummary.archivesUpdated == 1);
}

@("JSON archive member previews use leased cache files and preserve virtual paths")
unittest
{
    import std.file : exists, mkdirRecurse, readText, rmdirRecurse, tempDir;
    import std.path : buildPath;
    import std.process : Config, execute;
    import std.uuid : randomUUID;

    auto root = buildPath(tempDir(), "gui-json-member-preview-"
        ~ randomUUID().toString());
    mkdirRecurse(root);
    scope (exit)
        if (exists(root))
            rmdirRecurse(root);

    auto archivePath = buildPath(root, "bundle!.zip");
    const auto createArchive = "import sys, zipfile; z=zipfile.ZipFile(sys.argv[1], 'w'); "
        ~ "z.writestr('preview.txt', 'first occurrence\\n'); "
        ~ "z.writestr('preview.txt', 'second occurrence\\n'); z.close()";
    assert(execute(["python3", "-c", createArchive, archivePath], null,
        Config.none).status == 0);

    auto firstPreview = acquireJsonArchiveMemberPreview(
        buildPath(root, "catalog.json"), archivePath, "preview.txt", 0);
    scope (exit)
    {
        if (firstPreview.lease !is null)
            firstPreview.lease.release();
    }
    auto secondPreview = acquireJsonArchiveMemberPreview(
        buildPath(root, "catalog.json"), archivePath, "preview.txt", 1);
    scope (exit)
        if (secondPreview.lease !is null)
            secondPreview.lease.release();

    const auto encodedArchivePath = escapeArchiveVirtualPath(archivePath);
    assert(firstPreview.virtualPath == encodedArchivePath ~ "!/preview.txt!~0");
    assert(secondPreview.virtualPath == encodedArchivePath ~ "!/preview.txt!~1");
    assert(firstPreview.size == "first occurrence\n".length);
    assert(secondPreview.size == "second occurrence\n".length);
    assert(readText(firstPreview.lease.path) == "first occurrence\n");
    assert(readText(secondPreview.lease.path) == "second occurrence\n");
    assert(firstPreview.lease.path != secondPreview.lease.path);
    assert(firstPreview.lease.path != archivePath);
}

@("JSON archive member tree pages preserve duplicate virtual identities")
unittest
{
    import dosierarkivo.archive : appendArchiveVirtualPath;
    import dosierskanilo.model.filespec : FileSpec;
    import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob;

    auto archiveBlob = new NamedBinaryBlob();
    archiveBlob.fileSpecsUseArchiveVirtualGrammar = true;
    archiveBlob.fileSpecs = [new FileSpec("archives/bundle!!.zip", "")];
    BlobRow archiveRow;
    archiveRow.sourceBlob = archiveBlob;

    BlobRow first;
    first.sourceBlob = new NamedBinaryBlob();
    first.sourceBlob.fileSpecsUseArchiveVirtualGrammar = true;
    first.sourceBlob.fileSpecs = [new FileSpec(appendArchiveVirtualPath(
        "archives/bundle!!.zip", "same.txt", 0), "")];
    first.fileSize = 5;
    BlobRow second;
    second.sourceBlob = new NamedBinaryBlob();
    second.sourceBlob.fileSpecsUseArchiveVirtualGrammar = true;
    second.sourceBlob.fileSpecs = [new FileSpec(appendArchiveVirtualPath(
        "archives/bundle!!.zip", "same.txt", 1), "")];
    second.fileSize = 6;
    BlobRow nested;
    nested.sourceBlob = new NamedBinaryBlob();
    nested.sourceBlob.fileSpecsUseArchiveVirtualGrammar = true;
    nested.sourceBlob.fileSpecs = [new FileSpec(
        "archives/bundle!!.zip!/inner.zip!/deep.txt", "")];
    nested.fileSize = 9;

    auto firstPage = loadJsonArchiveMemberTreePage("archives/bundle!.zip",
        [archiveRow, first, second, nested], 0, 1);
    assert(firstPage.entries.length == 1);
    assert(firstPage.hasMore);
    assert(firstPage.entries[0].virtualPath
        == "archives/bundle!!.zip!/same.txt!~0");
    auto secondPage = loadJsonArchiveMemberTreePage("archives/bundle!.zip",
        [archiveRow, first, second, nested], firstPage.nextOffset, 1);
    assert(secondPage.entries.length == 1);
    assert(!secondPage.hasMore);
    assert(secondPage.entries[0].virtualPath
        == "archives/bundle!!.zip!/same.txt!~1");
}
