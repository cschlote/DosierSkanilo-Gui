/** Storage-neutral directory source over the catalog backend contract. */
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

private enum pageSize = 250;

/** Open the storage-neutral backend for one repository root. */
CatalogBackend openCatalogBackend(string repositoryPath)
{
    return new DefaultCatalogBackendFactory().open(
        OperationTarget.repositoryTarget(repositoryPath));
}

/** Open the storage-neutral backend for one JSON catalog file. */
CatalogBackend openJsonCatalogBackend(string catalogPath)
{
    return new DefaultCatalogBackendFactory().open(
        OperationTarget.jsonTarget(catalogPath));
}

/**
 * Directory source backed by a catalog backend.
 *
 * Directory and file nodes are addressed by their source-relative paths, so
 * restored state resolves against a freshly opened backend instance. The
 * backend target is owned by this source and closed with it.
 */
final class CatalogDirectorySource : DirectorySource
{
    private CatalogBackend backend;
    private DirectoryNode rootNode;

    this(CatalogBackend backend)
    {
        this.backend = backend;
        const info = backend.sourceInfo();
        const summary = backend.rootSummary();
        rootNode = DirectoryNode("root", "", info.displayName.length > 0
            ? info.displayName : baseName(backend.target().repositoryRoot), "",
            summary.childDirectoryCount, summary.fileReferenceCount,
            summary.aggregateSize);
    }

    /** The backend used for detail loads by callers that reuse this source. */
    @property ref CatalogBackend catalog() return
    {
        return backend;
    }

    override DirectoryNode root()
    {
        return rootNode;
    }

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

    override FilePage listFilesPage(string directoryId,
        FileCursor cursor = FileCursor(), size_t limit = 250, string filter = "")
    {
        FileFilter fileFilter;
        fileFilter.text = filter;
        return listFilteredFilesPage(directoryId, cursor, limit, fileFilter,
            FileSortOrder.pathAscending);
    }

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

    override void close()
    {
        if (backend !is null)
            backend.close();
        backend = null;
    }

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

    private static string directoryPath(string relativePath)
    {
        return relativePath.length > 0 ? relativePath : "root";
    }

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
