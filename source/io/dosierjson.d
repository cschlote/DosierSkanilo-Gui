module io.dosierjson;

import std.array : appender;
import std.json : JSONType, JSONValue;

import model.blobrow;

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
