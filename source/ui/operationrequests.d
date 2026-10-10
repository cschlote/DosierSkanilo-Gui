/** Pure source-aware construction of shared backend operation requests. */
module ui.operationrequests;

import dosierskanilo.operations : AnalysisOperationRequest,
    MetadataOperationRequest, OperationStorageMode, OperationTarget,
    ScanOperationRequest;
import dosierskanilo.repository.types : MetadataScanOptions,
    RepositoryAnalysisOptions, RepositoryScanOptions;

/** Build the request used by the GUI Scan action. */
ScanOperationRequest buildScanOperationRequest(ulong operationId,
    string documentPath, bool repositorySource, string filesystemRoot,
    RepositoryScanOptions scanOptions, MetadataScanOptions metadataOptions)
{
    ScanOperationRequest request;
    request.operationId = operationId;
    request.target = repositorySource
        ? OperationTarget.repositoryTarget(documentPath)
        : OperationTarget.jsonTarget(documentPath, filesystemRoot);
    request.scanOptions = scanOptions;
    request.metadataOptions = metadataOptions;
    return request;
}

/** Build the repository-only standalone metadata request. */
MetadataOperationRequest buildMetadataOperationRequest(ulong operationId,
    string repositoryRoot, MetadataScanOptions metadataOptions)
{
    MetadataOperationRequest request;
    request.operationId = operationId;
    request.target = OperationTarget.repositoryTarget(repositoryRoot);
    request.options = metadataOptions;
    return request;
}

/** Build an analysis request without crossing or inferring storage modes. */
AnalysisOperationRequest buildAnalysisOperationRequest(ulong operationId,
    string documentPath, bool repositorySource,
    RepositoryAnalysisOptions analysisOptions, MetadataScanOptions metadataOptions)
{
    AnalysisOperationRequest request;
    request.operationId = operationId;
    request.target = repositorySource
        ? OperationTarget.repositoryTarget(documentPath)
        : OperationTarget.jsonTarget(documentPath);
    request.options = analysisOptions;
    request.metadataOptions = metadataOptions;
    return request;
}

@("GUI scan request builder preserves explicit JSON and repository targets")
unittest
{
    MetadataScanOptions metadata;
    metadata.calculateChecksums = true;
    RepositoryScanOptions scanOptions;
    scanOptions.pickHidden = true;
    auto sqlite = buildScanOperationRequest(1, "/repository", true,
        "ignored", scanOptions, metadata);
    assert(sqlite.target.repositoryRoot == "/repository");
    assert(sqlite.target.catalogPath.length == 0);
    assert(sqlite.target.filesystemRoot.length == 0);
    assert(sqlite.scanOptions.pickHidden);
    assert(sqlite.metadataOptions.calculateChecksums);

    auto json = buildScanOperationRequest(2, "/catalog.json", false,
        "/media", scanOptions, metadata);
    assert(json.target.catalogPath == "/catalog.json");
    assert(json.target.filesystemRoot == "/media");
    assert(json.target.repositoryRoot.length == 0);
}

@("GUI metadata and analysis request builders use supported source modes")
unittest
{
    MetadataScanOptions metadata;
    metadata.scanArchives = true;
    auto standalone = buildMetadataOperationRequest(3, "/repository", metadata);
    assert(standalone.target.mode == OperationStorageMode.repository);
    assert(standalone.options.scanArchives);

    RepositoryAnalysisOptions analysis;
    analysis.dropMissing = true;
    auto sqlite = buildAnalysisOperationRequest(4, "/repository", true,
        analysis, MetadataScanOptions.init);
    assert(sqlite.target.repositoryRoot == "/repository");
    assert(sqlite.options.dropMissing);

    auto json = buildAnalysisOperationRequest(5, "/catalog.json", false,
        RepositoryAnalysisOptions.init, metadata);
    assert(json.target.catalogPath == "/catalog.json");
    assert(json.target.filesystemRoot.length == 0);
    assert(json.metadataOptions.scanArchives);
}

@("GUI-built requests use the same JSON and SQLite operation results")
unittest
{
    import std.algorithm.searching : startsWith;
    import std.file : DirEntry, SpanMode, dirEntries, exists, getcwd,
        mkdirRecurse, remove, rmdirRecurse, tempDir, write;
    import std.path : baseName, buildPath;
    import std.uuid : randomUUID;
    import dosierskanilo.model.namedbinaryblob : deserializeDataClassJsonWrapperFile;
    import dosierskanilo.operationrunner : runOperation;
    import dosierskanilo.operations : OperationControl, OperationState;
    import dosierskanilo.repository : Repository;

    auto token = randomUUID().toString();
    auto root = buildPath(tempDir(), "gui-operation-parity-" ~ token);
    mkdirRecurse(root);
    auto catalogPath = buildPath(tempDir(), "gui-operation-parity-"
        ~ token ~ ".json");
    auto backupPrefix = baseName(catalogPath)[0 .. $ - ".json".length] ~ "-";
    scope (exit)
    {
        if (exists(catalogPath))
            remove(catalogPath);
        foreach (DirEntry entry; dirEntries(getcwd(), SpanMode.shallow))
            if (entry.name.baseName.startsWith(backupPrefix) && exists(entry.name))
                remove(entry.name);
        if (exists(root))
            rmdirRecurse(root);
    }
    write(buildPath(root, "one.txt"), "identical GUI operation payload");
    write(buildPath(root, "two.txt"), "identical GUI operation payload");
    auto repository = Repository.initialize(root);
    repository.close();

    RepositoryScanOptions scanOptions;
    MetadataScanOptions metadataOptions;
    metadataOptions.calculateChecksums = true;
    auto sqliteScanRequest = buildScanOperationRequest(10, root, true, root,
        scanOptions, metadataOptions);
    auto jsonScanRequest = buildScanOperationRequest(11, catalogPath, false, root,
        scanOptions, metadataOptions);
    auto sqliteScan = runOperation(sqliteScanRequest, new OperationControl());
    auto jsonScan = runOperation(jsonScanRequest, new OperationControl());
    assert(sqliteScan.state == OperationState.completed, sqliteScan.error);
    assert(jsonScan.state == OperationState.completed, jsonScan.error);
    assert(sqliteScan.scanSummary.filesFound == jsonScan.scanSummary.filesFound);
    assert(sqliteScan.scanSummary.filesAdded == jsonScan.scanSummary.filesAdded);
    assert(sqliteScan.metadataSummary.checksumsUpdated
        == jsonScan.metadataSummary.checksumsUpdated);

    MetadataScanOptions typeOptions;
    typeOptions.detectFileTypes = true;
    auto metadataRequest = buildMetadataOperationRequest(12, root, typeOptions);
    auto sqliteMetadata = runOperation(metadataRequest, new OperationControl());
    assert(sqliteMetadata.state == OperationState.completed, sqliteMetadata.error);

    RepositoryAnalysisOptions analysisOptions;
    analysisOptions.mergeDuplicates = true;
    auto sqliteAnalyzeRequest = buildAnalysisOperationRequest(13, root, true,
        analysisOptions, MetadataScanOptions.init);
    auto jsonAnalyzeRequest = buildAnalysisOperationRequest(14, catalogPath, false,
        analysisOptions, typeOptions);
    auto sqliteAnalyze = runOperation(sqliteAnalyzeRequest, new OperationControl());
    auto jsonAnalyze = runOperation(jsonAnalyzeRequest, new OperationControl());
    assert(sqliteAnalyze.state == OperationState.completed, sqliteAnalyze.error);
    assert(jsonAnalyze.state == OperationState.completed, jsonAnalyze.error);
    assert(sqliteAnalyze.analysisSummary.duplicateGroups
        == jsonAnalyze.analysisSummary.duplicateGroups);
    assert(sqliteAnalyze.analysisSummary.mergedBlobs
        == jsonAnalyze.analysisSummary.mergedBlobs);
    assert(sqliteMetadata.metadataSummary.fileTypesUpdated
        == jsonAnalyze.metadataSummary.fileTypesUpdated);

    repository = Repository.open(root);
    scope (exit)
        repository.close();
    auto jsonCatalog = deserializeDataClassJsonWrapperFile(catalogPath);
    assert(repository.loadCatalog().length == jsonCatalog.dataArray.length);
    assert(repository.loadCatalog().length == 1);
    assert(repository.loadCatalog()[0].fileSpecs.length
        == jsonCatalog.dataArray[0].fileSpecs.length);
    assert(jsonAnalyze.changesCommitted && sqliteAnalyze.changesCommitted);
}
