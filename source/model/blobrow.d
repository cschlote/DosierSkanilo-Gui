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
    string sha1; /// SHA1 digest in base64, when available.
    size_t fileCount; /// Number of known file references for this blob.
    bool hasMedia; /// True when media metadata is present.
    string fileType; /// Optional file type signature from scanner metadata.
}
