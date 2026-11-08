/** Row projection model for table-oriented GUI rendering.
 *
 * The scanner catalog can contain rich nested structures. The GUI primarily
 * needs compact row data for list views and filters. `BlobRow` is the
 * normalized projection used between catalog/backend and view layers.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module model.blobrow;

import std.algorithm : sort;
import std.array : appender;
import std.format : format;
import std.string : join, empty;

import dosierskanilo.metadata.mediainfosig;
import dosierskanilo.model.namedbinaryblob;
import cli.logging;

/** Flat row model for the main result table.
 *
 * `BlobRow` projects either a legacy `NamedBinaryBlob` or a backend catalog
 * snapshot. It is a flattened projection of the most relevant fields for GUI
 * display and interaction.
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
    long sourceId = -1; /// Stable repository blob ID when available.
    string sourceKey; /// Catalog-relative representative path for backend rows.
    size_t sourceOrdinal = size_t.max; /// Stable source-array ordinal for JSON rows.
    bool detailsLoaded = true; /// False while repository details are lazy.
    bool hasSummaryFlags; /// True when metadata presence came from SQLite.
    /// True when the catalog summary reports any media metadata.
    bool summaryHasMedia;
    /// True when the catalog summary reports a video stream.
    bool summaryHasVideo;
    /// True when the catalog summary reports an audio stream.
    bool summaryHasAudio;
    /// True when the catalog summary reports an image stream.
    bool summaryHasImage;
    /// True when the catalog summary reports a text/subtitle stream.
    bool summaryHasText;
    /// True when the catalog summary reports file type metadata.
    bool summaryHasFileType;
    /// True when the catalog summary reports archive metadata.
    bool summaryHasArchive;
    /// True when the catalog summary reports torrent metadata.
    bool summaryHasTorrent;
    /// Legacy blob data when the row came from the in-memory projection;
    /// catalog-backed rows leave this null and use the `catalog*` fields.
    NamedBinaryBlob sourceBlob;

    /* Basic blob properties. */
    string primaryFileName; /// Preferred display filename for a blob row.
    ulong fileSize; /// Payload size in bytes.
    string md5; /// MD5 digest in base64, when available.
    string sha1; /// SHA1 digest in base64, when available.
    string xxh64; /// xxHash64 digest in base64, when available.
    size_t fileCount; /// Number of known file references for this blob.

    /* metadata presence flags and details for fold-out sections in the UI. */
    /** Whether any media metadata is present.
     *
     * Returns: `true` when the catalog summary marks media or the attached
     *     blob has a non-empty media signature.
     */
    @property bool hasMedia() const { return hasSummaryFlags ? summaryHasMedia : sourceBlob.mediaInfoSig !is null && !sourceBlob.mediaInfoSig.empty; }
    /** Whether media metadata marks a video stream.
     *
     * Returns: `true` when the catalog summary marks video or the attached
     *     blob has a media signature with a video stream.
     */
    @property bool hasVideo() const { return hasSummaryFlags ? summaryHasVideo : hasMedia && sourceBlob.mediaInfoSig.hasVideo; }
    /** Whether media metadata marks an audio stream.
     *
     * Returns: `true` when the catalog summary marks audio or the attached
     *     blob has a media signature with an audio stream.
     */
    @property bool hasAudio() const { return hasSummaryFlags ? summaryHasAudio : hasMedia && sourceBlob.mediaInfoSig.hasAudio; }
    /** Whether media metadata marks an image stream.
     *
     * Returns: `true` when the catalog summary marks images or the attached
     *     blob has a media signature with an image stream.
     */
    @property bool hasImage() const { return hasSummaryFlags ? summaryHasImage : hasMedia && sourceBlob.mediaInfoSig.hasImage; }
    /** Whether media metadata marks a text or subtitle stream.
     *
     * Returns: `true` when the catalog summary marks text or the attached blob
     *     has a media signature with a text/subtitle stream.
     */
    @property bool hasText() const { return hasSummaryFlags ? summaryHasText : hasMedia && sourceBlob.mediaInfoSig.hasText; }
    /** Whether file type signature metadata is present.
     *
     * Returns: `true` when the catalog summary marks file type metadata or the
     *     attached blob has a non-empty file type.
     */
    @property bool hasFileType() const { return hasSummaryFlags ? summaryHasFileType : sourceBlob.fileType !is null && !sourceBlob.fileType.empty; }
    /** Whether archive metadata is present.
     *
     * Returns: `true` when the catalog summary marks archives or the attached
     *     blob has at least one archive specification.
     */
    @property bool hasArchive() const { return hasSummaryFlags ? summaryHasArchive : sourceBlob.archiveSpecs.length > 0; }
    /** Whether torrent metadata is present.
     *
     * Returns: `true` when the catalog summary marks torrents or the attached
     *     blob has non-empty torrent information.
     */
    @property bool hasTorrent() const { return hasSummaryFlags ? summaryHasTorrent : sourceBlob.torrentInfo !is null && !sourceBlob.torrentInfo.empty; }

    /* Catalog-backed detail text used when no NamedBinaryBlob is attached. */
    string catalogFileType; /// File signature supplied by a catalog snapshot.
    string catalogMediaDetails; /// Rendered media streams from a catalog snapshot.
    string catalogArchiveDetails; /// Rendered archive summary from a catalog snapshot.
    string catalogTorrentDetails; /// Rendered torrent summary from a catalog snapshot.
    string catalogSourceDetails; /// Rendered identity/checksum summary.
    string catalogFileNames; /// Rendered reference paths.

    /* Fold-out details text for metadata sections, rendered from the source blob. */
    /** Pretty-printed media metadata for fold-out inspection.
     *
     * Returns: The attached blob's media details, or `catalogMediaDetails` when
     *     no blob or media signature is available.
     */
    @property string mediaInfoDetails() const { return hasMedia && sourceBlob !is null && sourceBlob.mediaInfoSig !is null ? sourceBlob.mediaInfoSig.toString() : catalogMediaDetails; }
    /** Pretty-printed file type metadata for fold-out inspection.
     *
     * Returns: The blob or catalog file type when metadata is present, or an
     *     empty string otherwise.
     */
    @property string fileTypeDetails() const { return hasFileType ? (sourceBlob !is null ? sourceBlob.fileType : catalogFileType) : ""; }
    /** Pretty-printed archive metadata for fold-out inspection.
     *
     * Returns: Rendered blob archive details or `catalogArchiveDetails` when
     *     archive metadata is present, or an empty string otherwise.
     */
    @property string archiveDetails() const { return hasArchive ? (sourceBlob !is null ? detailLines(sourceBlob.archiveSpecs) : catalogArchiveDetails) : ""; }
    /** Pretty-printed torrent metadata for fold-out inspection.
     *
     * Returns: The blob torrent details or `catalogTorrentDetails` when torrent
     *     metadata is present, or an empty string otherwise.
     */
    @property string torrentDetails() const { return hasTorrent ? (sourceBlob !is null && sourceBlob.torrentInfo !is null ? sourceBlob.torrentInfo.toString() : catalogTorrentDetails) : ""; }
    /** Optional file type signature from scanner metadata.
     *
     * Returns: The blob or catalog file type when metadata is present, or an
     *     empty string otherwise.
     */
    @property string fileType() const { return hasFileType ? (sourceBlob !is null ? sourceBlob.fileType : catalogFileType) : ""; }

    /** Render the full source object details directly from the backing blob.
     *
     * Returns: Multiline blob details, or `catalogSourceDetails` when no blob
     *     is attached.
     */
    @property string sourceBlobDetails()
    {
        return sourceBlob is null ? catalogSourceDetails : blobDetails(sourceBlob);
    }

    /** Render the known file references as a multiline block directly from the backing blob.
     *
     * Returns: One line per file reference, or `catalogFileNames` when no blob
     *     is attached.
     */
    @property string knownFileNamesText()
    {
        return sourceBlob is null ? catalogFileNames : fileSpecDetails(sourceBlob.fileSpecs);
    }
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
private string fileSpecDetails(const(FileSpec)[] specs)
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
    row.sourceBlob = blob;

    row.primaryFileName = blob.getFirstFileName;
    row.fileSize = cast(ulong) blob.fileSize;
    row.md5 = blob.checkSums.md5sum_b64;
    row.sha1 = blob.checkSums.sha1sum_b64;
    row.xxh64 = blob.checkSums.xxh64sum_b64;
    row.fileCount = blob.fileSpecs.length;

    if (blob.mediaInfoSig !is null)
    {
        // row.hasMedia = !blob.mediaInfoSig.empty;
        // row.hasImage = blob.mediaInfoSig.imageStreams.length > 0;
        // row.hasVideo = blob.mediaInfoSig.videoStreams.length > 0;
        // row.hasAudio = blob.mediaInfoSig.audioStreams.length > 0;
        // row.hasText = blob.mediaInfoSig.textStreams.length > 0;
        // row.mediaInfoDetails = blob.mediaInfoSig.toString();
    }
    // row.hasFileType = blob.fileType.length > 0;
    // row.fileTypeDetails = row.hasFileType ? blob.fileType : "";

    // row.hasArchive = blob.archiveSpecs.length > 0;
    // row.archiveDetails = detailLines(blob.archiveSpecs);

    // row.hasTorrent = blob.torrentInfo !is null;
    // row.torrentDetails = row.hasTorrent ? blob.torrentInfo.toString() : "";

    return row;
}

/** Convert a library blob array into GUI rows.
 *
 * Params:
 *     blobs = Array of library blobs to convert.
 * Returns: GUI rows in input order; the source ordinal records each blob's
 *     array position.
 */
BlobRow[] extractRowsFromBlobs(NamedBinaryBlob[] blobs)
{
    auto rows = appender!(BlobRow[])();
    foreach (index, blob; blobs)
    {
        auto row = rowFromNamedBinaryBlob(blob);
        row.sourceOrdinal = index;
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
    assert(row.sourceBlob !is null);
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
    assert(row.sourceBlob !is null);
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
    assert(row.sourceBlob !is null);
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
