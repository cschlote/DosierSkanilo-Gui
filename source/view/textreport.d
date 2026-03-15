/** View-layer transformation helpers for row rendering and filtering.
 *
 * The module contains pure data-to-text and row-selection helper logic that is
 * UI-toolkit agnostic. This allows table and textual presentations to share the
 * same filtering and duplicate grouping behavior.
 *
 * Authors: DosierSkanilo contributors
 * License: CC-BY-NC-SA 4.0
 */
module view.textreport;

import std.array : appender;
import std.algorithm.searching : canFind;
import std.format : format;
import std.string : join, strip;
import std.uni : toLower;

import model.blobrow;

/** Render rows as a textual report.
 *
 * Params:
 *   filePath = source file label shown in report header
 *   rows = row set to render
 * Returns:
 *   Multi-line plain text representation
 */
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

/** Count distinct SHA1 groups that occur more than once.
 *
 * Params:
 *   rows = input rows to analyze
 * Returns:
 *   Number of duplicate digest groups
 */
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

/** Filter rows to entries that belong to duplicate SHA1 groups.
 *
 * Params:
 *   rows = input row set
 * Returns:
 *   Rows participating in repeated SHA1 groups
 */
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

/** Filter rows by user query over filename and SHA1 text.
 *
 * Params:
 *   rows = input row set
 *   needle = filter query text
 *   caseSensitive = toggles case-sensitive matching
 * Returns:
 *   Filtered row subset; full copy when query is empty
 */
BlobRow[] filterRowsByText(const(BlobRow)[] rows, string needle, bool caseSensitive = false) {
    auto trimmed = needle.strip();
    if (trimmed.length == 0) {
        auto copy = appender!(BlobRow[])();
        foreach (row; rows) {
            copy.put(row);
        }
        return copy.data;
    }

    auto q = caseSensitive ? trimmed : toLower(trimmed);
    auto filtered = appender!(BlobRow[])();

    foreach (row; rows) {
        auto fileName = caseSensitive ? row.primaryFileName : toLower(row.primaryFileName);
        auto sha1 = caseSensitive ? row.sha1 : toLower(row.sha1);
        if (fileName.canFind(q) || sha1.canFind(q)) {
            filtered.put(row);
        }
    }

    return filtered.data;
}

unittest {
    BlobRow[] rows = [
        BlobRow("Alpha.mkv", 100, "", "sha-001", "", 1, "Alpha.mkv", true, false, false, "video", ""),
        BlobRow("beta.zip", 200, "", "sha-002", "", 1, "beta.zip", false, true, false, "archive", ""),
        BlobRow("gamma.txt", 50, "", "dup-sha", "", 1, "gamma.txt", false, false, false, "text", ""),
        BlobRow("delta.txt", 50, "", "dup-sha", "", 1, "delta.txt", false, false, false, "text", "")
    ];

    auto filteredInsensitive = filterRowsByText(rows, "alpha");
    assert(filteredInsensitive.length == 1);
    assert(filteredInsensitive[0].primaryFileName == "Alpha.mkv");

    auto filteredSensitiveMiss = filterRowsByText(rows, "alpha", true);
    assert(filteredSensitiveMiss.length == 0);

    auto filteredSha = filterRowsByText(rows, "dup");
    assert(filteredSha.length == 2);
}

unittest {
    BlobRow[] rows = [
        BlobRow("one.bin", 1, "", "same", "", 1, "one.bin", false, false, false, "", ""),
        BlobRow("two.bin", 2, "", "same", "", 1, "two.bin", false, false, false, "", ""),
        BlobRow("three.bin", 3, "", "other", "", 1, "three.bin", false, false, false, "", ""),
        BlobRow("empty.bin", 4, "", "", "", 1, "empty.bin", false, false, false, "", "")
    ];

    assert(countDuplicateDigestGroups(rows) == 1);

    auto duplicates = filterDuplicateRows(rows);
    assert(duplicates.length == 2);
    assert(duplicates[0].sha1 == "same");
    assert(duplicates[1].sha1 == "same");
}

unittest {
    BlobRow[] rows = [
        BlobRow("alpha.bin", 10, "", "sha-a", "", 1, "alpha.bin", false, false, false, "", "")
    ];

    auto report = rowsToDisplayText("sample.json", rows);
    assert(report.canFind("Loaded file: sample.json"));
    assert(report.canFind("Blob count: 1"));
    assert(report.canFind("alpha.bin"));
    assert(report.canFind("sha-a"));
}
