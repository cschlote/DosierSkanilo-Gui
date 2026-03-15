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

/** Flat row model for the main result table.
 *
 * Fields are intentionally string/number primitives so they can be mapped
 * directly into GTK list store columns.
 */
struct BlobRow {
    string primaryFileName; /// Preferred display filename for a blob row.
    ulong fileSize; /// Payload size in bytes.
    string md5; /// MD5 digest in base64, when available.
    string sha1; /// SHA1 digest in base64, when available.
    string xxh64; /// xxHash64 digest in base64, when available.
    size_t fileCount; /// Number of known file references for this blob.
    string fileNamesSummary; /// Concatenated file reference names for detail display.
    bool hasMedia; /// True when media metadata is present.
    bool hasArchive; /// True when archive metadata is present.
    bool hasTorrent; /// True when torrent metadata is present.
    string fileType; /// Optional file type signature from scanner metadata.
}
