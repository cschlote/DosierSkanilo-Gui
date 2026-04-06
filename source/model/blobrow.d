/** Row projection model for table-oriented GUI rendering.
 *
 * The scanner JSON can contain rich nested structures. The GUI primarily needs
 * compact row data for list views and filters. `BlobRow` is the normalized
 * projection used between parser and view layers.
 *
 * Authors: DosierSkanilo contributors
 * License: CC-BY-NC-SA 4.0
 */
module model.blobrow;

import std.algorithm : sort;
import std.array : appender;
import std.format : format;
import std.string : join;

import dosierskanilo.metadata.mediainfosig;
import dosierskanilo.model.namedbinaryblob;
import cli.logging;

/** Flat row model for the main result table.
 *
 * We use the DosierSkanilo library's `NamedBinaryBlob` as the canonical data model for scanner output.
 * `BlobRow` is a flattened projection of the most relevant fields for GUI display and interaction.
 *
 * Fields are intentionally string/number primitives so they can be mapped
 * directly into GTK list store columns.
 *
 * ToDo: Some fields are duplicated from the source blob for easier access in the UI, but this is not ideal.
 *    We should consider a more structured approach to fold-out details and metadata sections that can reference
 * the original blob data without flattening everything into the row model.
 */
struct BlobRow
{
    /* Backlink to the NamedBinaryBlob source for this row, for fold-out details and metadata sections. */
    //FIXME: NamedBinaryBlob sourceBlob; /// Original blob data for this row, for fold-out details
    string sourceBlobDetails; /// Full source JSON object for exhaustive detail inspection.

    /* Basic blob properties. */
    string primaryFileName; /// Preferred display filename for a blob row.
    ulong fileSize; /// Payload size in bytes.
    string md5; /// MD5 digest in base64, when available.
    string sha1; /// SHA1 digest in base64, when available.
    string xxh64; /// xxHash64 digest in base64, when available.
    size_t fileCount; /// Number of known file references for this blob.
    string fileNamesSummary; /// Concatenated file reference names for detail display.
    string fileNamesDetails; /// Multiline file reference list including optional access timestamps.

    /* metadata presence flags and details for fold-out sections in the UI. */
    bool hasMedia; /// True when media metadata is present.
    bool hasVideo; /// True when media metadata marks a video stream.
    bool hasAudio; /// True when media metadata marks an audio stream.
    bool hasImage; /// True when media metadata marks an image stream.
    bool hasText; /// True when media metadata marks a text/subtitle stream.
    bool hasFileType; /// True when file type signature metadata is present.
    bool hasArchive; /// True when archive metadata is present.
    bool hasTorrent; /// True when torrent metadata is present.
    string mediaInfoDetails; /// Pretty-printed media metadata for fold-out inspection.
    string fileTypeDetails; /// Pretty-printed file type metadata for fold-out inspection.
    string archiveDetails; /// Pretty-printed archive metadata for fold-out inspection.
    string torrentDetails; /// Pretty-printed torrent metadata for fold-out inspection.
    string fileType; /// Optional file type signature from scanner metadata.
}

/** Build a readable raw details block from the canonical library object.
 *
 * Params:
 *   blob = the canonical library object to convert
 * Returns:
 *   Multiline string with one line per detail, including nested file references and metadata sections
 */
private string blobDetails(NamedBinaryBlob blob)
{
    import std.array : appender;

    auto lines = appender!(string[])();
    lines.put(blob.toString());

    if (blob.fileSpecs.length > 0)
    {
        lines.put("Files:");
        lines.put(fileSpecDetails(blob.fileSpecs));
    }

    if (blob.archiveSpecs.length > 0)
    {
        lines.put("Archive:");
        lines.put(detailLines(blob.archiveSpecs));
    }

    if (blob.mediaInfoSig !is null && !blob.mediaInfoSig.empty)
    {
        lines.put("Media:");
        lines.put(blob.mediaInfoSig.toString());
    }

    if (blob.torrentInfo !is null && !blob.torrentInfo.empty)
    {
        lines.put("Torrent:");
        lines.put(blob.torrentInfo.toString());
    }

    return lines.data.join("\n");
}

/**
 * Build a readable details block for file references including optional timestamps.
 *
 * The `FileSpec` array can contain multiple file references for a blob, each with an optional last modified timestamp.
 * This function formats them into a human-readable multiline string for fold-out details display in the UI.
 *
 * Params:
 *   specs = array of file specifications from the library blob model
 * Returns:
 *   Multiline string with one line per file reference, including timestamps when available
 */
private string fileSpecDetails(FileSpec[] specs)
{
    auto lines = appender!(string[])();
    foreach (spec; specs)
    {
        if (spec is null || spec.fileName.length == 0)
        {
            continue;
        }

        auto modified = spec.timeLastModified.length > 0 ? spec.timeLastModified : "-";
        lines.put(format("%s | last modified: %s", spec.fileName, modified));
    }
    return lines.data.join("\n");
}

/** Join array items into a multiline details block using their own string form.
 *
 * Params:
 *   values = array of values to convert to strings
 * Returns:
 *   Multiline string with one line per value
 */
private string detailLines(T)(T[] values)
{
    if (values.length == 0)
    {
        return "";
    }

    auto lines = appender!(string[])();
    foreach (value; values)
    {
        static if (is(T == class))
        {
            if (value is null)
            {
                continue;
            }
        }
        lines.put(value.toString());
    }
    return lines.data.join("\n");
}

/** Convert one library blob into the flat GUI row projection.
 *
 * Params:
 *   blob = the canonical library object to convert
 * Returns:
 *   GUI row corresponding to the input blob
 */
private BlobRow rowFromNamedBinaryBlob(NamedBinaryBlob blob)
{
    BlobRow row;
    if (blob is null)
    {
        return row;
    }
    //FIXME: row.sourceBlob = blob;
    row.sourceBlobDetails = blobDetails(blob);

    auto specs = blob.fileSpecs.dup;
    specs.sort!((a, b) => a.fileName < b.fileName);

    auto names = appender!(string[])();
    foreach (spec; specs)
    {
        if (spec is null || spec.fileName.length == 0)
        {
            continue;
        }
        names.put(spec.fileName);
    }

    row.primaryFileName = blob.getFirstFileName;
    row.fileSize = cast(ulong) blob.fileSize;
    row.md5 = blob.checkSums.md5sum_b64;
    row.sha1 = blob.checkSums.sha1sum_b64;
    row.xxh64 = blob.checkSums.xxh64sum_b64;
    row.fileCount = names.data.length;
    row.fileNamesSummary = names.data.join(", ");
    row.fileNamesDetails = fileSpecDetails(specs);

    if (blob.mediaInfoSig !is null)
    {
        row.hasMedia = !blob.mediaInfoSig.empty;
        row.hasImage = blob.mediaInfoSig.imageStreams.length > 0;
        row.hasVideo = blob.mediaInfoSig.videoStreams.length > 0;
        row.hasAudio = blob.mediaInfoSig.audioStreams.length > 0;
        row.hasText = blob.mediaInfoSig.textStreams.length > 0;
        row.mediaInfoDetails = blob.mediaInfoSig.toString();
    }
    row.hasFileType = blob.fileType.length > 0;
    row.fileTypeDetails = row.hasFileType ? blob.fileType : "";

    row.hasArchive = blob.archiveSpecs.length > 0;
    row.archiveDetails = detailLines(blob.archiveSpecs);

    row.hasTorrent = blob.torrentInfo !is null;
    row.torrentDetails = row.hasTorrent ? blob.torrentInfo.toString() : "";

    return row;
}

/** Convert a library blob array into GUI rows.
 *
 * Param: blobs = array of library blobs to convert
 * Returns: array of GUI rows corresponding to the input blobs
 */
BlobRow[] extractRowsFromBlobs(NamedBinaryBlob[] blobs)
{
    auto rows = appender!(BlobRow[])();
    foreach (blob; blobs)
    {
        auto row = rowFromNamedBinaryBlob(blob);
        rows.put(row);
    }
    return rows.data;
}

/* Unit tests for BlobRow conversion and details formatting. */

@("NamedBinaryBlob to BlobRow conversion test: MediaInfo")
unittest
{
    import std.datetime.systime : SysTime;

    auto blob = new NamedBinaryBlob("alpha.mkv", 123, SysTime(1_234_567));
    blob.checkSums.md5sum_b64 = "md5";
    blob.checkSums.sha1sum_b64 = "sha1";
    blob.checkSums.xxh64sum_b64 = "xxh64";
    blob.fileType = "Matroska";
    blob.mediaInfoSig = new MediaInfoSig();
    blob.mediaInfoSig.videoStreams ~= new MediaInfoVideo(0, "de", "AV1", 1920, 1080, 25.0);
    blob.mediaInfoSig.audioStreams ~= new MediaInfoAudio(1, "de", "AAC", 2);

    auto row = rowFromNamedBinaryBlob(blob);
    assert(row.primaryFileName == "alpha.mkv");
    assert(row.fileSize == 123);
    assert(row.sha1 == "sha1");
    assert(row.fileCount == 1);
    assert(row.hasMedia);
    assert(row.hasVideo);
    assert(row.hasAudio);
    assert(!row.hasImage);
    assert(row.fileNamesDetails.length > 0);
    assert(row.sourceBlobDetails.length > 0);
    assert(row.hasFileType);
    assert(!row.hasArchive);
    assert(row.hasTorrent == false);
}

@("NamedBinaryBlob to BlobRow conversion test: Archive")
unittest
{
    import std.datetime.systime : SysTime;
    import dosierskanilo.model.namedbinaryblob : ArchiveSpec, CheckSums;

    auto blob = new NamedBinaryBlob("abc.zip", 12_345, SysTime(1_234_567));
    blob.checkSums.md5sum_b64 = "md5";
    blob.checkSums.sha1sum_b64 = "sha1";
    blob.checkSums.xxh64sum_b64 = "xxh64";
    blob.fileType = "Zip archive data";
    blob.archiveSpecs ~= new ArchiveSpec("inner.txt", 456, "2024-01-02T12:00:00Z", CheckSums("md5inner", "sha1inner", "xxh64inner"));

    auto row = rowFromNamedBinaryBlob(blob);
    assert(row.primaryFileName == "abc.zip");
    assert(row.fileSize == 12_345);
    assert(row.sha1 == "sha1");
    assert(row.fileCount == 1);
    assert(!row.hasMedia);
    assert(!row.hasVideo);
    assert(!row.hasAudio);
    assert(!row.hasImage);
    assert(row.fileNamesDetails.length > 0);
    assert(row.sourceBlobDetails.length > 0);
    assert(row.hasFileType);
    assert(row.hasArchive);
    assert(row.archiveDetails.length > 0);
    assert(row.hasTorrent == false);
}

@("NamedBinaryBlob to BlobRow conversion test: BitTorrent")
unittest
{
    import std.datetime.systime : SysTime;
    import dosierskanilo.metadata.torrentinfo : TorrentInfo;

    auto blob = new NamedBinaryBlob("abc.torrent", 12_345, SysTime(1_234_567));
    blob.checkSums.md5sum_b64 = "md5";
    blob.checkSums.sha1sum_b64 = "sha1";
    blob.checkSums.xxh64sum_b64 = "xxh64";
    blob.fileType = "BitTorrent file";
    blob.torrentInfo = new TorrentInfo();
    blob.torrentInfo.name = "abc.torrent";
    blob.torrentInfo.magnetURI = "magnet:?xt=urn:btih:...";

    auto row = rowFromNamedBinaryBlob(blob);

    assert(row.primaryFileName == "abc.torrent");
    assert(row.fileSize == 12_345);
    assert(row.sha1 == "sha1");
    assert(row.fileCount == 1);
    assert(!row.hasMedia);
    assert(!row.hasVideo);
    assert(!row.hasAudio);
    assert(!row.hasImage);
    assert(row.fileNamesDetails.length > 0);
    assert(row.sourceBlobDetails.length > 0);
    assert(row.hasTorrent);
    assert(row.torrentDetails.length > 0);
}

@("BlobRow filtering tests")
unittest
{
    import std.datetime.systime : SysTime;

    auto blob1 = new NamedBinaryBlob("one.bin", 1, SysTime(1_000));
    auto blob2 = new NamedBinaryBlob("two.bin", 2, SysTime(2_000));
    auto rows = extractRowsFromBlobs([blob1, blob2]);

    assert(rows.length == 2);
    assert(rows[0].primaryFileName == "one.bin");
    assert(rows[1].primaryFileName == "two.bin");
}
