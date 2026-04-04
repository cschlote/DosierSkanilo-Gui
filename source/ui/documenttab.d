module ui.documenttab;

import gtk.Box;
import gtk.Button;
import gtk.Entry;
import gtk.Expander;
import gtk.Label;
import gtk.ListStore;
import gtk.Paned;
import gtk.TextView;
import gtk.TreeView;

import model.blobrow : BlobRow;

enum int COL_INDEX = 0;
enum int COL_FILE_SIZE = 1;
enum int COL_CHECKSUM_SET = 2;
enum int COL_FILE_TYPE = 3;
enum int COL_MEDIA_INFO = 4;
enum int COL_HAS_ARCHIVE = 5;
enum int COL_HAS_TORRENT = 6;
enum int COL_INDEX_SORT = 7;
enum int COL_FILE_SIZE_SORT = 8;
enum int COL_COUNT = 9;

/** Per-document UI and data state for one open JSON file tab. */
class DocumentTab
{
    string filePath;
    string filterQuery;
    bool filterVideo;
    bool filterAudio;
    bool filterImage;
    bool filterText;
    bool filterMediaNegated;

    Box pageRoot;
    Paned split;
    ListStore tableStore;
    TreeView tableView;
    Entry detailIndexEntry;
    Entry detailSizeEntry;
    Entry detailSha1HexEntry;
    Entry detailMd5HexEntry;
    Entry detailXxh64HexEntry;
    Label detailChecksumStatus;
    Label detailFileNamesLabel;
    Label detailMediaInfoStatus;
    Label detailArchiveStatus;
    Label detailTorrentStatus;
    Expander detailChecksumExpander;
    Expander detailMediaInfoExpander;
    Expander detailArchiveExpander;
    Expander detailTorrentExpander;
    TextView detailMediaInfoView;
    TextView detailArchiveView;
    TextView detailTorrentView;
    ListStore detailFileNamesStore;
    TreeView detailFileNamesView;
    Button btnCopySha1;
    Button btnCopyFile;
    Button btnCopyDetails;
    Label rowDetails;
    Label status;
    Label perfStatus;
    Label fileMetaStatus;

    BlobRow[] loadedRows;
    BlobRow[] visibleRows;
    size_t loadedDuplicateGroups;
    string selectedSha1;
    string selectedFileName;
    string selectedDetailsText;
    int loadedDataVersion = -1;
    string loadedRootShape = "-";
    string loadedRootKeysSummary = "-";

    ulong loadRequestId;
    ulong filterRequestId;
    ulong renderRequestId;
    long pendingLoadElapsedMs = -1;
    string pendingStatusSuffix;
    long lastLoadElapsedMs = -1;
    long lastFilterElapsedMs = -1;
    long lastRenderElapsedMs = -1;
}
