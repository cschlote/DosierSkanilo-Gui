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
    size_t offset;
    size_t total;
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

/** Load one bounded page from a JSON file or SQLite repository. */
SourcePage loadDocumentPage(string path, size_t offset, size_t limit)
{
    if (!isRepositorySource(path))
    {
        auto allBlobs = deserializeDataClassJsonFile(path);
        auto end = offset + limit;
        if (end > allBlobs.length)
            end = allBlobs.length;
        if (offset > allBlobs.length)
            offset = allBlobs.length;
        return SourcePage(allBlobs[offset .. end].dup, offset, allBlobs.length);
    }

    auto repository = Repository.open(path);
    scope (exit)
        repository.close();
    JsonExportOptions options;
    options.absolutePaths = true;
    return SourcePage(repository.loadCatalogPage(offset, limit, options),
        offset, repository.blobCount);
}

@("repository source detection")
unittest
{
    import std.file : mkdirRecurse, rmdirRecurse, tempDir;
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
}
