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
import gtk.ToggleButton;
import gtk.Scale;
import gtk.CheckButton;
import gtk.ComboBoxText;
import gtk.Widget;

import gdkpixbuf.Pixbuf;
import gstreamer.Element;
import gstinterfaces.VideoOverlay;
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

enum PreviewScaleMode : int
{
    contain = 0,
    fitWidth = 1,
    fitHeight = 2,
    center = 3,
    cover = 4,
}

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

    ulong loadRequestId;
    ulong filterRequestId;
    ulong renderRequestId;
    long pendingLoadElapsedMs = -1;
    string pendingStatusSuffix = "";
    long lastLoadElapsedMs = -1;
    long lastFilterElapsedMs = -1;
    long lastRenderElapsedMs = -1;
}
