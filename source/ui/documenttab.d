/** Per-document UI state, bindings, and preview state for one open tab.
 *
 * The document tab keeps the table model, detail widgets, preview widgets, and
 * filter state for a single loaded JSON document together so the UI layer can
 * update it consistently.
 */
module ui.documenttab;

import gtk.AspectFrame;
import gtk.Box;
import gtk.Button;
import gtk.DrawingArea;
import gtk.Entry;
import gtk.Builder;
import gtk.Expander;
import gtk.Image;
import gtk.Label;
import gtk.ListStore;
import gtk.Paned;
import gtk.TextView;
import gtk.ScrolledWindow;
import gtk.TreeView;
import gtk.TreeStore;
import gtk.ToggleButton;
import gtk.Scale;
import gtk.CheckButton;
import gtk.ComboBoxText;
import gtk.SpinButton;
import gtk.Widget;

import gdkpixbuf.Pixbuf;
import gstreamer.Element;
import gstinterfaces.VideoOverlay;
import model.blobrow : BlobRow;
import model.treeprojection : DirectorySource, DirectoryTree;

/** Column index for the row number in the main table model. */
enum int COL_INDEX = 0;
/** Column index for the formatted file size in the main table model. */
enum int COL_FILE_SIZE = 1;
/** Column index for the checksum summary in the main table model. */
enum int COL_CHECKSUM_SET = 2;
/** Column index for the file type summary in the main table model. */
enum int COL_FILE_TYPE = 3;
/** Column index for the media summary in the main table model. */
enum int COL_MEDIA_INFO = 4;
/** Column index for the archive marker in the main table model. */
enum int COL_HAS_ARCHIVE = 5;
/** Column index for the torrent marker in the main table model. */
enum int COL_HAS_TORRENT = 6;
/** Sort column index for the row number column. */
enum int COL_INDEX_SORT = 7;
/** Sort column index for the file size column. */
enum int COL_FILE_SIZE_SORT = 8;
/** Total number of columns in the main table model. */
enum int COL_COUNT = 9;

enum PreviewScaleMode : int
{
    contain = 0,
    fitWidth = 1,
    fitHeight = 2,
    center = 3,
    cover = 4,
}

/** Clamp an integer preview scale mode to a valid enum value.
 *
 * Params:
 *     value = Raw preview scale mode read from persisted state or settings.
 * Returns: The matching preview mode, or contain when the input is out of
 *     range.
 * Throws: None.
 */
PreviewScaleMode clampPreviewScaleMode(int value)
{
    if (value < cast(int) PreviewScaleMode.contain || value > cast(int) PreviewScaleMode.cover)
    {
        return PreviewScaleMode.contain;
    }

    return cast(PreviewScaleMode) value;
}

/** Per-document UI and data state for one open JSON file tab. */
class DocumentTab
{
    string filePath;
    string filterQuery = "";
    bool filterVideo;
    bool filterAudio;
    bool filterImage;
    bool filterText;
    bool filterMediaNegated;
    bool filterFileType;
    bool filterArchive;
    bool filterTorrent;

    Box pageRoot;
    Paned split;
    Builder pageBuilder;
    Builder detailBuilder;
    Builder previewBuilder;
    ListStore tableStore;
    TreeView tableView;
    TreeStore directoryTreeStore;
    TreeView directoryTreeView;
    DirectoryTree directoryTree;
    DirectorySource directorySource;
    bool directorySourceRemote;
    Entry detailIndexEntry;
    Entry detailSizeEntry;
    Entry detailSha1HexEntry;
    Entry detailMd5HexEntry;
    Entry detailXxh64HexEntry;
    Label detailChecksumStatus;
    Label detailFileNamesLabel;
    Label detailPreviewTitle;
    Label detailPreviewSummary;
    Label detailMediaInfoStatus;
    Label detailFileTypeStatus;
    Label detailArchiveStatus;
    Label detailTorrentStatus;
    Expander detailChecksumExpander;
    Expander detailMediaInfoExpander;
    Expander detailFileTypeExpander;
    Expander detailArchiveExpander;
    Expander detailTorrentExpander;
    Paned detailPreviewSplit;
    ToggleButton detailPreviewContainButton;
    ToggleButton detailPreviewFitWidthButton;
    ToggleButton detailPreviewFitHeightButton;
    ToggleButton detailPreviewCenterButton;
    ToggleButton detailPreviewCoverButton;
    Box detailPreviewImageControls;
    CheckButton detailPreviewAutostartButton;
    Button detailPreviewPlayButton;
    Button detailPreviewJumpBackButton;
    Button detailPreviewJumpForwardButton;
    Box detailPreviewTrackSelectorsRow;
    Box detailPreviewVideoTrackBox;
    Box detailPreviewAudioTrackBox;
    Box detailPreviewSubtitleTrackBox;
    ComboBoxText detailPreviewVideoTrackCombo;
    ComboBoxText detailPreviewAudioTrackCombo;
    ComboBoxText detailPreviewSubtitleTrackCombo;
    Label detailPreviewPositionLabel;
    Scale detailPreviewPositionScale;
    Scale detailPreviewVolumeScale;
    Image detailPreviewImage;
    AspectFrame detailPreviewVideoFrame;
    DrawingArea detailPreviewVideoArea;
    Widget detailPreviewVideoSinkWidget;
    Box detailPreviewVideoControls;
    ScrolledWindow detailPreviewScroll;
    TextView detailMediaInfoView;
    TextView detailFileTypeView;
    TextView detailArchiveView;
    TextView detailTorrentView;
    ListStore detailFileNamesStore;
    TreeView detailFileNamesView;
    Element previewVideoPlayer;
    Element previewVideoSink;
    VideoOverlay previewVideoOverlay;
    Button btnCopySha1;
    Button btnCopyFile;
    Button btnCopyDetails;
    Label rowDetails;
    Label status;
    Label perfStatus;
    Label fileMetaStatus;
    Button pagePreviousButton;
    Button pageNextButton;
    Button pageFirstButton;
    Button pageLastButton;
    ComboBoxText pageSizeCombo;
    Label pageStatus;
    Box pageBar;
    string selectedPreviewPath = "";
    bool selectedPreviewIsImage;
    PreviewScaleMode previewScaleMode = PreviewScaleMode.contain;
    bool previewVideoAutostart;
    double previewVideoVolume = 0.5;
    bool previewVideoPositionSyncing;
    bool previewVideoTrackSyncing;
    int previewVideoTrackCount = -1;
    int previewAudioTrackCount = -1;
    int previewSubtitleTrackCount = -1;
    string[] previewVideoTrackLabels;
    string[] previewAudioTrackLabels;
    string[] previewSubtitleTrackLabels;
    string previewVideoTrackSignature;
    string previewAudioTrackSignature;
    string previewSubtitleTrackSignature;
    string selectedPreviewCandidatePath = "";
    bool selectedPreviewCandidateExists;
    string selectedPreviewSourcePath = "";
    Pixbuf selectedPreviewSourcePixbuf;

    BlobRow[] loadedRows;
    BlobRow[] visibleRows;
    size_t loadedDuplicateGroups;
    int tableNaturalWidth = -1;
    int tableMinimumWidth = -1;
    bool fitHorizontalSplitAfterLoad;
    bool pendingColumnMeasurement;
    string selectedSha1 = "";
    string selectedFileName = "";
    string selectedDetailsText = "";
    int loadedDataVersion = -1;
    string loadedRootShape = "-";
    string loadedRootKeysSummary = "-";
    bool selectedPreviewIsVideo;

    size_t pageOffset;
    size_t pageTotal;
    size_t pageSize = 250;
    bool loadAllRows;

    ulong loadRequestId;
    ulong filterRequestId;
    ulong renderRequestId;
    ulong detailRequestId;
    long pendingLoadElapsedMs = -1;
    string pendingStatusSuffix = "";
    long lastLoadElapsedMs = -1;
    long lastFilterElapsedMs = -1;
    long lastRenderElapsedMs = -1;
}

@("DocumentTab preview scale mode clamping")
unittest
{
    assert(clampPreviewScaleMode(cast(int) PreviewScaleMode.contain) == PreviewScaleMode.contain);
    assert(clampPreviewScaleMode(cast(int) PreviewScaleMode.fitWidth) == PreviewScaleMode.fitWidth);
    assert(clampPreviewScaleMode(cast(int) PreviewScaleMode.fitHeight) == PreviewScaleMode.fitHeight);
    assert(clampPreviewScaleMode(cast(int) PreviewScaleMode.center) == PreviewScaleMode.center);
    assert(clampPreviewScaleMode(cast(int) PreviewScaleMode.cover) == PreviewScaleMode.cover);
    assert(clampPreviewScaleMode(-1) == PreviewScaleMode.contain);
    assert(clampPreviewScaleMode(999) == PreviewScaleMode.contain);
}
