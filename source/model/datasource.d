/** Shared data-source adapter for JSON files and SQLite repositories. */
module model.datasource;

import std.file : exists, isDir;
import std.path : buildPath;

import dosierskanilo;
import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob,
    deserializeDataClassJsonFile;

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
}
