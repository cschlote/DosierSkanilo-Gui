/** Shared data-source adapter for JSON files and SQLite repositories. */
module model.datasource;

import std.file : exists, isDir;
import std.conv : to;
import std.path : baseName;
import std.string : empty;

import dosierskanilo;
import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob,
    deserializeDataClassJsonFile;
import model.treeprojection : DirectoryNode, DirectorySource, FileInput, FileNode,
    NestedFileNode, DirectoryTree, buildDirectoryTree;

/** One bounded source result page. */
struct SourcePage
{
    NamedBinaryBlob[] blobs;
    long[] blobIds;
    RepositoryBlobFlags[] flags;
    size_t offset;
    size_t total;
}

/** Filter state translated into repository query options. */
struct SourceQuery
{
    string text;
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
    private Repository repository;
    private DirectoryNode rootNode;

    this(string path)
    {
        repository = Repository.open(path);
        RepositoryDirectoryQuery directoryQuery;
        directoryQuery.limit = size_t.max;
        RepositoryFileQuery fileQuery;
        fileQuery.limit = size_t.max;
        auto directories = repository.listDirectories(directoryQuery);
        auto files = repository.listFiles(fileQuery);
        ulong aggregate;
        foreach (file; files)
            aggregate += file.size;
        rootNode = DirectoryNode("root", "", baseName(path), "", directories.length,
            files.length, aggregate);
    }

    override DirectoryNode root()
    {
        return rootNode;
    }

    override DirectoryNode[] listDirectories(string parentId)
    {
        RepositoryDirectoryQuery query;
        query.parentId = parentId == "root" ? 0 : to!long(parentId);
        query.limit = size_t.max;
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

    override FileNode[] listFiles(string directoryId, size_t offset = 0, size_t limit = 250,
        string filter = "")
    {
        RepositoryFileQuery query;
        query.directoryId = directoryId == "root" ? 0 : to!long(directoryId);
        query.offset = offset;
        query.limit = limit;
        query.text = filter;
        FileNode[] result;
        foreach (file; repository.listFiles(query))
        {
            result ~= FileNode(file.blobId.to!string, directoryId, file.name,
                file.relativePath, file.size);
        }
        return result;
    }

    override void close()
    {
        if (repository !is null)
        {
            repository.close();
            repository = null;
        }
    }
}

/** Open a repository-backed directory source for the GUI tree. */
DirectorySource openRepositoryDirectorySource(string path)
{
    return new RepositoryDirectorySource(path);
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

/** Load full details for one repository blob. */
NamedBinaryBlob loadDocumentDetails(string path, long blobId)
{
    auto repository = Repository.open(path);
    scope (exit)
        repository.close();
    JsonExportOptions options;
    options.absolutePaths = true;
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
    assert(directorySource.listFiles("root").length == 3);
    assert(directorySource.listFiles("root", 0, 250, "one.txt").length == 1);
    directorySource.close();
    SourceQuery filteredQuery;
    filteredQuery.text = "one.txt";
    auto filtered = loadDocumentPage(root, 0, 250, filteredQuery);
    assert(filtered.total == 1);
    assert(filtered.blobs.length == 1);
}
