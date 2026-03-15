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
import std.json : JSONType, JSONValue;

import model.blobrow;

/** Convert a JSON number node into `ulong`.
 *
 * Params:
 *   value = JSON value expected to be numeric
 * Returns:
 *   Numeric value converted to `ulong`, or `0` for non-numeric nodes
 */
ulong jsonAsULong(JSONValue value) {
    if (value.type == JSONType.integer) {
        return cast(ulong) value.integer;
    }
    if (value.type == JSONType.uinteger) {
        return value.uinteger;
    }
    if (value.type == JSONType.float_) {
        return cast(ulong) value.floating;
    }
    return 0;
}

/** Return two-space indentation prefix for pretty JSON rendering. */
string jsonIndent(size_t level) {
    string result;
    foreach (_; 0 .. level) {
        result ~= "  ";
    }
    return result;
}

/** Render JSON value into a stable, multi-line human-readable representation. */
string prettyJsonValue(JSONValue value, size_t indentLevel = 0) {
    if (value.type == JSONType.object) {
        auto keysAcc = appender!(string[])();
        foreach (key, _; value.object) {
            keysAcc.put(key);
        }
        auto keys = keysAcc.data;
        keys.sort();

        if (keys.length == 0) {
            return "{}";
        }

        auto lines = appender!(string[])();
        lines.put("{");
        foreach (idx, key; keys) {
            auto child = prettyJsonValue(value.object[key], indentLevel + 1);
            auto suffix = idx + 1 < keys.length ? "," : "";
            lines.put(format("%s\"%s\": %s%s", jsonIndent(indentLevel + 1), key, child, suffix));
        }
        lines.put(format("%s}", jsonIndent(indentLevel)));
        return lines.data.join("\n");
    }

    if (value.type == JSONType.array) {
        if (value.array.length == 0) {
            return "[]";
        }

        auto lines = appender!(string[])();
        lines.put("[");
        foreach (idx, childValue; value.array) {
            auto child = prettyJsonValue(childValue, indentLevel + 1);
            auto suffix = idx + 1 < value.array.length ? "," : "";
            lines.put(format("%s%s%s", jsonIndent(indentLevel + 1), child, suffix));
        }
        lines.put(format("%s]", jsonIndent(indentLevel)));
        return lines.data.join("\n");
    }

    return value.toString();
}

/** Pick the first filename from a `fileSpecs` array.
 *
 * Params:
 *   specs = JSON array containing object entries with optional `fileName`
 * Returns:
 *   The first available filename, or empty string when none is found
 */
string firstFileNameFromSpecs(JSONValue[] specs) {
    foreach (spec; specs) {
        if (spec.type != JSONType.object) {
            continue;
        }
        auto obj = spec.object;
        if ("fileName" in obj) {
            return (*("fileName" in obj)).str;
        }
    }
    return "";
}

/** Collect all filename values from a `fileSpecs` array.
 *
 * Params:
 *   specs = JSON array containing object entries with optional `fileName`
 * Returns:
 *   Array of extracted filename values
 */
string[] allFileNamesFromSpecs(JSONValue[] specs) {
    auto names = appender!(string[])();
    foreach (spec; specs) {
        if (spec.type != JSONType.object) {
            continue;
        }

        auto obj = spec.object;
        if ("fileName" in obj) {
            auto value = (*("fileName" in obj)).str;
            if (value.length > 0) {
                names.put(value);
            }
        }
    }
    return names.data;
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
BlobRow rowFromJsonObject(JSONValue objValue) {
    BlobRow row;
    if (objValue.type != JSONType.object) {
        return row;
    }

    row.rawJson = prettyJsonValue(objValue);

    auto obj = objValue.object;

    if ("fileSize" in obj) {
        row.fileSize = jsonAsULong(*("fileSize" in obj));
    }

    if ("checkSums" in obj && (*("checkSums" in obj)).type == JSONType.object) {
        auto checksums = (*("checkSums" in obj)).object;
        if ("md5sum_b64" in checksums) {
            row.md5 = (*("md5sum_b64" in checksums)).str;
        }
        if ("sha1sum_b64" in checksums) {
            row.sha1 = (*("sha1sum_b64" in checksums)).str;
        }
        if ("xxh64sum_b64" in checksums) {
            row.xxh64 = (*("xxh64sum_b64" in checksums)).str;
        }
    }

    if (row.md5.length == 0 && "md5sum_b64" in obj) {
        row.md5 = (*("md5sum_b64" in obj)).str;
    }
    if (row.sha1.length == 0 && "sha1sum_b64" in obj) {
        row.sha1 = (*("sha1sum_b64" in obj)).str;
    }
    if (row.xxh64.length == 0 && "xxh64sum_b64" in obj) {
        row.xxh64 = (*("xxh64sum_b64" in obj)).str;
    }

    if ("fileSpecs" in obj && (*("fileSpecs" in obj)).type == JSONType.array) {
        auto specs = (*("fileSpecs" in obj)).array;
        row.fileCount = specs.length;
        row.primaryFileName = firstFileNameFromSpecs(specs);
        row.fileNamesSummary = allFileNamesFromSpecs(specs).join(", ");
    } else if ("fileNames" in obj && (*("fileNames" in obj)).type == JSONType.array) {
        auto names = (*("fileNames" in obj)).array;
        row.fileCount = names.length;
        auto collectedNames = appender!(string[])();
        foreach (name; names) {
            auto value = name.str;
            if (value.length > 0) {
                collectedNames.put(value);
            }
        }
        if (names.length > 0) {
            row.primaryFileName = names[0].str;
        }
        row.fileNamesSummary = collectedNames.data.join(", ");
    } else if ("fileName" in obj) {
        row.primaryFileName = (*("fileName" in obj)).str;
        row.fileCount = row.primaryFileName.length == 0 ? 0 : 1;
        row.fileNamesSummary = row.primaryFileName;
    }

    if (row.fileNamesSummary.length == 0 && row.primaryFileName.length > 0) {
        row.fileNamesSummary = row.primaryFileName;
    }

    row.hasMedia = false;
    if ("mediaInfoSig" in obj && (*("mediaInfoSig" in obj)).type == JSONType.object) {
        row.hasMedia = true;
    }
    if (!row.hasMedia && "mediaInfo" in obj && (*("mediaInfo" in obj)).type == JSONType.array) {
        row.hasMedia = (*("mediaInfo" in obj)).array.length > 0;
    }

    if ("fileType" in obj) {
        row.fileType = (*("fileType" in obj)).str;
    }

    row.hasArchive = false;
    if ("archiveSpecs" in obj && (*("archiveSpecs" in obj)).type == JSONType.array) {
        row.hasArchive = (*("archiveSpecs" in obj)).array.length > 0;
    }

    row.hasTorrent = false;
    if ("torrentInfo" in obj && (*("torrentInfo" in obj)).type == JSONType.object) {
        row.hasTorrent = true;
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
BlobRow[] extractRowsFromRoot(JSONValue root) {
    JSONValue[] blobs;

    if (root.type == JSONType.array) {
        blobs = root.array;
    } else if (root.type == JSONType.object) {
        auto rootObj = root.object;
        if ("dataArray" in rootObj && (*("dataArray" in rootObj)).type == JSONType.array) {
            blobs = (*("dataArray" in rootObj)).array;
        }
    }

    auto rowsAcc = appender!(BlobRow[])();
    foreach (blob; blobs) {
        if (blob.type != JSONType.object) {
            continue;
        }
        rowsAcc.put(rowFromJsonObject(blob));
    }
    return rowsAcc.data;
}

unittest {
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
        assert(row.hasMedia);
        assert(row.hasArchive);
        assert(row.hasTorrent);
        assert(row.fileType == "video");
        assert(row.rawJson.canFind("\"archiveSpecs\""));
}

unittest {
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
        assert(row.hasMedia);
        assert(!row.hasArchive);
        assert(!row.hasTorrent);
}

unittest {
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

unittest {
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
