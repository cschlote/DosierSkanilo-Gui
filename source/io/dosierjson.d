/** JSON extraction helpers for DosierSkanilo scan files.
 *
 * This module normalizes legacy and wrapper JSON variants into `BlobRow`
 * projections used by the GUI. It intentionally performs tolerant extraction so
 * partially populated archives can still be displayed.
 *
 * Authors: DosierSkanilo contributors
 * License: CC-BY-NC-SA 4.0
 */
module io.dosierjson;

import std.array : appender;
import std.algorithm : sort;
import std.algorithm.searching : canFind, startsWith, countUntil;
import std.format : format;
import std.string : join;
import std.uni : toLower;
import std.json : JSONType, JSONValue;

import model.blobrow;

/** Convert a JSON number node into `ulong`.
 *
 * Params:
 *   value = JSON value expected to be numeric
 * Returns:
 *   Numeric value converted to `ulong`, or `0` for non-numeric nodes
 */
ulong jsonAsULong(JSONValue value)
{
    if (value.type == JSONType.integer)
    {
        return cast(ulong) value.integer;
    }
    if (value.type == JSONType.uinteger)
    {
        return value.uinteger;
    }
    if (value.type == JSONType.float_)
    {
        return cast(ulong) value.floating;
    }
    return 0;
}

@("jsonAsULong")
unittest
{
    import std.json : parseJSON;

    assert(jsonAsULong(parseJSON("42")) == 42);
    assert(jsonAsULong(parseJSON("12345678901234567890")) == 12345678901234567890UL);
    assert(jsonAsULong(parseJSON("3.14")) == 3);
    assert(jsonAsULong(parseJSON("\"not a number\"")) == 0);
    assert(jsonAsULong(parseJSON("true")) == 0);
    assert(jsonAsULong(parseJSON("null")) == 0);
}

/** Return two-space indentation prefix for pretty JSON rendering. */
string jsonIndent(size_t level)
{
    string result;
    foreach (_; 0 .. level)
    {
        result ~= "  ";
    }
    return result;
}

/** Render JSON value into a stable, multi-line human-readable representation. */
string prettyJsonValue(JSONValue value, size_t indentLevel = 0)
{
    if (value.type == JSONType.object)
    {
        auto keysAcc = appender!(string[])();
        foreach (key, _; value.object)
        {
            keysAcc.put(key);
        }
        auto keys = keysAcc.data;
        keys.sort();

        if (keys.length == 0)
        {
            return "{}";
        }

        auto lines = appender!(string[])();
        lines.put("{");
        foreach (idx, key; keys)
        {
            auto child = prettyJsonValue(value.object[key], indentLevel + 1);
            auto suffix = idx + 1 < keys.length ? "," : "";
            lines.put(format("%s\"%s\": %s%s", jsonIndent(indentLevel + 1), key, child, suffix));
        }
        lines.put(format("%s}", jsonIndent(indentLevel)));
        return lines.data.join("\n");
    }

    if (value.type == JSONType.array)
    {
        if (value.array.length == 0)
        {
            return "[]";
        }

        auto lines = appender!(string[])();
        lines.put("[");
        foreach (idx, childValue; value.array)
        {
            auto child = prettyJsonValue(childValue, indentLevel + 1);
            auto suffix = idx + 1 < value.array.length ? "," : "";
            lines.put(format("%s%s%s", jsonIndent(indentLevel + 1), child, suffix));
        }
        lines.put(format("%s]", jsonIndent(indentLevel)));
        return lines.data.join("\n");
    }

    return value.toString();
}

@("prettyJsonValue")
unittest
{
    import std.json : parseJSON;

    auto value = parseJSON(q{{"b":2,"a":[1,{"z":0,"y":1}]}});
    auto pretty = prettyJsonValue(value);

    auto value2 = parseJSON(q{{}}); // Empty  objects
    auto pretty2 = prettyJsonValue(value2);
    auto value3 = parseJSON(q{[]}); // Empty arrays
    auto pretty3 = prettyJsonValue(value3);
}

/** Pick the first filename from a `fileSpecs` array.
 *
 * Params:
 *   specs = JSON array containing object entries with optional `fileName`
 * Returns:
 *   The first available filename, or empty string when none is found
 */
string firstFileNameFromSpecs(JSONValue[] specs)
{
    foreach (spec; specs)
    {
        if (spec.type != JSONType.object)
        {
            continue;
        }
        auto obj = spec.object;
        if ("fileName" in obj)
        {
            return (*("fileName" in obj)).str;
        }
    }
    return "";
}

@("firstFileNameFromSpecs")
unittest
{
    import std.json : parseJSON;

    auto specs = parseJSON(q{[
        { "fileName": "first.txt" },
        { "fileName": "second.txt" }
    ]}).array;
    assert(firstFileNameFromSpecs(specs) == "first.txt");
    auto specs2 = parseJSON(q{[
        { "name": "nope" },
        { "fileName": "only.txt" }
    ]}).array;
    assert(firstFileNameFromSpecs(specs2) == "only.txt");
    auto specs3 = parseJSON(q{[
        { "name": "nope" },
        { "name": "still nope" }
    ]}).array;
    assert(firstFileNameFromSpecs(specs3) == "");
    auto specs4 = parseJSON(q{["booh"]}).array;
    assert(firstFileNameFromSpecs(specs4) == "");
}

/** Collect all filename values from a `fileSpecs` array.
 *
 * Params:
 *   specs = JSON array containing object entries with optional `fileName`
 * Returns:
 *   Array of extracted filename values
 */
string[] allFileNamesFromSpecs(JSONValue[] specs)
{
    auto names = appender!(string[])();
    foreach (spec; specs)
    {
        if (spec.type != JSONType.object)
        {
            continue;
        }

        auto obj = spec.object;
        if ("fileName" in obj)
        {
            auto value = (*("fileName" in obj)).str;
            if (value.length > 0)
            {
                names.put(value);
            }
        }
    }
    return names.data;
}

@("allFileNamesFromSpecs")
unittest
{
    import std.json : parseJSON;

    auto specs = parseJSON(q{[
        { "fileName": "first.txt" },
        { "fileName": "second.txt" },
        { "name": "nope" },
        { "fileName": "" }
    ]}).array;
    auto names = allFileNamesFromSpecs(specs);
    assert(names.length == 2);
    assert(names[0] == "first.txt");
    assert(names[1] == "second.txt");
    auto specs2 = parseJSON(q{[
        { "name": "nope" },
        { "name": "still nope" }
    ]}).array;
    auto names2 = allFileNamesFromSpecs(specs2);
    assert(names2.length == 0);
    auto specs3 = parseJSON(q{["booh"]}).array;
    auto names3 = allFileNamesFromSpecs(specs3);
    assert(names3.length == 0);
}

/** Convert a scalar-ish JSON node into display text. */
string jsonScalarText(JSONValue value)
{
    final switch (value.type)
    {
    case JSONType.string:
        return value.str;
    case JSONType.integer:
        return format("%s", value.integer);
    case JSONType.uinteger:
        return format("%s", value.uinteger);
    case JSONType.float_:
        return format("%s", value.floating);
    case JSONType.true_:
        return "true";
    case JSONType.false_:
        return "false";
    case JSONType.null_:
        return "";
    case JSONType.object:
    case JSONType.array:
        return prettyJsonValue(value);
    }
}

@("jsonScalarText")
unittest
{
    import std.json : parseJSON;
    import std.exception : assertThrown;

    assertThrown!Exception(jsonScalarText(parseJSON("hello"))); // Check for execpetion happening on non-scalar types
    assert(jsonScalarText(parseJSON("123")) == "123");
    assert(jsonScalarText(parseJSON("3.14")) == "3.14");
    assert(jsonScalarText(parseJSON("true")) == "true");
    assert(jsonScalarText(parseJSON("false")) == "false");
    assert(jsonScalarText(parseJSON("null")) == "");
    auto obj = parseJSON(q{{"key": "value"}});
    assert(jsonScalarText(obj) == prettyJsonValue(obj));
    auto arr = parseJSON(q{[1, 2, 3]});
    assert(jsonScalarText(arr) == prettyJsonValue(arr));
    // Test JSONType.uinteger
    auto uIntValue = parseJSON("12345678901234567890");
    assert(jsonScalarText(uIntValue) == "12345678901234567890");

}

/** Return the first available field value from an object. */
string firstAvailableField(JSONValue[string] obj, string[] keys)
{
    foreach (key; keys)
    {
        if (auto value = key in obj)
        {
            auto text = jsonScalarText(*value);
            if (text.length > 0)
            {
                return text;
            }
        }
    }
    return "";
}

/** Extract a best-effort access timestamp from one file spec object. */
string lastAccessFromSpec(JSONValue spec)
{
    if (spec.type != JSONType.object)
    {
        return "";
    }

    auto obj = spec.object;
    auto directValue = firstAvailableField(obj, [
        "lastAccess",
        "lastAccessDate",
        "lastAccessTime",
        "lastAccessUtc",
        "accessTime",
        "accessDate",
        "accessedAt",
        "atime"
    ]);
    if (directValue.length > 0)
    {
        return directValue;
    }

    if ("stat" in obj && (*("stat" in obj)).type == JSONType.object)
    {
        auto statObj = (*("stat" in obj)).object;
        return firstAvailableField(statObj, [
            "lastAccess",
            "lastAccessDate",
            "lastAccessTime",
            "lastAccessUtc",
            "accessTime",
            "accessDate",
            "accessedAt",
            "atime"
        ]);
    }

    return "";
}

/** Build a multiline detail list from file specs, including access timestamps when present. */
string fileSpecDetails(JSONValue[] specs)
{
    auto lines = appender!(string[])();
    foreach (spec; specs)
    {
        if (spec.type != JSONType.object)
        {
            continue;
        }

        auto obj = spec.object;
        auto fileName = firstAvailableField(obj, ["fileName", "path", "name"]);
        auto lastAccess = lastAccessFromSpec(spec);
        if (fileName.length == 0 && lastAccess.length == 0)
        {
            continue;
        }

        if (fileName.length == 0)
        {
            fileName = "-";
        }
        lines.put(format("%s | last access: %s", fileName, lastAccess.length > 0 ? lastAccess : "-"));
    }
    return lines.data.join("\n");
}

@("fileSpecDetails")
unittest
{
    import std.json : parseJSON;

    auto jsonString1 = q{
    [
        { "fileName": "alpha.mkv", "lastAccessDate": "2026-03-15T09:30:00Z" },
        { "fileName": "beta.srt", "stat": { "atime": 123456789 } },
        { "fileName": "gamma.txt" },
        { "name": "delta.dat", "lastAccess": "yesterday" },
        { "name": "epsilon.log", "stat": { "accessedAt": "2026-01-01" } },
        { "name": "zeta.bin", "stat": { "accessDate": "2026-02-01" } },
        { "name": "eta.iso", "stat": { "accessTime": "2026-02-15T12:00:00Z" } },
        { "name": "theta.zip", "stat": { "lastAccessTime": "2026-02-20T18:45:00Z" } },
        { "name": "iota.rar", "stat": { "lastAccessUtc": "2026-03-01T08:00:00Z" } },
        { "name": "kappa.7z", "stat": { "lastAccessDate": "2026-03-10" } },
        { "name": "lambda.tar", "stat": { "lastAccess": "2026-03-12T14:30:00Z" } }
    ]
    };
    auto specs = parseJSON(jsonString1).array;
    auto details = fileSpecDetails(specs);
    assert(details.canFind("alpha.mkv | last access: 2026-03-15T09:30:00Z"));
    assert(details.canFind("beta.srt | last access: 123456789"));
    assert(details.canFind("gamma.txt | last access: -"));
    assert(details.canFind("delta.dat | last access: yesterday"));
    assert(details.canFind("epsilon.log | last access: 2026-01-01"));
    assert(details.canFind("zeta.bin | last access: 2026-02-01"));
    assert(details.canFind("eta.iso | last access: 2026-02-15T12:00:00Z"));
    assert(details.canFind("theta.zip | last access: 2026-02-20T18:45:00Z"));
    assert(details.canFind("iota.rar | last access: 2026-03-01T08:00:00Z"));
    assert(details.canFind("kappa.7z | last access: 2026-03-10"));
    assert(details.canFind("lambda.tar | last access: 2026-03-12T14:30:00Z"));
}

/** Build a multiline detail list from plain filename arrays. */
string fileNameArrayDetails(JSONValue[] names)
{
    auto lines = appender!(string[])();
    foreach (name; names)
    {
        auto value = name.str;
        if (value.length > 0)
        {
            lines.put(format("%s | last access: -", value));
        }
    }
    return lines.data.join("\n");
}

/** Map a single blob JSON object into a GUI row projection.
 *
 * The mapper supports modern and legacy fields:
 * - digest via `checkSums.md5sum_b64|sha1sum_b64|xxh64sum_b64` and top-level fallback
 * - file refs via `fileSpecs`, `fileNames`, or `fileName`
 * - media flags via `mediaInfoSig` or legacy `mediaInfo`
 * - feature flags via `archiveSpecs` and `torrentInfo`
 *
 * Params:
 *   objValue = JSON object node representing one blob entry
 * Returns:
 *   Normalized `BlobRow` instance
 */
BlobRow rowFromJsonObject(JSONValue objValue)
{
    BlobRow row;
    if (objValue.type != JSONType.object)
    {
        return row;
    }

    row.rawJson = prettyJsonValue(objValue);

    auto obj = objValue.object;

    if ("fileSize" in obj)
    {
        row.fileSize = jsonAsULong(*("fileSize" in obj));
    }

    if ("checkSums" in obj && (*("checkSums" in obj)).type == JSONType.object)
    {
        auto checksums = (*("checkSums" in obj)).object;
        if ("md5sum_b64" in checksums)
        {
            row.md5 = (*("md5sum_b64" in checksums)).str;
        }
        if ("sha1sum_b64" in checksums)
        {
            row.sha1 = (*("sha1sum_b64" in checksums)).str;
        }
        if ("xxh64sum_b64" in checksums)
        {
            row.xxh64 = (*("xxh64sum_b64" in checksums)).str;
        }
    }

    if (row.md5.length == 0 && "md5sum_b64" in obj)
    {
        row.md5 = (*("md5sum_b64" in obj)).str;
    }
    if (row.sha1.length == 0 && "sha1sum_b64" in obj)
    {
        row.sha1 = (*("sha1sum_b64" in obj)).str;
    }
    if (row.xxh64.length == 0 && "xxh64sum_b64" in obj)
    {
        row.xxh64 = (*("xxh64sum_b64" in obj)).str;
    }

    if ("fileSpecs" in obj && (*("fileSpecs" in obj)).type == JSONType.array)
    {
        auto specs = (*("fileSpecs" in obj)).array;
        row.fileCount = specs.length;
        row.primaryFileName = firstFileNameFromSpecs(specs);
        row.fileNamesSummary = allFileNamesFromSpecs(specs).join(", ");
        row.fileNamesDetails = fileSpecDetails(specs);
    }
    else if ("fileNames" in obj && (*("fileNames" in obj)).type == JSONType.array)
    {
        auto names = (*("fileNames" in obj)).array;
        row.fileCount = names.length;
        auto collectedNames = appender!(string[])();
        foreach (name; names)
        {
            auto value = name.str;
            if (value.length > 0)
            {
                collectedNames.put(value);
            }
        }
        if (names.length > 0)
        {
            row.primaryFileName = names[0].str;
        }
        row.fileNamesSummary = collectedNames.data.join(", ");
        row.fileNamesDetails = fileNameArrayDetails(names);
    }
    else if ("fileName" in obj)
    {
        row.primaryFileName = (*("fileName" in obj)).str;
        row.fileCount = row.primaryFileName.length == 0 ? 0 : 1;
        row.fileNamesSummary = row.primaryFileName;
        row.fileNamesDetails = row.primaryFileName.length > 0
            ? format("%s | last access: -", row.primaryFileName) : "";
    }

    if (row.fileNamesSummary.length == 0 && row.primaryFileName.length > 0)
    {
        row.fileNamesSummary = row.primaryFileName;
    }
    if (row.fileNamesDetails.length == 0 && row.fileNamesSummary.length > 0)
    {
        row.fileNamesDetails = format("%s | last access: -", row.fileNamesSummary);
    }

    row.hasMedia = false;
    row.hasVideo = false;
    row.hasAudio = false;
    row.hasImage = false;
    row.hasText = false;
    if ("mediaInfoSig" in obj && (*("mediaInfoSig" in obj)).type == JSONType.object)
    {
        auto sig = (*("mediaInfoSig" in obj)).object;
        foreach (key, value; sig)
        {
            bool isPresent = value.type != JSONType.false_ && value.type != JSONType.null_;
            if (!isPresent)
            {
                continue;
            }

            row.hasMedia = true;
            auto keyLower = toLower(key);
            if (keyLower == "video" || keyLower.canFind("video"))
            {
                row.hasVideo = true;
                continue;
            }
            if (keyLower == "audio" || keyLower.canFind("audio"))
            {
                row.hasAudio = true;
                continue;
            }
            if (keyLower == "image" || keyLower.canFind("image") || keyLower.canFind("photo") || keyLower.canFind(
                    "picture"))
            {
                row.hasImage = true;
                continue;
            }
            if (keyLower == "text" || keyLower.canFind("text") || keyLower.canFind("subtitle") || keyLower.canFind(
                    "caption"))
            {
                row.hasText = true;
                continue;
            }
        }
    }
    if (!row.hasMedia && "mediaInfo" in obj && (*("mediaInfo" in obj)).type == JSONType.array)
    {
        row.hasMedia = (*("mediaInfo" in obj)).array.length > 0;
    }
    row.hasMedia = row.hasMedia || row.hasVideo || row.hasAudio || row.hasImage || row.hasText;
    if ("mediaInfoSig" in obj)
    {
        row.mediaInfoDetails = prettyJsonValue(*("mediaInfoSig" in obj));
    }
    else if ("mediaInfo" in obj)
    {
        row.mediaInfoDetails = prettyJsonValue(*("mediaInfo" in obj));
    }

    if ("fileType" in obj)
    {
        row.fileType = (*("fileType" in obj)).str;
    }

    row.hasArchive = false;
    if ("archiveSpecs" in obj && (*("archiveSpecs" in obj)).type == JSONType.array)
    {
        row.hasArchive = (*("archiveSpecs" in obj)).array.length > 0;
        if (row.hasArchive)
        {
            row.archiveDetails = prettyJsonValue(*("archiveSpecs" in obj));
        }
    }

    row.hasTorrent = false;
    if ("torrentInfo" in obj && (*("torrentInfo" in obj)).type == JSONType.object)
    {
        row.hasTorrent = true;
        row.torrentDetails = prettyJsonValue(*("torrentInfo" in obj));
    }

    return row;
}

/** Extract all blob rows from the JSON root object.
 *
 * Supported root shapes:
 * - legacy plain array
 * - wrapper object containing `dataArray`
 *
 * Params:
 *   root = parsed JSON root node
 * Returns:
 *   Array of normalized `BlobRow` entries
 */
BlobRow[] extractRowsFromRoot(JSONValue root)
{
    JSONValue[] blobs;

    if (root.type == JSONType.array)
    {
        blobs = root.array;
    }
    else if (root.type == JSONType.object)
    {
        auto rootObj = root.object;
        if ("dataArray" in rootObj && (*("dataArray" in rootObj)).type == JSONType.array)
        {
            blobs = (*("dataArray" in rootObj)).array;
        }
    }

    auto rowsAcc = appender!(BlobRow[])();
    foreach (blob; blobs)
    {
        if (blob.type != JSONType.object)
        {
            continue;
        }
        rowsAcc.put(rowFromJsonObject(blob));
    }
    return rowsAcc.data;
}

unittest
{
    import std.json : parseJSON;

    auto parsed = parseJSON(q{
                {
                    "fileSize": 42,
                    "checkSums": {
                        "md5sum_b64": "md5-modern",
                        "sha1sum_b64": "sha-modern",
                        "xxh64sum_b64": "xxh-modern"
                    },
                    "fileSpecs": [
                        { "fileName": "alpha.mkv" },
                        { "fileName": "beta.srt" }
                    ],
                    "mediaInfoSig": { "video": true },
                    "archiveSpecs": [ { "kind": "zip" } ],
                    "torrentInfo": { "name": "release" },
                    "fileType": "video"
                }
        });

    auto row = rowFromJsonObject(parsed);
    assert(row.fileSize == 42);
    assert(row.md5 == "md5-modern");
    assert(row.sha1 == "sha-modern");
    assert(row.xxh64 == "xxh-modern");
    assert(row.primaryFileName == "alpha.mkv");
    assert(row.fileCount == 2);
    assert(row.fileNamesSummary == "alpha.mkv, beta.srt");
    assert(row.fileNamesDetails == "alpha.mkv | last access: -\nbeta.srt | last access: -");
    assert(row.hasMedia);
    assert(row.hasVideo);
    assert(!row.hasAudio);
    assert(!row.hasImage);
    assert(!row.hasText);
    assert(row.hasArchive);
    assert(row.hasTorrent);
    assert(row.mediaInfoDetails.canFind("video"));
    assert(row.archiveDetails.canFind("zip"));
    assert(row.torrentDetails.canFind("release"));
    assert(row.fileType == "video");
    assert(row.rawJson.canFind("\"archiveSpecs\""));
}

unittest
{
    import std.json : parseJSON;

    auto parsed = parseJSON(q{
                {
                    "md5sum_b64": "md5-legacy",
                    "sha1sum_b64": "sha-legacy",
                    "xxh64sum_b64": "xxh-legacy",
                    "fileNames": ["one.bin", "two.bin"],
                    "mediaInfo": [ { "stream": 1 } ]
                }
        });

    auto row = rowFromJsonObject(parsed);
    assert(row.md5 == "md5-legacy");
    assert(row.sha1 == "sha-legacy");
    assert(row.xxh64 == "xxh-legacy");
    assert(row.primaryFileName == "one.bin");
    assert(row.fileCount == 2);
    assert(row.fileNamesSummary == "one.bin, two.bin");
    assert(row.fileNamesDetails == "one.bin | last access: -\ntwo.bin | last access: -");
    assert(row.hasMedia);
    assert(!row.hasVideo);
    assert(!row.hasAudio);
    assert(!row.hasImage);
    assert(!row.hasText);
    assert(!row.hasArchive);
    assert(!row.hasTorrent);
}

unittest
{
    import std.json : parseJSON;

    auto parsed = parseJSON(q{
                {
                    "fileSpecs": [
                        { "fileName": "alpha.mkv", "lastAccessDate": "2026-03-15T09:30:00Z" },
                        { "fileName": "beta.srt", "stat": { "atime": 123456789 } }
                    ]
                }
        });

    auto row = rowFromJsonObject(parsed);
    assert(row.fileNamesDetails == "alpha.mkv | last access: 2026-03-15T09:30:00Z\nbeta.srt | last access: 123456789");
}

unittest
{
    import std.json : parseJSON;

    auto root = parseJSON(q{
                {
                    "dataArray": [
                        { "fileName": "first.dat", "sha1sum_b64": "sha-a" },
                        123,
                        { "fileSpecs": [ { "fileName": "second.dat" } ], "checkSums": { "sha1sum_b64": "sha-b" } }
                    ]
                }
        });

    auto rows = extractRowsFromRoot(root);
    assert(rows.length == 2);
    assert(rows[0].primaryFileName == "first.dat");
    assert(rows[0].sha1 == "sha-a");
    assert(rows[1].primaryFileName == "second.dat");
    assert(rows[1].sha1 == "sha-b");
}

unittest
{
    import std.json : parseJSON;

    auto value = parseJSON(q{{"b":2,"a":[1,{"z":0,"y":1}]}});
    auto pretty = prettyJsonValue(value);

    assert(pretty.startsWith("{"));
    assert(pretty.canFind("\n  \"a\": [\n"));
    assert(pretty.canFind("\n  \"b\": 2\n"));
    assert(pretty.canFind("\"y\": 1"));
    assert(pretty.canFind("\"z\": 0"));
    assert(pretty.countUntil("\"a\"") < pretty.countUntil("\"b\""));
}
