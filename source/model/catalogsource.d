/** Storage-neutral directory source over the catalog backend contract.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module model.catalogsource;

import std.exception : enforce;
import std.path : baseName;

import dosierskanilo.catalogbackend : CatalogBackend, CatalogDirectory,
    CatalogDirectoryPage, CatalogDirectoryQuery, CatalogFile, CatalogFilePage,
    CatalogFileQuery, CatalogFilter, CatalogPageRequest, CatalogRootSummary,
    CatalogSortOrder, DirectoryId;
import dosierskanilo.operations : OperationTarget;
import dosierskanilo.sqlitecatalogbackend : DefaultCatalogBackendFactory;
import model.treeprojection : DirectoryNode, DirectorySource, FileCursor,
    FileFilter, FileNode, FilePage, FileSortOrder, isArchivePathCandidate;

/// Backend page size used when paging through directory and file results.
private enum pageSize = 250;

/** Open the storage-neutral backend for one repository root.
 *
 * Params:
 *     repositoryPath = Filesystem path of the repository root to open.
 * Returns: An open repository-backed catalog backend.
 * Throws: Backend construction errors when the repository cannot be opened.
 */
CatalogBackend openCatalogBackend(string repositoryPath)
{
    return new DefaultCatalogBackendFactory().open(
        OperationTarget.repositoryTarget(repositoryPath));
}

/** Open the storage-neutral backend for one JSON catalog file.
 *
 * Params:
 *     catalogPath = Filesystem path of the JSON catalog to open.
 * Returns: An open JSON-backed catalog backend.
 * Throws: Backend construction errors when the catalog cannot be opened.
 */
CatalogBackend openJsonCatalogBackend(string catalogPath)
{
    return new DefaultCatalogBackendFactory().open(
        OperationTarget.jsonTarget(catalogPath));
}

/** Wrap an already opened backend for tree queries without owning it.
 *
 * Params:
 *     backend = Open catalog backend to expose through the directory source.
 *     ownBackend = Whether the returned source closes `backend` on `close()`.
 * Returns: A directory source backed by `backend`.
 */
DirectorySource openCatalogDirectorySource(CatalogBackend backend,
    bool ownBackend = false)
{
    return new CatalogDirectorySource(backend, ownBackend);
}

/**
 * Directory source backed by a catalog backend.
 *
 * Directory and file nodes are addressed by their source-relative paths, so
 * restored state resolves against a freshly opened backend instance. The source
 * closes the backend only when constructed with `ownBackend = true`; wrapper
 * sources leave backend lifetime to the caller.
 */
final class CatalogDirectorySource : DirectorySource
{
    /// Backend queried for directory, file, and detail data.
    private CatalogBackend backend;
    /// Whether `close()` also closes `backend`; false for borrowed backends.
    private bool ownBackend;
    /// Precomputed root node exposed by `root()`.
    private DirectoryNode rootNode;

    /** Wrap an open backend and compute its root node summary.
     *
     * Params:
     *     backend = Open catalog backend to query; must not be null.
     *     ownBackend = Whether this source owns and closes the backend.
     * Throws: `CatalogBackendException` when the backend cannot report source
     *     information or root aggregates.
     */
    this(CatalogBackend backend, bool ownBackend = true)
    {
        this.backend = backend;
        this.ownBackend = ownBackend;
        const info = backend.sourceInfo();
        const summary = backend.rootSummary();
        rootNode = DirectoryNode("root", "", info.displayName.length > 0
            ? info.displayName : baseName(backend.target().repositoryRoot), "",
            summary.childDirectoryCount, summary.fileReferenceCount,
            summary.aggregateSize);
    }

    /** The backend used for detail loads by callers that reuse this source.
     *
     * Returns: The wrapped backend; `null` after `close()` has been called.
     */
    @property ref CatalogBackend catalog() return
    {
        return backend;
    }

    /** Return the precomputed root directory node for this source.
     *
     * Returns: Root node whose `id` is `"root"` and whose name is the backend
     *     display name, falling back to the repository basename.
     */
    override DirectoryNode root()
    {
        return rootNode;
    }

    /** List all immediate child directories of one parent.
     *
     * Backend pages are fetched until no more results remain.
     *
     * Params:
     *     parentId = Directory ID (relative path) or `"root"`/empty for the
     *         source root.
     *     filter = Optional file filter used to include only directories with
     *         matching files.
     * Returns: Matching child directory nodes, or `null` when `parentId`
     *     cannot be resolved.
     * Throws: `CatalogBackendException` when a backend query fails.
     */
    override DirectoryNode[] listDirectories(string parentId,
        FileFilter filter = FileFilter())
    {
        CatalogDirectoryQuery query;
        if (!resolveDirectoryId(parentId, query.parentId))
            return null;
        query.filter = catalogFilter(filter);
        CatalogDirectory[] directories;
        CatalogPageRequest request;
        request.limit = pageSize;
        while (true)
        {
            const page = backend.listDirectories(query, request);
            directories ~= page.directories;
            if (!page.hasMore)
                break;
            request = CatalogPageRequest(pageSize, page.nextCursor);
        }

        DirectoryNode[] result;
        result.reserve(directories.length);
        foreach (directory; directories)
            result ~= DirectoryNode(directoryPath(directory.relativePath),
                parentId, directory.name, directory.relativePath,
                directory.childDirectoryCount, directory.fileCount,
                directory.aggregateSize);
        return result;
    }

    /** Report whether a directory contains at least one matching file.
     *
     * Only the first backend result is requested, so this is a cheap
     * existence check.
     *
     * Params:
     *     directoryId = Directory ID (relative path) or `"root"`/empty for the
     *         source root.
     *     filter = Optional file filter the candidate file must satisfy.
     * Returns: `true` when at least one matching file exists; `false` for an
     *     unresolved directory or no match.
     * Throws: `CatalogBackendException` when the backend query fails.
     */
    override bool hasMatchingFileInDirectory(string directoryId,
        FileFilter filter = FileFilter())
    {
        CatalogFileQuery query;
        if (!resolveDirectoryId(directoryId, query.directoryId))
            return false;
        query.filter = catalogFilter(filter);
        CatalogPageRequest request;
        request.limit = 1;
        return backend.listFiles(query, request).files.length > 0;
    }

    /** List files below one directory using offset/limit slicing.
     *
     * Backend pages are fetched as needed and the requested window is cut
     * from the combined result. `filter` only constrains the path text.
     *
     * Params:
     *     directoryId = Directory ID (relative path) or `"root"`/empty for the
     *         source root.
     *     offset = Number of matching files to skip.
     *     limit = Maximum number of files to return.
     *     filter = Case-insensitive substring filter over file paths.
     * Returns: The requested file nodes, or `null` when `directoryId` cannot
     *     be resolved.
     * Throws: `CatalogBackendException` when a backend query fails.
     */
    override FileNode[] listFiles(string directoryId, size_t offset = 0,
        size_t limit = 250, string filter = "")
    {
        FileFilter fileFilter;
        fileFilter.text = filter;
        CatalogFileQuery query;
        if (!resolveDirectoryId(directoryId, query.directoryId))
            return null;
        query.filter = catalogFilter(fileFilter);

        FileNode[] result;
        CatalogPageRequest request;
        request.limit = pageSize;
        size_t matched;
        while (result.length < limit)
        {
            const page = backend.listFiles(query, request);
            foreach (file; page.files)
            {
                if (matched >= offset && result.length < limit)
                    result ~= fileNode(file, directoryId);
                ++matched;
            }
            if (!page.hasMore)
                break;
            request = CatalogPageRequest(pageSize, page.nextCursor);
        }
        return result;
    }

    /** List one path-ordered file page using a text-only filter.
     *
     * Params:
     *     directoryId = Directory ID (relative path) or `"root"`/empty for the
     *         source root.
     *     cursor = Position returned by a previous page, or
     *         `FileCursor.init` for the first page.
     *     limit = Maximum number of files to return; must be greater than zero.
     *     filter = Case-insensitive substring filter over file paths.
     * Returns: The requested page, or `FilePage.init` when `directoryId`
     *     cannot be resolved.
     * Throws: `Exception` when `limit` is zero and `CatalogBackendException`
     *     when the backend query fails.
     */
    override FilePage listFilesPage(string directoryId,
        FileCursor cursor = FileCursor(), size_t limit = 250, string filter = "")
    {
        FileFilter fileFilter;
        fileFilter.text = filter;
        return listFilteredFilesPage(directoryId, cursor, limit, fileFilter,
            FileSortOrder.pathAscending);
    }

    /** List one page of filtered files in the requested sort order.
     *
     * The cursor's relative path is used as a stateless anchor, so a stale
     * cursor simply yields an empty page.
     *
     * Params:
     *     directoryId = Directory ID (relative path) or `"root"`/empty for the
     *         source root.
     *     cursor = Anchor returned by a previous page, or `FileCursor.init`
     *         for the first page.
     *     limit = Maximum number of files to return; must be greater than zero.
     *     filter = Structured filter applied by the backend.
     *     sortOrder = Requested stable file order.
     * Returns: The page following the anchor, or `FilePage.init` when
     *     `directoryId` cannot be resolved.
     * Throws: `Exception` when `limit` is zero and `CatalogBackendException`
     *     when the backend query fails.
     */
    override FilePage listFilteredFilesPage(string directoryId,
        FileCursor cursor = FileCursor(), size_t limit = 250,
        FileFilter filter = FileFilter(),
        FileSortOrder sortOrder = FileSortOrder.pathAscending)
    {
        CatalogFileQuery query;
        if (!resolveDirectoryId(directoryId, query.directoryId))
            return FilePage.init;
        query.filter = catalogFilter(filter);
        query.sortOrder = catalogSortOrder(sortOrder);
        enforce(limit > 0, "File page size must be greater than zero.");
        return filePage(backend.listFilesFrom(query, cursor.relativePath, true,
            limit), directoryId, limit);
    }

    /** List one page of filtered files preceding an anchor in display order.
     *
     * The returned rows are ordered by the requested sort and end strictly
     * before the anchor path.
     *
     * Params:
     *     directoryId = Directory ID (relative path) or `"root"`/empty for the
     *         source root.
     *     cursor = Anchor returned by a previous page; must identify a file.
     *     limit = Maximum number of files to return; must be greater than zero.
     *     filter = Structured filter applied by the backend.
     *     sortOrder = Requested stable file order.
     * Returns: The page preceding the anchor, or `FilePage.init` when
     *     `directoryId` cannot be resolved.
     * Throws: `Exception` when `limit` is zero and `CatalogBackendException`
     *     when the backend query fails.
     */
    override FilePage listPreviousFilteredFilesPage(string directoryId,
        FileCursor cursor, size_t limit = 250, FileFilter filter = FileFilter(),
        FileSortOrder sortOrder = FileSortOrder.pathAscending)
    {
        CatalogFileQuery query;
        if (!resolveDirectoryId(directoryId, query.directoryId))
            return FilePage.init;
        query.filter = catalogFilter(filter);
        query.sortOrder = catalogSortOrder(sortOrder);
        enforce(limit > 0, "File page size must be greater than zero.");
        return filePage(backend.listFilesFrom(query, cursor.relativePath, false,
            limit), directoryId, limit);
    }

    /** Release the backend if this source owns it.
     *
     * Borrowed backends are left open. The field is cleared afterwards, so
     * repeated calls are safe.
     */
    override void close()
    {
        if (ownBackend && backend !is null)
            backend.close();
        backend = null;
    }

    /** Resolve a directory ID or relative path to a backend identity.
     *
     * Params:
     *     directoryId = Directory ID, relative path, or `"root"`/empty for the
     *         source root.
     *     resolved = Receives the resolved identity; invalid for the source
     *         root.
     * Returns: `true` when the directory exists or denotes the root; `false`
     *     for an unknown path.
     * Throws: `CatalogBackendException` when the backend lookup fails.
     */
    private bool resolveDirectoryId(string directoryId, out DirectoryId resolved)
    {
        if (directoryId == "root" || directoryId.length == 0)
        {
            resolved = DirectoryId.init;
            return true;
        }
        resolved = backend.resolveDirectory(directoryId);
        return resolved.isValid;
    }

    /** Map an empty root-relative path to the display ID `"root"`.
     *
     * Params:
     *     relativePath = Source-relative directory path.
     * Returns: `relativePath` unchanged, or `"root"` when it is empty.
     */
    private static string directoryPath(string relativePath)
    {
        return relativePath.length > 0 ? relativePath : "root";
    }

    /** Translate the GUI file filter into the backend filter model.
     *
     * Params:
     *     filter = GUI file filter to translate.
     * Returns: Backend filter with matching path, media, and type selectors.
     */
    private static CatalogFilter catalogFilter(FileFilter filter)
    {
        CatalogFilter result;
        result.pathText = filter.text;
        result.caseSensitive = filter.caseSensitive;
        result.video = filter.video;
        result.audio = filter.audio;
        result.image = filter.image;
        result.text = filter.textStream;
        result.mediaNegated = filter.mediaNegated;
        result.fileType = filter.fileType;
        result.archive = filter.archive;
        result.torrent = filter.torrent;
        return result;
    }

    /** Translate a GUI sort order into the equivalent backend sort order.
     *
     * Params:
     *     sortOrder = GUI file sort order to translate.
     * Returns: The matching backend sort order.
     */
    private static CatalogSortOrder catalogSortOrder(FileSortOrder sortOrder)
    {
        final switch (sortOrder)
        {
        case FileSortOrder.pathAscending:
            return CatalogSortOrder.pathAscending;
        case FileSortOrder.pathDescending:
            return CatalogSortOrder.pathDescending;
        case FileSortOrder.sizeAscending:
            return CatalogSortOrder.sizeAscending;
        case FileSortOrder.sizeDescending:
            return CatalogSortOrder.sizeDescending;
        }
    }

    /** Convert a backend file page into the GUI file page projection.
     *
     * Params:
     *     page = Backend page to convert.
     *     directoryId = Directory ID stored on every returned file node.
     *     limit = Requested page size; currently only used for the contract.
     * Returns: GUI page with converted nodes and a cursor pointing at the last
     *     returned file when more rows remain.
     */
    private FilePage filePage(CatalogFilePage page, string directoryId,
        size_t limit)
    {
        FilePage result;
        result.hasMore = page.hasMore;
        result.files.reserve(page.files.length);
        foreach (file; page.files)
            result.files ~= fileNode(file, directoryId);
        if (page.hasMore && result.files.length > 0)
        {
            const last = result.files[$ - 1];
            result.nextCursor = FileCursor(last.relativePath, last.cursorId,
                last.size);
        }
        return result;
    }

    /** Convert a backend file row into the GUI file node projection.
     *
     * Params:
     *     file = Backend file row to convert.
     *     directoryId = Directory ID stored on the returned node.
     * Returns: GUI node using the source-relative path as both ID and cursor
     *     ID; archive detection also considers the filename.
     */
    private static FileNode fileNode(CatalogFile file, string directoryId)
    {
        FileNode node;
        node.id = file.relativePath;
        node.cursorId = file.relativePath;
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
        node.hasArchive = file.hasArchive
            || isArchivePathCandidate(file.name);
        node.hasTorrent = file.hasTorrent;
        return node;
    }
}

@("catalog directory source mirrors repository tree semantics")
unittest
{
    import dosierskanilo : Repository;
    import std.file : mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto root = buildPath(tempDir(), "gui-catalog-source-"
        ~ randomUUID().toString());
    mkdirRecurse(root);
    scope (exit)
        rmdirRecurse(root);

    auto repository = Repository.initialize(root);
    scope (exit)
        repository.close();
    write(buildPath(root, "one.txt"), "one");
    write(buildPath(root, "two.txt"), "two");
    write(buildPath(root, "three.txt"), "three");
    mkdirRecurse(buildPath(root, "nested"));
    write(buildPath(root, "nested", "deep.txt"), "deep");
    repository.scan();

    auto source = new CatalogDirectorySource(openCatalogBackend(root));
    scope (exit)
        source.close();

    assert(source.root().id == "root");
    assert(source.root().name == baseName(root));
    assert(source.root().fileCount == 4);
    assert(source.root().aggregateSize == 15);

    auto rootFiles = source.listFiles("root");
    assert(rootFiles.length == 3);
    assert(source.listFiles("root", 0, 250, "one.txt").length == 1);
    assert(source.listFiles("root", 1, 1).length == 1);
    assert(source.listFiles("root", 3, 1).length == 0);

    auto directories = source.listDirectories("root");
    assert(directories.length == 1);
    assert(directories[0].name == "nested");
    assert(directories[0].fileCount == 1);
    assert(source.hasMatchingFileInDirectory(directories[0].id));
    assert(source.listFiles(directories[0].id).length == 1);

    auto first = source.listFilesPage("root", FileCursor(), 1);
    assert(first.files.length == 1 && first.hasMore);
    auto second = source.listFilesPage("root", first.nextCursor, 1);
    assert(second.files.length == 1 && second.hasMore);
    auto third = source.listFilesPage("root", second.nextCursor, 1);
    assert(third.files.length == 1 && !third.hasMore);

    FileNode threeFile;
    foreach (file; rootFiles)
        if (file.name == "three.txt")
            threeFile = file;
    assert(threeFile.cursorId == "three.txt");
    auto previous = source.listPreviousFilteredFilesPage("root",
        FileCursor(threeFile.relativePath, threeFile.cursorId, threeFile.size), 1);
    assert(previous.files.length == 1 && previous.files[0].name == "one.txt");
    auto next = source.listFilteredFilesPage("root",
        FileCursor(threeFile.relativePath, threeFile.cursorId, threeFile.size), 1);
    assert(next.files.length == 1 && next.files[0].name == "two.txt");

    FileFilter archiveFilter;
    archiveFilter.archive = true;
    assert(source.listFilteredFilesPage("root", FileCursor(), 10, archiveFilter)
        .files.length == 0);

    FileFilter caseSensitiveFilter;
    caseSensitiveFilter.text = "ONE.TXT";
    caseSensitiveFilter.caseSensitive = true;
    assert(source.listPreviousFilteredFilesPage("root",
        FileCursor("two.txt", "two.txt", 3), 10, caseSensitiveFilter)
        .files.length == 0);
}
