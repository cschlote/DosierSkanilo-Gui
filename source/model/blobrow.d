module model.blobrow;

struct BlobRow {
    string primaryFileName;
    ulong fileSize;
    string sha1;
    size_t fileCount;
    bool hasMedia;
    string fileType;
}
