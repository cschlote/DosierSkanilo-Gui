module view.textreport;

import std.array : appender;
import std.format : format;
import std.string : join, strip;
import std.algorithm : canFind;
import std.uni : toLower;

import model.blobrow;

string rowsToDisplayText(string filePath, const(BlobRow)[] rows) {
    auto lines = appender!(string[])();
    lines.put(format("Loaded file: %s", filePath));
    lines.put(format("Blob count: %s", rows.length));
    lines.put("");
    lines.put("# | Size (bytes) | Files | Media | SHA1 (base64) | Primary file");
    lines.put("--+--------------+-------+-------+---------------+-------------------------------");

    foreach (idx, row; rows) {
        auto media = row.hasMedia ? "yes" : "no";
        auto sha = row.sha1.length > 0 ? row.sha1 : "-";
        auto fileName = row.primaryFileName.length > 0 ? row.primaryFileName : "-";
        lines.put(format("%s | %s | %s | %s | %s | %s", idx + 1, row.fileSize, row.fileCount, media, sha, fileName));
    }

    return lines.data.join("\n");
}

size_t countDuplicateDigestGroups(const(BlobRow)[] rows) {
    string[] seen;
    string[] duplicates;

    foreach (row; rows) {
        if (row.sha1.length == 0) {
            continue;
        }
        if (seen.canFind(row.sha1)) {
            if (!duplicates.canFind(row.sha1)) {
                duplicates ~= row.sha1;
            }
            continue;
        }
        seen ~= row.sha1;
    }

    return duplicates.length;
}

BlobRow[] filterDuplicateRows(const(BlobRow)[] rows) {
    string[] seen;
    string[] duplicates;
    auto filtered = appender!(BlobRow[])();

    foreach (row; rows) {
        if (row.sha1.length == 0) {
            continue;
        }
        if (seen.canFind(row.sha1)) {
            if (!duplicates.canFind(row.sha1)) {
                duplicates ~= row.sha1;
            }
        } else {
            seen ~= row.sha1;
        }
    }

    foreach (row; rows) {
        if (row.sha1.length > 0 && duplicates.canFind(row.sha1)) {
            filtered.put(row);
        }
    }

    return filtered.data;
}

BlobRow[] filterRowsByText(const(BlobRow)[] rows, string needle) {
    auto trimmed = needle.strip();
    if (trimmed.length == 0) {
        auto copy = appender!(BlobRow[])();
        foreach (row; rows) {
            copy.put(row);
        }
        return copy.data;
    }

    auto q = toLower(trimmed);
    auto filtered = appender!(BlobRow[])();

    foreach (row; rows) {
        auto fileName = toLower(row.primaryFileName);
        auto sha1 = toLower(row.sha1);
        if (fileName.canFind(q) || sha1.canFind(q)) {
            filtered.put(row);
        }
    }

    return filtered.data;
}
