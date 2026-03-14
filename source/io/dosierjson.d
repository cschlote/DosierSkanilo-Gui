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

/** Map a single blob JSON object into a GUI row projection.
 *
 * The mapper supports modern and legacy fields:
 * - digest via `checkSums.sha1sum_b64` and top-level fallback
 * - file refs via `fileSpecs`, `fileNames`, or `fileName`
 * - media flags via `mediaInfoSig` or legacy `mediaInfo`
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

    auto obj = objValue.object;

    if ("fileSize" in obj) {
        row.fileSize = jsonAsULong(*("fileSize" in obj));
    }

    if ("checkSums" in obj && (*("checkSums" in obj)).type == JSONType.object) {
        auto checksums = (*("checkSums" in obj)).object;
        if ("sha1sum_b64" in checksums) {
            row.sha1 = (*("sha1sum_b64" in checksums)).str;
        }
    }
    if (row.sha1.length == 0 && "sha1sum_b64" in obj) {
        row.sha1 = (*("sha1sum_b64" in obj)).str;
    }

    if ("fileSpecs" in obj && (*("fileSpecs" in obj)).type == JSONType.array) {
        auto specs = (*("fileSpecs" in obj)).array;
        row.fileCount = specs.length;
        row.primaryFileName = firstFileNameFromSpecs(specs);
    } else if ("fileNames" in obj && (*("fileNames" in obj)).type == JSONType.array) {
        auto names = (*("fileNames" in obj)).array;
        row.fileCount = names.length;
        if (names.length > 0) {
            row.primaryFileName = names[0].str;
        }
    } else if ("fileName" in obj) {
        row.primaryFileName = (*("fileName" in obj)).str;
        row.fileCount = row.primaryFileName.length == 0 ? 0 : 1;
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
