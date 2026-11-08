/** Per-document UI state, bindings, and preview state for one open tab.
 *
 * The document tab keeps the table model, detail widgets, preview widgets, and
 * filter state for one open JSON catalog or SQLite repository document together
 * so the UI layer can update it consistently.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.documenttab;

import dosierskanilo.catalogbackend : CatalogBackend, CatalogDocument,
    CatalogPageCursor;
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
import gtk.TreeModelFilter;
import gtk.TreeModelIF;
import gtk.ToggleButton;
import gtk.Scale;
import gtk.CheckButton;
import gtk.ComboBoxText;
import gtk.Notebook;
import gtk.SpinButton;
import gtk.Widget;

import gdkpixbuf.Pixbuf;
import gstreamer.Element;
import gstinterfaces.VideoOverlay;
import core.thread : Thread;
import dosierskanilo.operations : OperationControl, OperationKind, OperationState;
import dosierskanilo.membercontentcache : MemberContentLease;
import model.blobrow : BlobRow;
import model.treeprojection : DirectorySource, DirectoryTree, FileCursor;
import ui.filterrequeststate : FilterRequestState;
import ui.operationtaskstate : OperationTaskState;

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
/** Stable repository blob ID carried as hidden table metadata. */
enum int COL_SOURCE_ID = 9;
/** Hidden flag column: the row has a known file type. */
enum int COL_HAS_FILE_TYPE_FLAG = 10;
/** Hidden flag column: the row has media information. */
enum int COL_HAS_MEDIA_FLAG = 11;
/** Hidden flag column: the row contains a video stream. */
enum int COL_HAS_VIDEO_FLAG = 12;
/** Hidden flag column: the row contains an audio stream. */
enum int COL_HAS_AUDIO_FLAG = 13;
/** Hidden flag column: the row contains an image stream. */
enum int COL_HAS_IMAGE_FLAG = 14;
/** Hidden flag column: the row contains a text stream. */
enum int COL_HAS_TEXT_FLAG = 15;
/** Hidden flag column: the row has archive metadata. */
enum int COL_HAS_ARCHIVE_FLAG = 16;
/** Hidden flag column: the row has torrent metadata. */
enum int COL_HAS_TORRENT_FLAG = 17;
/** Total number of columns in the main table model. */
enum int COL_COUNT = 18;

/** How an image preview is scaled inside its available area. */
enum PreviewScaleMode : int
{
    /// Preserve aspect ratio and fit the whole image inside the area.
    contain = 0,
    /// Scale the image so its width fills the viewport.
    fitWidth = 1,
    /// Scale the image so its height fills the viewport.
    fitHeight = 2,
    /// Show the image at its natural size, centered in the viewport.
    center = 3,
    /// Preserve aspect ratio and fill the whole area, cropping overflow.
    cover = 4,
}

/** Sort order offered for directory-tree rows. */
enum TreeSortOrder : int
{
    /// Sort by display name in ascending order.
    nameAscending = 0,
    /// Sort by display name in descending order.
    nameDescending = 1,
    /// Sort by aggregate file size, smallest first.
    sizeAscending = 2,
    /// Sort by aggregate file size, largest first.
    sizeDescending = 3,
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

/** Per-document UI and catalog state for one JSON or repository tab. */
class DocumentTab
{
    /// Path or repository locator that identifies the document's source.
    string filePath;
    /// Current text filter; an empty or whitespace-only string means no text criterion.
    string filterQuery = "";
    /// Whether rows must contain a video stream to match the filter.
    bool filterVideo;
    /// Whether rows must contain an audio stream to match the filter.
    bool filterAudio;
    /// Whether rows must contain an image stream to match the filter.
    bool filterImage;
    /// Whether rows must contain a text stream to match the filter.
    bool filterText;
    /// Invert the video/audio/image/text criteria instead of requiring them.
    bool filterMediaNegated;
    /// Whether rows must have a known file type to match the filter.
    bool filterFileType;
    /// Whether rows must have archive metadata to match the filter.
    bool filterArchive;
    /// Whether rows must have torrent metadata to match the filter.
    bool filterTorrent;

    /// Root container widget of the document page.
    Box pageRoot;
    /// Container that hosts the filter bar widgets.
    Box filterSlot;
    /// Text entry holding the user-entered filter query.
    Entry filterEntry;
    /// Check button that selects case-sensitive text matching.
    CheckButton filterCaseSensitiveWidget;
    /// Check button that toggles the video filter criterion.
    CheckButton filterVideoWidget;
    /// Check button that toggles the audio filter criterion.
    CheckButton filterAudioWidget;
    /// Check button that toggles the image filter criterion.
    CheckButton filterImageWidget;
    /// Check button that toggles the text-stream filter criterion.
    CheckButton filterTextWidget;
    /// Check button that inverts the media-type filter criteria.
    CheckButton filterMediaNotWidget;
    /// Check button that requires a known file type.
    CheckButton filterFileTypeWidget;
    /// Check button that requires archive metadata.
    CheckButton filterArchiveWidget;
    /// Check button that requires torrent metadata.
    CheckButton filterTorrentWidget;
    /// Button that applies the current filter criteria.
    Button btnApplyFilter;
    /// Button that clears the current filter criteria.
    Button btnClearFilter;
    /// Main paned widget separating the result views from the detail pane.
    Paned split;
    /// GtkBuilder that owns the page shell widgets.
    Builder pageBuilder;
    /// GtkBuilder that owns the detail-pane widgets.
    Builder detailBuilder;
    /// GtkBuilder that owns the preview-pane widgets.
    Builder previewBuilder;
    /// Flat list store backing the blob table for JSON documents.
    ListStore tableStore;
    /// Virtual table model used for repository rows; null when the flat list store is used.
    TreeModelIF repositoryTableModel;
    /// Tree view that displays the blob table.
    TreeView tableView;
    /// Tree store that holds directory-tree rows.
    TreeStore directoryTreeStore;
    /// Filter model that hides directory-tree rows excluded by the active filter.
    TreeModelFilter directoryTreeFilterModel;
    /// Tree view that displays the filtered directory tree.
    TreeView directoryTreeView;
    /// Directory projection currently displayed in the tree, possibly filtered.
    DirectoryTree directoryTree;
    /// Unfiltered directory projection kept so filtered views can be rebuilt.
    DirectoryTree unfilteredDirectoryTree;
    /// Directory source queried when the user expands tree nodes.
    DirectorySource directorySource;
    /// Complete directory source used as the basis for filtering and refreshes.
    DirectorySource unfilteredDirectorySource;
    /// Whether the directory source is backed by a catalog repository instead of a local JSON file.
    bool directorySourceRemote;
    /// Whether the tree currently shows a filtered projection rather than the full tree.
    bool directorySourceFiltered;
    /// Set of tree node IDs that are currently visible after filtering.
    bool[string] visibleTreeNodeIds;
    /// Visibility flags indexed by canonical file index in the tree projection.
    bool[] visibleTreeFileIndexes;
    /// Visibility flags indexed by canonical directory index in the tree projection.
    bool[] visibleTreeDirectoryIndexes;
    /// Number of visible files per directory, indexed by directory source index.
    size_t[] visibleDirectoryFileCounts;
    /// Total byte size of visible files per directory, indexed by directory source index.
    ulong[] visibleDirectoryAggregateSizes;
    /// Number of visible child entries per directory, indexed by directory source index.
    size_t[] visibleDirectoryChildCounts;
    /// Whether the active filter matched at least one tree node.
    bool hasVisibleTreeMatches;
    /// Whether an existing tree can be updated in place instead of being cleared and rebuilt.
    bool reuseDirectoryTreeNodes;
    /// Whether materialized tree nodes should survive the next source load.
    bool preserveDirectoryTreeNodesOnNextLoad;
    /// Monotonic token used to discard stale asynchronous expanded-directory refreshes.
    ulong directoryTreeRefreshRequestId;
    /// IDs of directories the user expanded, restored after a tree rebuild.
    string[] expandedDirectoryIds;
    /// Callback that reconciles placeholder loading rows after a source load; may be null.
    void delegate() reconcileDirectoryLoads;
    /// Guard that suppresses reciprocal table/tree selection handlers while a selection is synchronized.
    bool syncingTreeSelection;
    /// File ID to reveal and select as soon as its tree row exists; empty when nothing is pending.
    string pendingTreeRevealFileId;
    /// Directory ID whose first child should be selected after expansion; empty when nothing is pending.
    string pendingTreeFirstChildNodeId;
    /// Stable ID of the selected tree file; empty when the selection is not a file.
    string selectedTreeFileId;
    /// Stable ID of the selected tree directory, used to restore the directory cursor.
    string selectedTreeDirectoryId;
    /// Cursor metadata for the last selected tree file.
    FileCursor selectedTreeCursor;
    /// Row selected directly from the repository table when no tree selection drives details.
    BlobRow directSelectedRow;
    /// Whether `directSelectedRow` holds a valid selection.
    bool hasDirectSelectedRow;
    /// Row index label displayed for a direct selection; `"Tree"` for tree-driven selections.
    string directSelectedIndex;
    /// Entry showing the selected row's display index.
    Entry detailIndexEntry;
    /// Entry showing the selected row's formatted file size.
    Entry detailSizeEntry;
    /// Entry showing the selected row's SHA-1 checksum in hexadecimal form.
    Entry detailSha1HexEntry;
    /// Entry showing the selected row's MD5 checksum in hexadecimal form.
    Entry detailMd5HexEntry;
    /// Entry showing the selected row's XXH64 checksum in hexadecimal form.
    Entry detailXxh64HexEntry;
    /// Status label summarising checksum availability for the selected row.
    Label detailChecksumStatus;
    /// Heading label for the known-file-names list.
    Label detailFileNamesLabel;
    /// Button that selects the previous known file name for the row.
    Button detailPreviousFileButton;
    /// Button that selects the next known file name for the row.
    Button detailNextFileButton;
    /// Title label at the top of the preview pane.
    Label detailPreviewTitle;
    /// Multiline summary label describing the current preview.
    Label detailPreviewSummary;
    /// Scrolled container around the preview summary label.
    ScrolledWindow detailPreviewSummaryScroll;
    /// Scrolled container around the text or hex preview.
    ScrolledWindow detailPreviewTextScroll;
    /// Text view that renders text and hexadecimal previews.
    TextView detailPreviewTextView;
    /// Scrolled container around the archive member tree preview.
    ScrolledWindow detailPreviewArchiveScroll;
    /// Scrolled container around the torrent member tree preview.
    ScrolledWindow detailPreviewTorrentScroll;
    /// Status label inside the MediaInfo expander.
    Label detailMediaInfoStatus;
    /// Status label inside the file-type expander.
    Label detailFileTypeStatus;
    /// Status label inside the archive expander.
    Label detailArchiveStatus;
    /// Status label inside the torrent expander.
    Label detailTorrentStatus;
    /// Expander that holds the checksum details section.
    Expander detailChecksumExpander;
    /// Expander that holds the MediaInfo stream section.
    Expander detailMediaInfoExpander;
    /// Expander that holds the file-type details section.
    Expander detailFileTypeExpander;
    /// Expander that holds the archive details section.
    Expander detailArchiveExpander;
    /// Expander that holds the torrent details section.
    Expander detailTorrentExpander;
    /// Paned widget separating the preview summary from the media preview area.
    Paned detailPreviewSplit;
    /// Toggle button selecting `PreviewScaleMode.contain`.
    ToggleButton detailPreviewContainButton;
    /// Toggle button selecting `PreviewScaleMode.fitWidth`.
    ToggleButton detailPreviewFitWidthButton;
    /// Toggle button selecting `PreviewScaleMode.fitHeight`.
    ToggleButton detailPreviewFitHeightButton;
    /// Toggle button selecting `PreviewScaleMode.center`.
    ToggleButton detailPreviewCenterButton;
    /// Toggle button selecting `PreviewScaleMode.cover`.
    ToggleButton detailPreviewCoverButton;
    /// Box holding the image scale-mode controls.
    Box detailPreviewImageControls;
    /// Check button that enables autostart for audio/video previews.
    CheckButton detailPreviewAutostartButton;
    /// Button that starts or pauses audio/video playback.
    Button detailPreviewPlayButton;
    /// Button that seeks the audio/video preview backward.
    Button detailPreviewJumpBackButton;
    /// Button that seeks the audio/video preview forward.
    Button detailPreviewJumpForwardButton;
    /// Row that holds the video, audio, and subtitle track selectors.
    Box detailPreviewTrackSelectorsRow;
    /// Box containing the video track selector.
    Box detailPreviewVideoTrackBox;
    /// Box containing the audio track selector.
    Box detailPreviewAudioTrackBox;
    /// Box containing the subtitle track selector.
    Box detailPreviewSubtitleTrackBox;
    /// Combo box that selects the active video track.
    ComboBoxText detailPreviewVideoTrackCombo;
    /// Combo box that selects the active audio track.
    ComboBoxText detailPreviewAudioTrackCombo;
    /// Combo box that selects the active subtitle track.
    ComboBoxText detailPreviewSubtitleTrackCombo;
    /// Label showing the current playback position and duration.
    Label detailPreviewPositionLabel;
    /// Scale used to seek within the audio/video preview.
    Scale detailPreviewPositionScale;
    /// Scale controlling preview volume in the range 0.0 to 1.0.
    Scale detailPreviewVolumeScale;
    /// Image widget that renders still-image previews.
    Image detailPreviewImage;
    /// Aspect frame that hosts either the drawing area or a custom video sink widget.
    AspectFrame detailPreviewVideoFrame;
    /// Drawing area used as the video output surface by overlay-based sinks.
    DrawingArea detailPreviewVideoArea;
    /// Custom GTK video sink widget when the sink renders itself; null for overlay-based sinks.
    Widget detailPreviewVideoSinkWidget;
    /// Box holding the audio/video playback controls.
    Box detailPreviewVideoControls;
    /// Scrolled container around the image or video preview.
    ScrolledWindow detailPreviewScroll;
    /// Tree store holding MediaInfo stream rows.
    TreeStore detailMediaInfoStore;
    /// Tree view displaying media stream rows.
    TreeView detailMediaInfoTreeView;
    /// Expander that holds fallback property rows when no specialized metadata exists.
    Expander detailFallbackExpander;
    /// Status label inside the fallback details expander.
    Label detailFallbackStatus;
    /// Tree store holding fallback property/value rows.
    TreeStore detailFallbackStore;
    /// Tree view displaying fallback property/value rows.
    TreeView detailFallbackTreeView;
    /// Label showing the file-type description.
    Label detailFileTypeLabel;
    /// Text view showing raw archive metadata.
    TextView detailArchiveView;
    /// Text view showing raw torrent metadata.
    TextView detailTorrentView;
    /// Tree store holding archive member rows.
    TreeStore detailArchiveTreeStore;
    /// Tree view displaying archive member rows.
    TreeView detailArchiveTreeView;
    /// Tree store holding torrent member rows.
    TreeStore detailTorrentTreeStore;
    /// Tree view displaying torrent member rows.
    TreeView detailTorrentTreeView;
    /// Monotonic token used to identify and invalidate nested archive/torrent entry loads.
    ulong nestedEntryRequestId;
    /// List store holding alternate known file names for the selected row.
    ListStore detailFileNamesStore;
    /// Tree view displaying alternate known file names.
    TreeView detailFileNamesView;
    /// GStreamer `playbin` element used for audio/video previews; null until created.
    Element previewVideoPlayer;
    /// GStreamer video sink element selected for the preview player.
    Element previewVideoSink;
    /// Overlay interface used to attach overlay-based sinks; null for other sink types.
    VideoOverlay previewVideoOverlay;
    /// Button that copies the selected row's SHA-1 checksum.
    Button btnCopySha1;
    /// Button that copies the selected row's file name.
    Button btnCopyFile;
    /// Button that copies the selected row's file path.
    Button btnCopyPath;
    /// Button that copies the assembled detail text.
    Button btnCopyDetails;
    /// Label summarising the currently selected row.
    Label rowDetails;
    /// General status label for load, filter, and operation messages.
    Label status;
    /// Button that moves to the previous result page.
    Button pagePreviousButton;
    /// Button that moves to the next result page.
    Button pageNextButton;
    /// Button that moves to the first result page.
    Button pageFirstButton;
    /// Button that moves to the last result page.
    Button pageLastButton;
    /// Button that moves to the previous file in the tree.
    Button treePreviousFileButton;
    /// Button that moves to the next file in the tree.
    Button treeNextFileButton;
    /// Combo box that selects the number of rows per page.
    ComboBoxText pageSizeCombo;
    /// Combo box that selects the directory-tree sort order.
    ComboBoxText treeSortCombo;
    /// Sort order currently applied to directory-tree rows.
    TreeSortOrder treeSortOrder = TreeSortOrder.nameAscending;
    /// Notebook that switches between the directory tree and the blob table.
    Notebook resultViews;
    /// Index of the currently visible notebook page.
    int resultViewPage;
    /// Whether the current filter criteria have been applied to the displayed rows.
    bool filterApplied;
    /// Whether the blob table currently has an active sort column.
    bool tableSortEnabled;
    /// Gtk column ID of the active table sort; -1 when no column is sorted.
    int tableSortColumnId = -1;
    /// Active table sort direction as a `GtkSortType` value.
    int tableSortOrder;
    /// Label showing the current result page range or matching-row count.
    Label pageStatus;
    /// Container that holds the pagination controls and page status.
    Box pageBar;
    /// Filesystem path of the preview currently shown; empty when no preview is active.
    string selectedPreviewPath = "";
    /// Container archive path used for the current archive-member preview; empty when not applicable.
    string archivePreviewContainerPath;
    /// Logical path of the selected member inside the archive preview container.
    string selectedArchiveMemberPath;
    /// Lease that keeps the selected archive member's content available; null when none is held.
    MemberContentLease selectedArchiveMemberLease;
    /// Token used to discard stale archive-member preview loads.
    ulong archiveMemberPreviewRequestId;
    /// Token used to discard stale preview path checks.
    ulong previewPathRequestId;
    /// Whether a preview path check is currently in flight.
    bool previewPathCheckPending;
    /// Whether the selected preview is a still image.
    bool selectedPreviewIsImage;
    /// Whether the selected preview is text.
    bool selectedPreviewIsText;
    /// Whether the selected preview is an archive listing.
    bool selectedPreviewIsArchive;
    /// Whether the selected preview is a torrent listing.
    bool selectedPreviewIsTorrent;
    /// Image scaling mode used by the preview.
    PreviewScaleMode previewScaleMode = PreviewScaleMode.contain;
    /// Whether audio/video previews start automatically.
    bool previewVideoAutostart;
    /// Preview volume in the range 0.0 to 1.0.
    double previewVideoVolume = 0.5;
    /// Guard that suppresses seek handlers while the position control is updated programmatically.
    bool previewVideoPositionSyncing;
    /// Whether playback should start once the pending media has loaded.
    bool previewVideoPendingPlayback;
    /// Explicit play decision to apply after a pending video window sync completes.
    bool previewVideoPendingPlaybackOverride;
    /// Guard that suppresses track-selection handlers while track controls are rebuilt.
    bool previewVideoTrackSyncing;
    /// Whether the video window handle still needs to be attached once the widget is realized.
    bool previewVideoPendingWindowSync;
    /// Number of known video tracks; -1 when the track list has not been discovered.
    int previewVideoTrackCount = -1;
    /// Number of known audio tracks; -1 when the track list has not been discovered.
    int previewAudioTrackCount = -1;
    /// Number of known subtitle tracks; -1 when the track list has not been discovered.
    int previewSubtitleTrackCount = -1;
    /// Display labels for the known video tracks.
    string[] previewVideoTrackLabels;
    /// Display labels for the known audio tracks.
    string[] previewAudioTrackLabels;
    /// Display labels for the known subtitle tracks.
    string[] previewSubtitleTrackLabels;
    /// Joined video-track labels used to detect when the selector needs rebuilding.
    string previewVideoTrackSignature;
    /// Joined audio-track labels used to detect when the selector needs rebuilding.
    string previewAudioTrackSignature;
    /// Joined subtitle-track labels used to detect when the selector needs rebuilding.
    string previewSubtitleTrackSignature;
    /// Path of the image file whose decoded pixbuf is cached in `selectedPreviewSourcePixbuf`.
    string selectedPreviewSourcePath = "";
    /// Cached decoded source pixbuf for the current image preview; null when not loaded.
    Pixbuf selectedPreviewSourcePixbuf;

    /// All rows loaded from the source before filtering.
    BlobRow[] loadedRows;
    /// Rows currently eligible for display after filtering.
    BlobRow[] visibleRows;
    /// Cached natural width of the blob table in pixels; -1 when not measured yet.
    int tableNaturalWidth = -1;
    /// Cached minimum width of the blob table in pixels; -1 when not measured yet.
    int tableMinimumWidth = -1;
    /// Whether the horizontal split should be fitted after the next load completes.
    bool fitHorizontalSplitAfterLoad;
    /// Whether blob-table column widths still need to be measured.
    bool pendingColumnMeasurement;
    /// Checksum string of the selected row; empty when no row is selected.
    string selectedSha1 = "";
    /// Display name of the selected file; empty when no file is selected.
    string selectedFileName = "";
    /// Path of the selected file as shown to the user; empty when no file is selected.
    string selectedFilePath = "";
    /// Assembled detail text for the selected row, used by the copy-details action.
    string selectedDetailsText = "";
    /// Version number of the loaded data; -1 when no version is available.
    int loadedDataVersion = -1;
    /// Human-readable root shape of the loaded JSON document; `"-"` when unknown.
    string loadedRootShape = "-";
    /// Summary of the root keys in the loaded JSON document; `"-"` when unknown.
    string loadedRootKeysSummary = "-";
    /// Whether the selected preview is a video.
    bool selectedPreviewIsVideo;
    /// Whether the selected preview is audio.
    bool selectedPreviewIsAudio;
    /// Whether the current preview player was created for audio-only playback.
    bool previewVideoPlayerAudioOnly;

    /// Zero-based index of the first row on the current result page.
    size_t pageOffset;
    /// Total number of rows matching the active criteria across all pages.
    size_t pageTotal;
    /// Number of repository rows already loaded into the table during page draining.
    size_t repositoryRowsLoaded;
    /// Opaque cursor for fetching the next repository page; valid only during a load.
    CatalogPageCursor repositoryContentCursor;
    /// Catalog backend serving this document; null for plain JSON documents.
    CatalogBackend catalogBackend;
    /// JSON document session; null for transactional SQLite documents.
    CatalogDocument catalogDocument;
    /// Whether the document is backed by a repository instead of a JSON file.
    bool repositoryStorage;
    /// Filesystem root used by backend tree/preview queries.
    string sourceRoot;
    /// Whether the JSON document buffer differs from its stored catalog.
    bool modified;
    /// Number of rows requested per page; defaults to 250.
    size_t pageSize = 250;
    /// Whether all rows should be loaded instead of a single page.
    bool loadAllRows;
    shared bool archiveScanCancelled; /// Cooperative cancel flag for archive scans.
    /// Whether repository pages are being drained automatically.
    bool drainRepositoryPages;
    /// Whether the next load should continue draining repository pages.
    bool drainPageRequest;
    /// Whether the next repository page should be requested after the current render.
    bool drainAfterRender;
    /// Whether the document source has finished loading into this tab.
    bool sourceLoaded;
    /// Latest-wins state for asynchronous filter requests.
    FilterRequestState filterRequest;

    /// Generation token used to discard stale document loads.
    ulong loadRequestId;
    /// Generation token used to discard stale table renders.
    ulong renderRequestId;
    /// Generation token used to discard stale detail loads.
    ulong detailRequestId;
    /// Control interface for the active backend operation; null when idle.
    OperationControl operationControl;
    /// Worker thread running the active backend operation; null when idle.
    Thread operationThread;
    /// ID of the active backend operation; 0 when no operation is active.
    ulong activeOperationId;
    /// Kind of the active backend operation.
    OperationKind activeOperationKind;
    /// Last acknowledged state of the active backend operation.
    OperationState operationState;
    /// Whether a backend operation is currently running for this document.
    bool operationRunning;
    /// Whether the active backend operation currently supports pausing.
    bool operationPauseAvailable;
    /// Whether the active backend operation is paused.
    bool operationPaused;
    /// Validated lifecycle state used to reject stale operation events.
    OperationTaskState operationTaskState;
    /// Duration of the last load in milliseconds; -1 when not measured.
    long lastLoadElapsedMs = -1;
    /// Duration of the last filter pass in milliseconds; -1 when not measured.
    long lastFilterElapsedMs = -1;
    /// Duration of the last table render in milliseconds; -1 when not measured.
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
