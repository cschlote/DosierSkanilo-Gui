/** Filtered summary export helpers for CSV and JSON files.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.dataexport;

import std.array : appender;
import std.file : write;
import std.format : format;
import std.json : JSONType, JSONValue;
import std.string : replace;

import dosierskanilo.catalogbackend : CatalogPageCursor;
import model.blobrow : BlobRow, extractRowsFromBlobs;
import model.datasource : SourceQuery, isRepositorySource, loadCatalogRowPage,
    loadDocumentSource;
import view.textreport : filterRowsByText;

/** Filter rows with the GUI's text, media-negation, and presence semantics.
 *
 * Params:
 *     rows = Source rows to filter.
 *     query = Active filter criteria.
 * Returns: Rows matching the text, media, and presence criteria in input order.
 */
BlobRow[] filterExportRows(const(BlobRow)[] rows, SourceQuery query)
{
    auto textFiltered = filterRowsByText(rows, query.text, query.caseSensitive);
    BlobRow[] result;
    auto hasMediaFilter = query.video || query.audio || query.image || query.textStream;
    auto hasPresenceFilter = query.fileType || query.archive || query.torrent;
    foreach (row; textFiltered)
    {
        auto matchesMedia = (query.video && row.hasVideo) || (query.audio && row.hasAudio)
            || (query.image && row.hasImage) || (query.textStream && row.hasText);
        if (hasMediaFilter && (query.mediaNegated ? matchesMedia : !matchesMedia))
            continue;
        auto matchesPresence = (query.fileType && row.hasFileType)
            || (query.archive && row.hasArchive) || (query.torrent && row.hasTorrent);
        if (hasPresenceFilter && !matchesPresence)
            continue;
        result ~= row;
    }
    return result;
}

/** Load all logical rows matching one tab's active filter state.
 *
 * Repository sources are paged through the catalog backend while JSON documents
 * are loaded whole; text filtering differs only in where it is applied.
 *
 * Params:
 *     sourcePath = JSON document path or repository directory.
 *     query = Active filter criteria.
 * Returns: All matching rows from the source.
 * Throws: Source loading, paging, or file errors are propagated.
 */
BlobRow[] loadFilteredExportRows(string sourcePath, SourceQuery query)
{
    if (!isRepositorySource(sourcePath))
        return filterExportRows(extractRowsFromBlobs(loadDocumentSource(sourcePath)),
            query);

    auto repositoryQuery = query;
    auto localFilter = query;
    localFilter.text = "";
    BlobRow[] result;
    CatalogPageCursor cursor;
    while (true)
    {
        auto page = loadCatalogRowPage(sourcePath, cursor, 250, repositoryQuery);
        result ~= filterExportRows(page.rows, localFilter);
        if (!page.hasMore)
            break;
        cursor = page.nextCursor;
    }
    return result;
}

/** Serialize the visible row projection as a stable CSV document.
 *
 * Params:
 *     rows = Rows to serialize.
 * Returns: A CSV document with a header row and one line per input row.
 */
string exportRowsCsv(const(BlobRow)[] rows)
{
    auto output = appender!string();
    output.put("fileName,fileSize,md5,sha1,xxh64,fileCount,fileType,video,audio,image,text,archive,torrent\n");
    foreach (row; rows)
    {
        output.put(format("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
            csvField(row.primaryFileName), row.fileSize, csvField(row.md5),
            csvField(row.sha1), csvField(row.xxh64), row.fileCount,
            csvField(row.fileType), csvBool(row.hasVideo), csvBool(row.hasAudio),
            csvBool(row.hasImage), csvBool(row.hasText), csvBool(row.hasArchive),
            csvBool(row.hasTorrent)));
    }
    return output.data;
}

/** Render a boolean as the lowercase CSV token `true` or `false`.
 *
 * Params:
 *     value = Boolean to render.
 * Returns: `"true"` when `value` is true, otherwise `"false"`.
 */
private string csvBool(bool value)
{
    return value ? "true" : "false";
}

/** Quote and escape a CSV field when it contains separators or quotes.
 *
 * Commas, double quotes, and line breaks trigger quoting; embedded double
 * quotes are doubled as required by RFC 4180-style CSV.
 *
 * Params:
 *     value = Raw field value.
 * Returns: The field unchanged when no quoting is needed, otherwise a quoted
 *     and escaped copy.
 */
private string csvField(string value)
{
    bool needsQuotes;
    foreach (ch; value)
        if (ch == ',' || ch == '"' || ch == '\n' || ch == '\r')
            needsQuotes = true;
    if (!needsQuotes)
        return value;
    return "\"" ~ value.replace("\"", "\"\"") ~ "\"";
}

/** Serialize the visible row projection as a versioned JSON subset.
 *
 * Params:
 *     rows = Rows to serialize.
 * Returns: A JSON document tagged `dosierskanilo-gui-subset-v1`.
 */
string exportRowsJson(const(BlobRow)[] rows)
{
    JSONValue[] jsonRows;
    foreach (row; rows)
    {
        JSONValue[string] item;
        item["fileName"] = JSONValue(row.primaryFileName);
        item["fileSize"] = JSONValue(row.fileSize);
        item["md5"] = JSONValue(row.md5);
        item["sha1"] = JSONValue(row.sha1);
        item["xxh64"] = JSONValue(row.xxh64);
        item["fileCount"] = JSONValue(row.fileCount);
        item["fileType"] = JSONValue(row.fileType);
        item["video"] = JSONValue(row.hasVideo);
        item["audio"] = JSONValue(row.hasAudio);
        item["image"] = JSONValue(row.hasImage);
        item["text"] = JSONValue(row.hasText);
        item["archive"] = JSONValue(row.hasArchive);
        item["torrent"] = JSONValue(row.hasTorrent);
        jsonRows ~= JSONValue(item);
    }
    JSONValue[string] document;
    document["format"] = JSONValue("dosierskanilo-gui-subset-v1");
    document["rows"] = JSONValue(jsonRows);
    return JSONValue(document).toString ~ "\n";
}

/** Write selected row summaries to a CSV file.
 *
 * Params:
 *     path = Destination file path.
 *     rows = Rows to serialize.
 * Throws: File errors from `std.file.write`.
 */
void writeRowsCsv(string path, const(BlobRow)[] rows)
{
    write(path, exportRowsCsv(rows));
}

/** Write selected row summaries to a JSON file.
 *
 * Params:
 *     path = Destination file path.
 *     rows = Rows to serialize.
 * Throws: File errors from `std.file.write`.
 */
void writeRowsJson(string path, const(BlobRow)[] rows)
{
    write(path, exportRowsJson(rows));
}

@("filtered exports preserve CSV fields and JSON summary values")
unittest
{
    import std.algorithm.searching : canFind;
    import std.json : parseJSON;

    BlobRow quoted;
    quoted.primaryFileName = "keep, \"this\".mp4";
    quoted.fileSize = 12;
    quoted.sha1 = "abc123";
    quoted.fileCount = 2;
    quoted.hasSummaryFlags = true;
    quoted.summaryHasVideo = true;
    quoted.summaryHasArchive = true;

    BlobRow excluded;
    excluded.primaryFileName = "skip.txt";
    excluded.fileSize = 3;

    SourceQuery query;
    query.text = "keep";
    query.video = true;
    query.archive = true;
    auto rows = filterExportRows([quoted, excluded], query);
    assert(rows.length == 1);
    assert(rows[0].primaryFileName == quoted.primaryFileName);

    auto csv = exportRowsCsv(rows);
    assert(csv.canFind("\"keep, \"\"this\"\".mp4\""));
    auto json = parseJSON(exportRowsJson(rows));
    assert(json.object["format"].str == "dosierskanilo-gui-subset-v1");
    assert(json.object["rows"].array.length == 1);
    auto exported = json.object["rows"].array[0].object;
    assert(exported["fileName"].str == quoted.primaryFileName);
    assert(exported["fileSize"].integer == 12);
    assert(exported["video"].type == JSONType.true_);
    assert(exported["archive"].type == JSONType.true_);
}

@("filtered row export respects case sensitivity for filename matching")
unittest
{
    BlobRow mixedCase;
    mixedCase.primaryFileName = "Folder/Alpha.txt";
    BlobRow[] rows = [mixedCase];

    SourceQuery query;
    query.text = "alpha";
    assert(filterExportRows(rows, query).length == 1);
    query.caseSensitive = true;
    assert(filterExportRows(rows, query).length == 0);
}

@("filtered exports include the same JSON and repository row subset")
unittest
{
    import dosierskanilo.repository.repository : Repository;
    import std.file : exists, mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.path : baseName, buildPath;
    import std.uuid : randomUUID;

    auto fixture = buildPath(tempDir(), "gui-export-subset-" ~ randomUUID().toString());
    auto root = buildPath(fixture, "repository");
    auto jsonPath = buildPath(fixture, "catalog.json");
    mkdirRecurse(root);
    scope (exit)
    {
        if (exists(fixture))
            rmdirRecurse(fixture);
    }
    write(buildPath(root, "keep-one.txt"), "one");
    write(buildPath(root, "skip.txt"), "skip");
    write(buildPath(root, "keep-two.txt"), "two-two");
    write(buildPath(root, "NorthStar-one.txt"), "upper path");
    write(buildPath(root, "northstar-two.txt"), "lower path");

    auto repository = Repository.initialize(root);
    repository.scan();
    repository.exportJson(jsonPath);
    repository.close();

    SourceQuery query;
    query.text = "keep";
    auto jsonRows = loadFilteredExportRows(jsonPath, query);
    auto repositoryRows = loadFilteredExportRows(root, query);
    assert(jsonRows.length == 2);
    assert(repositoryRows.length == 2);
    foreach (jsonRow; jsonRows)
    {
        bool found;
        foreach (repositoryRow; repositoryRows)
            if (baseName(repositoryRow.primaryFileName) == jsonRow.primaryFileName
                && repositoryRow.fileSize == jsonRow.fileSize)
                found = true;
        assert(found, "Missing exported repository row for " ~ jsonRow.primaryFileName);
    }

    query.text = "NorthStar";
    query.caseSensitive = true;
    auto jsonSensitiveRows = loadFilteredExportRows(jsonPath, query);
    auto repositorySensitiveRows = loadFilteredExportRows(root, query);
    assert(jsonSensitiveRows.length == 1);
    assert(repositorySensitiveRows.length == 1);
    assert(jsonSensitiveRows[0].primaryFileName == "NorthStar-one.txt");
    assert(baseName(repositorySensitiveRows[0].primaryFileName)
        == "NorthStar-one.txt");

    query.text = "northstar";
    query.caseSensitive = false;
    auto jsonInsensitiveRows = loadFilteredExportRows(jsonPath, query);
    auto repositoryInsensitiveRows = loadFilteredExportRows(root, query);
    assert(jsonInsensitiveRows.length == 2);
    assert(repositoryInsensitiveRows.length == 2);
}
