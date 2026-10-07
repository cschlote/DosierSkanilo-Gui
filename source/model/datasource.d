/** Shared data-source adapter for JSON files and SQLite repositories. */
module model.datasource;

import std.file : exists, isDir;
import std.conv : to;
import std.datetime.systime : Clock;
import std.exception : enforce;
import std.path : baseName, dirName;
import std.string : empty;

import dosierarkivo.archive : ArchivePasswordCallback,
    ArchivePasswordCancelledException;
import dosierskanilo;
import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob,
    DATA_CLASS_VERSION3, NamedBinaryBlobCatalog, deserializeDataClassJsonFile,
    updateArchives;
import dosierskanilo.service.storageio : writeStorageJsonFile;
import ui.contextpaths : resolveDocumentSourcePath;
import model.treeprojection : DirectoryNode, DirectorySource, FileCursor, FileFilter, FileInput, FileNode,
    FilePage, FileSortOrder, NestedFileNode, DirectoryTree, ProjectedDirectorySource,
    buildDirectoryTree;

/** One bounded source result page. */
struct SourcePage
{
    NamedBinaryBlob[] blobs;
    long[] blobIds;
    RepositoryBlobFlags[] flags;
    size_t offset;
    size_t total;
    long nextBlobId;
    bool hasMore;
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
                inputs ~= FileInput(spec.fileName, cast(ulong) blob.fileSize);
        }
        if (blob.fileSpecs.length == 0 && blob.getFirstFileName.length > 0)
            inputs ~= FileInput(blob.getFirstFileName, cast(ulong) blob.fileSize);
    }
    return buildDirectoryTree(inputs);
}

/** Directory source backed by bounded SQLite repository queries. */
final class RepositoryDirectorySource : DirectorySource
{
    private string repositoryPath;
    private DirectoryNode rootNode;

    this(string path)
    {
        repositoryPath = path;
        auto repository = Repository.open(path);
        scope (exit)
            repository.close();
        auto summary = repository.rootSummary();
        rootNode = DirectoryNode("root", "", baseName(repository.rootPath), "",
            summary.childDirectoryCount, summary.fileCount, summary.aggregateSize);
    }

    override DirectoryNode root()
    {
        return rootNode;
    }

    override DirectoryNode[] listDirectories(string parentId, FileFilter filter = FileFilter())
    {
        auto repository = Repository.open(repositoryPath);
        scope (exit)
            repository.close();
        RepositoryDirectoryQuery query;
        query.parentId = parentId == "root" ? 0 : to!long(parentId);
        query.limit = size_t.max;
        query.text = filter.text;
        query.caseSensitive = filter.caseSensitive;
        query.video = filter.video;
        query.audio = filter.audio;
        query.image = filter.image;
        query.textStream = filter.textStream;
        query.mediaNegated = filter.mediaNegated;
        query.fileType = filter.fileType;
        query.archive = filter.archive;
        query.torrent = filter.torrent;
        DirectoryNode[] result;
        foreach (directory; repository.listDirectories(query))
        {
            result ~= DirectoryNode("" ~ directory.id.to!string,
                directory.parentId == 0 ? "root" : directory.parentId.to!string,
                directory.name, directory.relativePath, directory.childDirectoryCount,
                directory.fileCount, directory.aggregateSize);
        }
        return result;
    }

    override bool hasMatchingFileInDirectory(string directoryId,
        FileFilter filter = FileFilter())
    {
        return listFilteredFilesPage(directoryId, FileCursor(), 1, filter).files.length > 0;
    }

    override FileNode[] listFiles(string directoryId, size_t offset = 0, size_t limit = 250,
        string filter = "")
    {
        auto repository = Repository.open(repositoryPath);
        scope (exit)
            repository.close();
        RepositoryFileQuery query;
        query.directoryId = directoryId == "root" ? 0 : to!long(directoryId);
        query.offset = offset;
        query.limit = limit;
        query.text = filter;
        FileNode[] result;
        foreach (file; repository.listFiles(query))
        {
            FileNode node;
            node.id = file.blobId.to!string;
            node.cursorId = file.id.to!string;
            node.directoryId = directoryId;
            node.name = file.name;
            node.relativePath = file.relativePath;
            node.size = file.size;
            node.hasFileType = file.hasFileType;
            node.hasMedia = file.hasMedia;
            node.hasVideo = file.hasVideo;
            node.hasAudio = file.hasAudio;
            node.hasImage = file.hasImage;
            node.hasText = file.hasText;
            node.hasArchive = file.hasArchive;
            node.hasTorrent = file.hasTorrent;
            result ~= node;
        }
        return result;
    }

    override FilePage listFilesPage(string directoryId, FileCursor cursor = FileCursor(),
        size_t limit = 250, string filter = "")
    {
        auto repository = Repository.open(repositoryPath);
        scope (exit)
            repository.close();
        RepositoryFileQuery query;
        query.directoryId = directoryId == "root" ? 0 : to!long(directoryId);
        query.limit = limit;
        query.text = filter;
        query.afterPath = cursor.relativePath;
        query.afterId = cursor.id.length > 0 ? to!long(cursor.id) : 0;
        auto page = repository.listFilesPage(query);
        FilePage result;
        result.hasMore = page.hasMore;
        foreach (file; page.files)
        {
            FileNode node;
            node.id = file.blobId.to!string;
            node.cursorId = file.id.to!string;
            node.directoryId = directoryId;
            node.name = file.name;
            node.relativePath = file.relativePath;
            node.size = file.size;
            node.hasFileType = file.hasFileType;
            node.hasMedia = file.hasMedia;
            node.hasVideo = file.hasVideo;
            node.hasAudio = file.hasAudio;
            node.hasImage = file.hasImage;
            node.hasText = file.hasText;
            node.hasArchive = file.hasArchive;
            node.hasTorrent = file.hasTorrent;
            result.files ~= node;
        }
        if (page.hasMore)
            result.nextCursor = FileCursor(page.nextCursor.relativePath,
                page.nextCursor.id.to!string);
        return result;
    }

    override FilePage listFilteredFilesPage(string directoryId, FileCursor cursor = FileCursor(),
        size_t limit = 250, FileFilter filter = FileFilter(),
        FileSortOrder sortOrder = FileSortOrder.pathAscending)
    {
        auto repository = Repository.open(repositoryPath);
        scope (exit)
            repository.close();
        RepositoryFileQuery query;
        query.directoryId = directoryId == "root" ? 0 : to!long(directoryId);
        query.limit = limit;
        query.text = filter.text;
        query.caseSensitive = filter.caseSensitive;
        query.video = filter.video;
        query.audio = filter.audio;
        query.image = filter.image;
        query.textStream = filter.textStream;
        query.mediaNegated = filter.mediaNegated;
        query.fileType = filter.fileType;
        query.archive = filter.archive;
        query.torrent = filter.torrent;
        query.sortOrder = cast(RepositoryFileSortOrder) sortOrder;
        query.afterPath = cursor.relativePath;
        query.afterId = cursor.id.length > 0 ? to!long(cursor.id) : 0;
        query.afterSize = cursor.size;
        auto page = repository.listFilesPage(query);
        FilePage result;
        result.hasMore = page.hasMore;
        foreach (file; page.files)
        {
            FileNode node;
            node.id = file.blobId.to!string;
            node.cursorId = file.id.to!string;
            node.directoryId = directoryId;
            node.name = file.name;
            node.relativePath = file.relativePath;
            node.size = file.size;
            node.hasFileType = file.hasFileType;
            node.hasMedia = file.hasMedia;
            node.hasVideo = file.hasVideo;
            node.hasAudio = file.hasAudio;
            node.hasImage = file.hasImage;
            node.hasText = file.hasText;
            node.hasArchive = file.hasArchive;
            node.hasTorrent = file.hasTorrent;
            result.files ~= node;
        }
        if (page.hasMore)
            result.nextCursor = FileCursor(page.nextCursor.relativePath,
                page.nextCursor.id.to!string, page.nextCursor.size);
        return result;
    }

    override FilePage listPreviousFilteredFilesPage(string directoryId, FileCursor cursor,
        size_t limit = 250, FileFilter filter = FileFilter(),
        FileSortOrder sortOrder = FileSortOrder.pathAscending)
    {
        auto repository = Repository.open(repositoryPath);
        scope (exit)
            repository.close();
        RepositoryFileQuery query;
        query.directoryId = directoryId == "root" ? 0 : to!long(directoryId);
        query.limit = limit;
        query.text = filter.text;
        query.caseSensitive = filter.caseSensitive;
        query.video = filter.video;
        query.audio = filter.audio;
        query.image = filter.image;
        query.textStream = filter.textStream;
        query.mediaNegated = filter.mediaNegated;
        query.fileType = filter.fileType;
        query.archive = filter.archive;
        query.torrent = filter.torrent;
        query.sortOrder = cast(RepositoryFileSortOrder) sortOrder;
        auto backendCursor = RepositoryFileCursor(cursor.relativePath,
            to!long(cursor.id), cursor.size);
        auto page = repository.previousFilesPage(query, backendCursor);
        FilePage result;
        result.hasMore = page.hasMore;
        foreach (file; page.files)
        {
            FileNode node;
            node.id = file.blobId.to!string;
            node.cursorId = file.id.to!string;
            node.directoryId = directoryId;
            node.name = file.name;
            node.relativePath = file.relativePath;
            node.size = file.size;
            node.hasFileType = file.hasFileType;
            node.hasMedia = file.hasMedia;
            node.hasVideo = file.hasVideo;
            node.hasAudio = file.hasAudio;
            node.hasImage = file.hasImage;
            node.hasText = file.hasText;
            node.hasArchive = file.hasArchive;
            node.hasTorrent = file.hasTorrent;
            result.files ~= node;
        }
        if (page.hasMore)
            result.nextCursor = FileCursor(page.nextCursor.relativePath,
                page.nextCursor.id.to!string, page.nextCursor.size);
        return result;
    }

    override void close()
    {
        // Each operation opens and closes its own repository connection.
    }
}

/** Open a repository-backed directory source for the GUI tree. */
DirectorySource openRepositoryDirectorySource(string path)
{
    return new RepositoryDirectorySource(path);
}

private class ConcurrentSourceQueryResults
{
    size_t directoryCount;
    size_t fileCount;
    size_t detailLoads;
    string treeError;
    string detailError;
}

/** Load one bounded page of archive entries for a repository blob. */
NestedFileNode[] loadRepositoryArchiveEntries(string path, long blobId,
    size_t offset = 0, size_t limit = 250)
{
    auto repository = Repository.open(path);
    scope (exit)
        repository.close();
    RepositoryArchiveQuery query;
    query.blobId = blobId;
    query.offset = offset;
    query.limit = limit;
    NestedFileNode[] result;
    foreach (entry; repository.listArchiveEntries(query))
        result ~= NestedFileNode(entry.id.to!string, entry.name, entry.name,
            entry.size, entry.modifiedAt);
    return result;
}

/** Load one bounded page of torrent files for a repository blob. */
NestedFileNode[] loadRepositoryTorrentFiles(string path, long blobId,
    size_t offset = 0, size_t limit = 250)
{
    auto repository = Repository.open(path);
    scope (exit)
        repository.close();
    RepositoryTorrentQuery query;
    query.blobId = blobId;
    query.offset = offset;
    query.limit = limit;
    NestedFileNode[] result;
    foreach (file; repository.listTorrentFiles(query))
        result ~= NestedFileNode(file.id.to!string, file.relativePath,
            file.relativePath, file.size, "");
    return result;
}

/** Load one GUI document from JSON or an SQLite repository. */
NamedBinaryBlob[] loadDocumentSource(string path)
{
    if (!isRepositorySource(path))
        return deserializeDataClassJsonFile(path);

    auto repository = Repository.open(path);
    scope (exit)
        repository.close();

    JsonExportOptions options;
    options.absolutePaths = true;
    return repository.loadCatalog(options);
}

/** Store or remove one password after resolving the user's filename to a blob. */
void setDocumentArchivePassword(string sourcePath, string fileName, string password)
{
    if (isRepositorySource(sourcePath))
    {
        auto repository = Repository.open(sourcePath);
        scope (exit)
            repository.close();
        repository.setArchivePasswordForPath(fileName, password);
        return;
    }

    auto blobs = deserializeDataClassJsonFile(sourcePath);
    auto requestedPath = resolveDocumentSourcePath(sourcePath, fileName);
    size_t[] exactMatches;
    size_t[] nameMatches;
    foreach (index, blob; blobs)
    {
        foreach (spec; blob.fileSpecs)
        {
            if (spec is null)
                continue;
            auto knownPath = resolveDocumentSourcePath(sourcePath, spec.fileName);
            if (knownPath == requestedPath || spec.fileName == fileName)
            {
                exactMatches ~= index;
                break;
            }
            if (baseName(fileName) == fileName
                && baseName(spec.fileName) == fileName)
            {
                nameMatches ~= index;
                break;
            }
        }
    }
    auto matches = exactMatches.length > 0 ? exactMatches : nameMatches;
    if (matches.length == 0)
        throw new Exception("No catalog file matches: " ~ fileName);
    if (matches.length > 1)
        throw new Exception("Filename is ambiguous in this catalog: " ~ fileName);
    blobs[matches[0]].archivePassword = password;
    writeJsonCatalog(sourcePath, blobs);
}

/** Scan archive entries in a JSON catalog or SQLite repository. */
MetadataSummary scanDocumentArchives(string sourcePath,
    ArchivePasswordCallback passwordCallback)
{
    if (isRepositorySource(sourcePath))
    {
        auto repository = Repository.open(sourcePath);
        scope (exit)
            repository.close();
        MetadataScanOptions options;
        options.scanArchives = true;
        options.deepArchiveScan = true;
        options.rescan = true;
        options.archivePasswordCallback = passwordCallback;
        return repository.updateMetadata(options);
    }

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
    writeJsonCatalog(sourcePath, blobs);
    return summary;
}

/** Scan archive entries for the single file selected in a source context menu. */
MetadataSummary scanDocumentArchive(string sourcePath, string filePath,
    ArchivePasswordCallback passwordCallback)
{
    if (isRepositorySource(sourcePath))
    {
        auto repository = Repository.open(sourcePath);
        scope (exit)
            repository.close();
        MetadataScanOptions options;
        options.scanArchives = true;
        options.deepArchiveScan = true;
        options.rescan = true;
        options.archivePasswordCallback = passwordCallback;
        options.filePath = filePath;
        auto summary = repository.updateMetadata(options);
        if (summary.blobsVisited == 0)
            throw new Exception("No repository file matches: " ~ filePath);
        return summary;
    }

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
    writeJsonCatalog(sourcePath, blobs);
    return summary;
}

private void writeJsonCatalog(string sourcePath, NamedBinaryBlob[] blobs)
{
    auto wrapper = NamedBinaryBlobCatalog(DATA_CLASS_VERSION3, blobs);
    enforce(writeStorageJsonFile(sourcePath, wrapper, ".json",
        Clock.currTime.toISOExtString, dirName(sourcePath)),
        "Failed to safely save JSON archive metadata to " ~ sourcePath);
}

/** Load full details for one repository blob. */
NamedBinaryBlob loadDocumentDetails(string path, long blobId)
{
    auto repository = Repository.open(path);
    scope (exit)
        repository.close();
    JsonExportOptions options;
    options.absolutePaths = true;
    options.includeArchiveEntries = false;
    options.includeTorrentFiles = false;
    return repository.loadBlobDetails(blobId, options);
}

/** Load one bounded page from a JSON file or SQLite repository. */
SourcePage loadDocumentPage(string path, size_t offset, size_t limit,
    SourceQuery query = SourceQuery())
{
    if (!isRepositorySource(path))
    {
        auto allBlobs = deserializeDataClassJsonFile(path);
        auto end = offset + limit;
        if (end > allBlobs.length)
            end = allBlobs.length;
        if (offset > allBlobs.length)
            offset = allBlobs.length;
        return SourcePage(allBlobs[offset .. end].dup, [], [], offset, allBlobs.length);
    }

    auto repository = Repository.open(path);
    scope (exit)
        repository.close();
    JsonExportOptions options;
    options.absolutePaths = true;
    options.includeDetails = false;
    RepositoryQueryOptions repositoryQuery;
    repositoryQuery.offset = offset;
    repositoryQuery.limit = limit;
    repositoryQuery.text = query.text;
    repositoryQuery.caseSensitive = query.caseSensitive;
    repositoryQuery.video = query.video;
    repositoryQuery.audio = query.audio;
    repositoryQuery.image = query.image;
    repositoryQuery.textStream = query.textStream;
    repositoryQuery.mediaNegated = query.mediaNegated;
    repositoryQuery.fileType = query.fileType;
    repositoryQuery.archive = query.archive;
    repositoryQuery.torrent = query.torrent;
    if (limit == size_t.max)
    {
        auto queryTotal = repository.countCatalogQuery(repositoryQuery);
        repositoryQuery.limit = queryTotal == 0 ? 1 : queryTotal;
    }
    auto page = repository.loadCatalogQueryPageWithIds(repositoryQuery, options);
    auto total = page.total;
    return SourcePage(page.blobs, page.blobIds, page.flags,
        offset, total);
}

/** Load one source-opaque repository catalog chunk using its stable blob cursor. */
SourcePage loadDocumentCursorPage(string path, long afterBlobId, size_t limit,
    SourceQuery query = SourceQuery())
{
    auto repository = Repository.open(path);
    scope (exit)
        repository.close();

    RepositoryQueryOptions options;
    options.limit = limit;
    options.afterBlobId = afterBlobId;
    options.useCursor = true;
    options.text = query.text;
    options.caseSensitive = query.caseSensitive;
    options.video = query.video;
    options.audio = query.audio;
    options.image = query.image;
    options.textStream = query.textStream;
    options.mediaNegated = query.mediaNegated;
    options.fileType = query.fileType;
    options.archive = query.archive;
    options.torrent = query.torrent;

    JsonExportOptions exportOptions;
    exportOptions.absolutePaths = true;
    exportOptions.includeDetails = false;
    auto page = repository.loadCatalogQueryCursorPage(options, exportOptions);
    SourcePage result;
    result.blobs = page.blobs;
    result.blobIds = page.blobIds;
    result.flags = page.flags;
    result.total = page.total;
    result.nextBlobId = page.nextCursor;
    result.hasMore = page.hasMore;
    return result;
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
    auto page = loadDocumentPage(root, 0, 10);
    assert(page.total == 0);
    assert(page.blobs.length == 0);

    repository = Repository.open(root);
    write(buildPath(root, "one.txt"), "one");
    write(buildPath(root, "two.txt"), "two");
    write(buildPath(root, "three.txt"), "three");
    repository.scan();
    assert(repository.blobCount == 3, "blobs=" ~ to!string(repository.blobCount));
    assert(repository.countCatalogQuery(RepositoryQueryOptions()) == 3,
        "query=" ~ to!string(repository.countCatalogQuery(RepositoryQueryOptions())));
    repository.close();
    auto populated = loadDocumentPage(root, 0, 2);
    assert(populated.total == 3, "total=" ~ to!string(populated.total));
    assert(populated.blobs.length == 2);
    assert(populated.blobIds.length == 2);
    assert(populated.flags.length == 2);
    assert(!populated.flags[0].hasMedia);
    auto tree = loadDocumentTree(root);
    assert(tree.files.length == 3);
    auto directorySource = openRepositoryDirectorySource(root);
    assert(directorySource.root().id == "root");
    assert(directorySource.root().name == baseName(root));
    assert(directorySource.root().fileCount == 3);
    assert(directorySource.root().aggregateSize == 11);
    assert(directorySource.listFiles("root").length == 3);
    assert(directorySource.listFiles("root", 0, 250, "one.txt").length == 1);
    auto catalogPage = loadDocumentCursorPage(root, 0, 1);
    assert(catalogPage.blobs.length == 1);
    assert(catalogPage.hasMore);
    auto nextCatalogPage = loadDocumentCursorPage(root, catalogPage.nextBlobId, 1);
    assert(nextCatalogPage.blobs.length == 1);
    assert(nextCatalogPage.blobIds[0] > catalogPage.blobIds[0]);
    auto finalCatalogPage = loadDocumentCursorPage(root, nextCatalogPage.nextBlobId, 10);
    assert(finalCatalogPage.blobs.length == 1);
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
    auto filtered = loadDocumentPage(root, 0, 250, filteredQuery);
    assert(filtered.total == 1);
    assert(filtered.blobs.length == 1);
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
    auto blobId = to!long(selectedFile.id);
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
                if (loadDocumentDetails(root, blobId) !is null)
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

@("repository detail adapter keeps archive and torrent entries lazy")
unittest
{
    import std.file : copy, exists, mkdirRecurse, rmdirRecurse, tempDir, write;
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

    auto archiveDetails = loadDocumentDetails(root, archiveFile.blobId);
    assert(archiveDetails !is null);
    assert(archiveDetails.archiveSpecs.length == 0);
    assert(loadRepositoryArchiveEntries(root, archiveFile.blobId).length > 0);

    auto torrentDetails = loadDocumentDetails(root, torrentFile.blobId);
    assert(torrentDetails !is null && torrentDetails.torrentInfo !is null);
    assert(torrentDetails.torrentInfo.files.length == 0);
    assert(loadRepositoryTorrentFiles(root, torrentFile.blobId).length > 0);
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

    auto archiveProbe = loadRepositoryArchiveEntries(root, archiveFile.blobId,
        0, 251);
    assert(archiveProbe.length == 251);
    auto archivePage = archiveProbe[0 .. 250];
    assert(archivePage.length == 250);
    auto archiveContinuation = loadRepositoryArchiveEntries(root,
        archiveFile.blobId, archivePage.length, 251);
    assert(archiveContinuation.length == 1);
    assert(archiveContinuation[0].relativePath.endsWith("folder/entry-250.txt"));

    auto torrentProbe = loadRepositoryTorrentFiles(root, torrentFile.blobId,
        0, 251);
    assert(torrentProbe.length == 251);
    auto torrentPage = torrentProbe[0 .. 250];
    assert(torrentPage.length == 250);
    auto torrentContinuation = loadRepositoryTorrentFiles(root,
        torrentFile.blobId, torrentPage.length, 251);
    assert(torrentContinuation.length == 1);
    assert(torrentContinuation[0].relativePath == "test/folder/entry-250.txt");
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
    assert(scanned.length == 1);
    assert(scanned[0].archivePassword == "catalog-secret");
    assert(scanned[0].archiveSpecs.length == 1);
    assert(scanned[0].archiveSpecs[0].fileName == "payload.txt");

    setDocumentArchivePassword(jsonPath, "private.zip", "");
    auto cleared = deserializeDataClassJsonFile(jsonPath);
    assert(cleared[0].archivePassword.length == 0);

    size_t selectedPrompts;
    ArchivePasswordCallback selectedCallback = (string requestedPath,
        string reason, out string password) {
        ++selectedPrompts;
        password = "catalog-secret";
        return true;
    };
    auto selectedSummary = scanDocumentArchive(jsonPath, "private.zip",
        selectedCallback);
    assert(selectedPrompts == 1);
    assert(selectedSummary.blobsVisited == 1);
    assert(selectedSummary.archivesUpdated == 1);
}
