/** Shared data-source adapter for JSON files and SQLite repositories. */
module model.datasource;

import std.file : exists, isDir;
import std.path : buildPath;

import dosierskanilo;
import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob,
    deserializeDataClassJsonFile;

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

/** Return whether `path` is a DosierSkanilo repository root. */
bool isRepositorySource(string path)
{
    return isDir(path) && exists(buildPath(path, ".dosierskanilo"));
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
    auto page = repository.loadCatalogQueryPageWithIds(repositoryQuery, options);
    return SourcePage(page.blobs, page.blobIds, page.flags, page.total);
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
    auto repository = Repository.initialize(root);
    repository.close();
    assert(isRepositorySource(root));
    auto page = loadDocumentPage(root, 0, 10);
    assert(page.total == 0);
    assert(page.blobs.length == 0);

    repository = Repository.open(root);
    write(buildPath(root, "one.txt"), "one");
    write(buildPath(root, "two.txt"), "two");
    write(buildPath(root, "three.txt"), "three");
    repository.scan();
    assert(repository.blobCount == 3, "blobs=" ~ to!string(repository.blobCount));
    auto populated = loadDocumentPage(root, 0, 2);
    assert(populated.total == 3, "total=" ~ to!string(populated.total));
    assert(populated.blobs.length == 2);
    assert(populated.blobIds.length == 2);
    assert(populated.flags.length == 2);
    assert(!populated.flags[0].hasMedia);
    repository.close();
}
