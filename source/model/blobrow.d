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

import dosierskanilo.model.namedbinaryblob;

/** Flat row model for the main result table.
 *
 * We use the DosierSkanilo library's `NamedBinaryBlob` as the canonical data model for scanner output.
 * `BlobRow` is a flattened projection of the most relevant fields for GUI display and interaction.
 *
 * Fields are intentionally string/number primitives so they can be mapped
 * directly into GTK list store columns.
 */
struct BlobRow {
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

