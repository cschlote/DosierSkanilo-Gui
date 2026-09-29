/** Compact fallback details for files without specialized metadata views. */
module ui.fallbackrenderer;

import std.conv : to;

import model.blobrow : BlobRow;

/** One property/value pair shown by the fallback detail renderer. */
struct FallbackDetailRow
{
    string property;
    string value;
}

/** Build a useful identity/checksum summary when no specialized metadata exists. */
FallbackDetailRow[] fallbackDetailRows(const(BlobRow) row)
{
    auto hasSpecializedMetadata = row.hasSummaryFlags
        ? row.summaryHasMedia || row.summaryHasVideo || row.summaryHasAudio
            || row.summaryHasImage || row.summaryHasText || row.summaryHasFileType
            || row.summaryHasArchive || row.summaryHasTorrent
        : row.sourceBlob !is null
            && (row.sourceBlob.mediaInfoSig !is null
                || row.sourceBlob.fileType.length > 0
                || row.sourceBlob.archiveSpecs.length > 0
                || row.sourceBlob.torrentInfo !is null);
    if (hasSpecializedMetadata)
        return [];

    FallbackDetailRow[] rows;
    if (row.primaryFileName.length > 0)
        rows ~= FallbackDetailRow("File", row.primaryFileName);
    rows ~= FallbackDetailRow("Size", row.fileSize.to!string ~ " bytes");
    rows ~= FallbackDetailRow("Known paths", row.fileCount.to!string);
    if (row.md5.length > 0)
        rows ~= FallbackDetailRow("MD5 (base64)", row.md5);
    if (row.sha1.length > 0)
        rows ~= FallbackDetailRow("SHA1 (base64)", row.sha1);
    if (row.xxh64.length > 0)
        rows ~= FallbackDetailRow("XXH64 (base64)", row.xxh64);
    rows ~= FallbackDetailRow("Details", "No specialized metadata is available.");
    return rows;
}

@("fallback renderer shows useful identity and checksum fields")
unittest
{
    BlobRow row;
    row.primaryFileName = "notes.txt";
    row.fileSize = 128;
    row.fileCount = 2;
    row.sha1 = "abc123";

    auto details = fallbackDetailRows(row);
    assert(details.length == 5);
    assert(details[0].property == "File" && details[0].value == "notes.txt");
    assert(details[1].property == "Size" && details[1].value == "128 bytes");
    assert(details[2].property == "Known paths" && details[2].value == "2");
    assert(details[3].property == "SHA1 (base64)" && details[3].value == "abc123");
    assert(details[4].property == "Details");

    row.hasSummaryFlags = true;
    row.summaryHasVideo = true;
    assert(fallbackDetailRows(row).length == 0);
}
