/** Main GTK application shell for DosierSkanilo GUI.
 *
 * This module wires together command-line startup options, JSON loading,
 * row-table rendering, and classic desktop menu actions.
 *
 * Authors: DosierSkanilo contributors
 * License: CC-BY-NC-SA 4.0
 */
module ui.mainwindow;

import gdk.c.types : GdkEventConfigure;
import gdk.Display;
import glib.Idle;
import glib.Timeout;
import gobject.Value;
import gobject.Type : GType;
import gobject.ObjectG : ObjectG;
import gobject.ParamSpec : ParamSpec;
import gtk.Builder;
import gtk.AccelGroup;
import gtk.Box;
import gtk.Button;
import gtk.AspectFrame;
import gtk.c.types : Orientation;
import gtk.c.types : GtkAccelFlags;
import gtk.CheckButton;
import gtk.Clipboard;
import gtk.ComboBoxText;
import gtk.DrawingArea;
import gtk.Entry;
import gtk.Expander;
import gtk.Image;
import gtk.FileChooserDialog;
import gtk.Grid;
import gtk.Label;
import gtk.ListStore;
import gtk.Main;
import gtk.Menu;
import gtk.MenuBar;
import gtk.MenuItem;
import gtk.Notebook;
import gtk.Paned;
import gtk.ProgressBar;
import gtk.Range;
import gtk.Scale;
import gtk.ScrolledWindow;
import gtk.Separator;
import gtk.Spinner;
import gtk.TextView;
import gtk.ToggleButton;
import gtk.TreeIter;
import gtk.TreeModelIF;
import gtk.TreeSelection;
import gtk.TreePath;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.Widget;
import gtk.Window;
import gtk.c.types : GtkAlign, GtkIconSize, GtkReliefStyle, GtkShadowType, GtkTreeViewColumnSizing;
import gdk.c.types : GdkModifierType;

import core.thread : Thread;
import core.time : MonoTime;
import std.algorithm : sort;
import std.array : appender;
import std.base64 : Base64;
import std.conv : to;
import std.file : exists;
import std.format : format;
import std.path : absolutePath, baseName, buildNormalizedPath, dirName, isAbsolute;
import std.process : Config, ProcessException, spawnProcess;
import std.stdio : writeln;
import std.string : join;
import gstreamer.GStreamer : GStreamer;
import gstreamer.c.types : GstState, GstStateChangeReturn;

import cli.commandline : CliOptions, cliUsageText, parseCliOptions;
import model.blobrow : BlobRow, extractRowsFromBlobs;
import ui.appstate : AppState, loadAppState, saveAppState;
import ui.builderutils : builderObject;
import ui.filterbar : loadFilterBarUi;
import ui.detailpane : DetailPaneCallbacks, bindDetailPaneSignals, loadDetailPaneUi;
import ui.detailpreview : DetailPreviewCallbacks, bindDetailPreviewSignals, loadDetailPreviewUi;
import ui.documenttab : COL_CHECKSUM_SET, COL_FILE_SIZE, COL_FILE_SIZE_SORT, COL_FILE_TYPE, COL_HAS_ARCHIVE, COL_HAS_TORRENT, COL_INDEX, COL_INDEX_SORT, COL_MEDIA_INFO, DocumentTab, PreviewScaleMode, clampPreviewScaleMode;
import ui.documentpage : loadDocumentPageUi;
import ui.detailswidgets : setDetailEntry,
    setMetadataStatusLabel, setMetadataDetails, setKnownFilesTable, setMediaPreview,
    refreshMediaPreview, syncVideoPreviewWindow, setVideoPreviewVolume, playVideoPreview,
    pauseVideoPreview, jumpVideoPreview, stopVideoPreview, syncVideoPreviewPosition,
    seekVideoPreview, syncVideoPlaybackButton, syncVideoTrackSelectors;
import ui.documentactions : DocumentActionCallbacks, closeCurrentDocument, reloadCurrentDocument;
import ui.fileopendialog : FileOpenDialogCallbacks, chooseAndLoadPath;
import ui.helpdialogs : showAbout, showShortcutsHelp;
import ui.loadingstatus;
import ui.preferencesdialog : PreferencesDialogCallbacks, showPreferencesDialog;
import ui.selectionstatus : boolStatusIcon, checksumStatusSummary, clearSelectionDetails,
    mediaInfoStatusSummary, metadataPresenceSummary, resetFilterState, resetPerfMetrics, updateFileMetaStatus, updatePerfStatus;
import ui.styles : installApplicationCss;
import ui.toolbarbindings : ToolbarBindingsCallbacks, bindToolbarSignals;
import ui.windowlifecycle : WindowLifecycleCallbacks, bindWindowLifecycleSignals;
import ui.startupworkflow : scheduleSelfTestQuit, startStartupWorkflow;
import ui.previewprogress : PreviewProgressCallbacks, startPreviewProgressTimer;
import ui.tablecolumns : MAIN_TABLE_FIXED_COLUMN_WIDTH, setTableColumnsResizable, configureTableColumns, configureKnownFilesColumns;
import view.textreport : countDuplicateDigestGroups, filterRowsByText;
import dosierskanilo.model.namedbinaryblob : DATA_CLASS_VERSION2, deserializeDataClassJsonFile;
import cli.logging;

/** Worker result payload for background JSON loading. */
struct AsyncLoadResult
{
    BlobRow[] allRows;
    size_t duplicateGroups;
    string filePath;
    int dataVersion = -1;
    string rootShape;
    string rootKeysSummary;
    string error;
    long elapsedMs;
}

/** Worker result payload for background text filtering. */
struct AsyncFilterResult
{
    BlobRow[] filteredRows;
    string query;
    bool caseSensitive;
    string mediaStats;
    string error;
    long elapsedMs;
}

/** Smallest window width accepted when restoring geometry. */
enum int MIN_VALID_WINDOW_WIDTH = 320;
/** Smallest window height accepted when restoring geometry. */
enum int MIN_VALID_WINDOW_HEIGHT = 240;

/** Summarize checksum availability for the list view.
 *
 * Params:
 *     row = Blob row whose checksum fields should be summarized.
 * Returns: none, partial, or full depending on checksum coverage.
 * Throws: None.
 */
string checksumSetStatus(const(BlobRow) row)
{
    auto present = 0;
    if (row.md5.length > 0)
    {
        ++present;
    }
    if (row.sha1.length > 0)
    {
        ++present;
    }
    if (row.xxh64.length > 0)
    {
        ++present;
    }

    if (present == 0)
    {
        return "none";
    }
    if (present == 3)
    {
        return "full";
    }
    return format("partial (%s/3)", present);
}

/** Summarize media subtype flags for the list view.
 *
 * Params:
 *     row = Blob row whose media flags should be summarized.
 * Returns: A compact media marker list or yes/dash when no individual type
 *     markers apply.
 * Throws: None.
 */
string mediaInfoSummary(const(BlobRow) row)
{
    auto labels = appender!(string[])();
    if (row.hasVideo)
    {
        labels.put("V");
    }
    if (row.hasAudio)
    {
        labels.put("A");
    }
    if (row.hasImage)
    {
        labels.put("I");
    }
    if (row.hasText)
    {
        labels.put("T");
    }

    if (labels.data.length > 0)
    {
        return labels.data.join(",");
    }
    return row.hasMedia ? "yes" : "-";
}

/** Estimate the natural width required for the blob table columns.
 *
 * Params:
 *     document = Active document tab whose table should be measured.
 *     columnLimit = Optional maximum column count to include in the sum.
 * Returns: Estimated width in pixels for the visible table columns.
 * Throws: None.
 */
int measureTableColumnsWidth(DocumentTab document, int columnLimit = -1)
{
    auto columnCount = cast(int) document.tableView.getNColumns();
    if (columnCount <= 0)
    {
        return 0;
    }

    if (columnLimit >= 0 && columnLimit < columnCount)
    {
        columnCount = columnLimit;
    }

    int totalWidth = 0;
    foreach (columnIndex; 0 .. columnCount)
    {
        auto column = document.tableView.getColumn(columnIndex);
        if (column is null || !column.getVisible())
        {
            continue;
        }
        auto columnWidth = column.getWidth();
        auto minWidth = column.getMinWidth();
        totalWidth += columnWidth > minWidth ? columnWidth : minWidth;
    }

    return totalWidth;
}

/** Estimate or return the cached natural width of the blob table.
 *
 * Params:
 *     document = Active document tab whose cached width should be read.
 * Returns: Cached natural width when available, otherwise a fresh estimate.
 * Throws: None.
 */
int naturalListWidth(DocumentTab document)
{
    return document.tableNaturalWidth > 0 ? document.tableNaturalWidth
        : measureTableColumnsWidth(document);
}

/** Estimate or return the cached minimum width that keeps the first two columns visible.
 *
 * Params:
 *     document = Active document tab whose cached minimum width should be read.
 * Returns: Cached minimum width when available, otherwise a fresh estimate for
 *     the leading columns.
 * Throws: None.
 */
int minimumListWidth(DocumentTab document)
{
    return document.tableMinimumWidth > 0 ? document.tableMinimumWidth
        : measureTableColumnsWidth(document, 2);
}

/** Measure the table columns once and freeze them at their natural widths.
 *
 * Params:
 *     document = Active document tab whose blob table should be measured.
 * Returns: Nothing.
 * Throws: None.
 */
void lockMainTableColumnWidths(DocumentTab document)
{
    if (document is null || document.tableView is null || document.tableNaturalWidth > 0)
    {
        return;
    }

    if (document.tableView.getModel() is null)
    {
        document.tableView.setModel(document.tableStore);
    }

    document.tableView.columnsAutosize();

    auto columnCount = cast(int) document.tableView.getNColumns();
    int totalWidth = 0;
    int minimumWidth = 0;
    logLineVerbose("[layout] measuring columns for ", document.filePath,
        ": columnCount=", columnCount);
    foreach (columnIndex; 0 .. columnCount)
    {
        auto column = document.tableView.getColumn(columnIndex);
        if (column is null || !column.getVisible())
        {
            continue;
        }

        auto measuredWidth = column.getWidth();
        auto measuredMinWidth = column.getMinWidth();
        if (measuredWidth <= 0)
        {
            measuredWidth = measuredMinWidth;
        }
        if (measuredWidth <= 0 && columnIndex >= 5)
        {
            measuredWidth = MAIN_TABLE_FIXED_COLUMN_WIDTH;
        }
        if (measuredWidth <= 0)
        {
            logLineVerbose("[layout] column ", columnIndex,
                " skipped for ", document.filePath,
                ": width=", column.getWidth(),
                ", min=", measuredMinWidth,
                ", fallbackFixed=", (columnIndex >= 5 ? MAIN_TABLE_FIXED_COLUMN_WIDTH : -1));
            continue;
        }

        column.setSizing(GtkTreeViewColumnSizing.FIXED);
        column.setFixedWidth(measuredWidth);
        totalWidth += measuredWidth;
        if (columnIndex < 2)
        {
            minimumWidth += measuredWidth;
        }
        logLineVerbose("[layout] column ", columnIndex,
            " measured for ", document.filePath,
            ": width=", measuredWidth,
            ", min=", measuredMinWidth,
            ", fallbackFixed=", (columnIndex >= 5 ? MAIN_TABLE_FIXED_COLUMN_WIDTH : -1),
            ", fixed=", measuredWidth,
            ", runningTotal=", totalWidth,
            ", runningMinimum=", minimumWidth);
    }

    document.tableNaturalWidth = totalWidth;
    document.tableMinimumWidth = minimumWidth;
    logLineVerbose("[layout] measured table widths for ", document.filePath,
        ": total=", totalWidth, ", minimum=", minimumWidth);
}

/** Measure table widths after GTK has finished laying out the current model.
 *
 * Params:
 *     document = Active document tab whose table should be finalized.
 *     fitHorizontalSplit = Callback used when the split should be fit to the
 *         measured table width.
 *     restoreSplit = Callback used when the previous split position should be
 *         restored instead.
 * Returns: Nothing.
 * Throws: None.
 */
void finalizeTableColumnMeasurement(
    DocumentTab document,
    void delegate(DocumentTab) fitHorizontalSplit,
    void delegate(DocumentTab) restoreSplit
)
{
    if (document is null || document.tableView is null)
    {
        return;
    }

    if (document.tableView.getModel() is null)
    {
        document.tableView.setModel(document.tableStore);
    }

    lockMainTableColumnWidths(document);
    logLineVerbose("[layout] finalize measurement for ", document.filePath,
        ": fitAfterLoad=", document.fitHorizontalSplitAfterLoad);

    if (document.fitHorizontalSplitAfterLoad)
    {
        if (fitHorizontalSplit !is null)
        {
            fitHorizontalSplit(document);
        }
    }
    else
    {
        if (restoreSplit !is null)
        {
            restoreSplit(document);
        }
    }
}

/** Count media subtype hits in the currently filtered row set.
 *
 * Params:
 *     rows = Blob rows to count media subtype hits from.
 * Returns: Formatted string with counts of each media subtype.
 * Throws: None.
 */
string mediaHitStats(const(BlobRow)[] rows)
{
    size_t videoCount = 0;
    size_t audioCount = 0;
    size_t imageCount = 0;
    size_t textCount = 0;
    size_t fileTypeCount = 0;
    size_t archiveCount = 0;
    size_t torrentCount = 0;

    foreach (row; rows)
    {
        if (row.hasVideo)
        {
            ++videoCount;
        }
        if (row.hasAudio)
        {
            ++audioCount;
        }
        if (row.hasImage)
        {
            ++imageCount;
        }
        if (row.hasText)
        {
            ++textCount;
        }
        if (row.hasFileType)
        {
            ++fileTypeCount;
        }
        if (row.hasArchive)
        {
            ++archiveCount;
        }
        if (row.hasTorrent)
        {
            ++torrentCount;
        }
    }

    return format("hits V:%s A:%s I:%s T:%s FT:%s AR:%s TO:%s", videoCount, audioCount, imageCount, textCount, fileTypeCount, archiveCount, torrentCount);
}

/** Convert a base64-encoded digest into lowercase hexadecimal text.
 *
 * Params:
 *     digest = Base64-encoded digest string.
 * Returns: Lowercase hexadecimal representation of the digest, or an error
 *     placeholder when the input is invalid.
 * Throws: None.
 */
string digestBase64ToHex(string digest)
{
    if (digest.length == 0)
    {
        return "-";
    }

    try
    {
        auto bytes = Base64.decode(digest);
        auto builder = appender!string();
        foreach (b; bytes)
        {
            builder.put(format("%02x", b));
        }
        return builder.data;
    }
    catch (Exception)
    {
        return "<invalid base64>";
    }
}

/** Program entry point.
 *
 * Params:
 *     args = Process command-line arguments.
 * Returns: Exit code for the application process.
 * Throws: Unexpected startup or runtime failures may propagate.
 */
int runMainWindow(string[] args, ref CliOptions cli)
{
    auto loadedState = loadAppState();

    GStreamer.init(args);
    Main.init(args);
    installApplicationCss();

    // Construct the main window and shared toolbar widgets, which will be manipulated and re-parented by document tabs.

    auto mainBuilder = new Builder();
    logLineVerbose("[ui] loading main window builder");
    mainBuilder.addFromString(import("source/ui/mainwindow.ui"));
    logLineVerbose("[ui] main window builder loaded, objects=", mainBuilder.getObjects().length);

    auto window = builderObject!Window(mainBuilder, "main", "mainWindow");
    window.setDefaultSize(loadedState.windowWidth, loadedState.windowHeight);

    auto accelGroup = new AccelGroup();
    window.addAccelGroup(accelGroup);

    auto root = builderObject!Box(mainBuilder, "main", "root");
    auto fileMenu = builderObject!Menu(mainBuilder, "main", "fileMenu");
    auto editMenu = builderObject!Menu(mainBuilder, "main", "editMenu");
    auto helpMenu = builderObject!Menu(mainBuilder, "main", "helpMenu");
    auto content = builderObject!Box(mainBuilder, "main", "content");
    auto separator = builderObject!Separator(mainBuilder, "main", "separator");
    auto toolbar = builderObject!Box(mainBuilder, "main", "toolbar");
    auto fileOpenMenuItem = builderObject!MenuItem(mainBuilder, "main", "fileOpenMenuItem");
    auto fileCloseMenuItem = builderObject!MenuItem(mainBuilder, "main", "fileCloseMenuItem");
    auto fileReloadMenuItem = builderObject!MenuItem(mainBuilder, "main", "fileReloadMenuItem");
    auto fileCancelOperationMenuItem = builderObject!MenuItem(mainBuilder, "main", "fileCancelOperationMenuItem");
    auto fileQuitMenuItem = builderObject!MenuItem(mainBuilder, "main", "fileQuitMenuItem");
    auto editApplyFilterMenuItem = builderObject!MenuItem(mainBuilder, "main", "editApplyFilterMenuItem");
    auto editClearFilterMenuItem = builderObject!MenuItem(mainBuilder, "main", "editClearFilterMenuItem");
    auto editResetMetricsMenuItem = builderObject!MenuItem(mainBuilder, "main", "editResetMetricsMenuItem");
    auto editPreferencesMenuItem = builderObject!MenuItem(mainBuilder, "main", "editPreferencesMenuItem");
    auto helpShortcutsMenuItem = builderObject!MenuItem(mainBuilder, "main", "helpShortcutsMenuItem");
    auto helpAboutMenuItem = builderObject!MenuItem(mainBuilder, "main", "helpAboutMenuItem");
    auto btnReload = builderObject!Button(mainBuilder, "main", "btnReload");
    auto btnRelayout = builderObject!Button(mainBuilder, "main", "btnRelayout");
    auto btnCancelLoad = builderObject!Button(mainBuilder, "main", "btnCancelLoad");
    auto loadSpinner = builderObject!Spinner(mainBuilder, "main", "loadSpinner");
    auto filterSlot = builderObject!Box(mainBuilder, "main", "filterSlot");
    auto filterUi = loadFilterBarUi(filterSlot);
    auto filterEntry = filterUi.filterEntry;
    auto filterMediaNot = filterUi.filterMediaNot;
    auto filterVideo = filterUi.filterVideo;
    auto filterAudio = filterUi.filterAudio;
    auto filterImage = filterUi.filterImage;
    auto filterText = filterUi.filterText;
    auto filterFileType = filterUi.filterFileType;
    auto filterArchive = filterUi.filterArchive;
    auto filterTorrent = filterUi.filterTorrent;
    auto btnApplyFilter = filterUi.btnApplyFilter;
    auto btnClearFilter = filterUi.btnClearFilter;
    auto progressBar = builderObject!ProgressBar(mainBuilder, "main", "progressBar");
    auto notebook = builderObject!Notebook(mainBuilder, "main", "notebook");

    DocumentTab[] documents;
    string[] pendingStartupPaths;
    int pendingStartupSelectIndex = -1;

    bool prefAutoApplyFilter = loadedState.prefAutoApplyFilter;
    bool prefCaseSensitiveFilter = loadedState.prefCaseSensitiveFilter;
    bool prefDetailsBelow = loadedState.prefDetailsBelow;
    bool prefRestoreOpenFiles = loadedState.prefRestoreOpenFiles;
    string externalOpenProgram = loadedState.externalOpenProgram.length > 0 ? loadedState.externalOpenProgram : "xdg-open";
    bool previewVideoAutostart = loadedState.previewVideoAutostart;
    double previewVideoVolume = loadedState.previewVideoVolume < 0.0 ? 0.5
        : loadedState.previewVideoVolume > 1.0 ? 1.0 : loadedState.previewVideoVolume;
    bool clearSavedWindowGeometryOnExit;
    bool allowRuntimeStatePersistence = !loadedState.hasWindowSize;
    bool isSyncingToolbarState;
    bool selfTestQuitScheduled;
    int splitPositionHorizontal = loadedState.splitPositionHorizontal;
    int splitPositionVertical = loadedState.splitPositionVertical;
    int splitPositionPreview = loadedState.hasSplitPositionPreview ? loadedState.splitPositionPreview : 0;
    PreviewScaleMode previewScaleMode = clampPreviewScaleMode(loadedState.previewScaleMode);
    int lastKnownWindowWidth = loadedState.windowWidth;
    int lastKnownWindowHeight = loadedState.windowHeight;
    Timeout windowSizePersistTimer;
    bool isLoading;
    DocumentTab busyDocument;
    Timeout progressPulseTimer;
    Timeout previewVideoProgressTimer;
    Timeout selfTestQuitTimer;

    if (cli.disableAutoFilter)
    {
        prefAutoApplyFilter = false;
    }
    if (cli.caseSensitiveFilter)
    {
        prefCaseSensitiveFilter = true;
    }

    if (cli.filterOnStart.length > 0)
    {
        filterEntry.setText(cli.filterOnStart);
    }
    else
    {
        filterEntry.setText("");
    }
    logLineVerbose("[startup] initial filter text length=", cli.filterOnStart.length,
        ", verbose=", cli.argVerboseOutputs);
    logLineVerbose("[startup] self-test mode=", cli.selfTestMode ? "yes" : "no",
        ", delayMs=", cli.selfTestDelayMs);

    /** Format internal timing values for status labels. */
    string formatTimingValue(long valueMs)
    {
        return valueMs >= 0 ? format("%s", valueMs) : "-";
    }

    /** Return the currently selected document tab, if any. */
    DocumentTab currentDocument()
    {
        auto pageIndex = notebook.getCurrentPage();
        if (pageIndex < 0 || pageIndex >= documents.length)
        {
            return null;
        }
        return documents[pageIndex];
    }

    /** Return the notebook page index for a given document instance. */
    int indexOfDocument(DocumentTab target)
    {
        foreach (idx, document; documents)
        {
            if (document is target)
            {
                return cast(int) idx;
            }
        }
        return -1;
    }

    /** Attach a standard application accelerator to one menu item. */
    void attachMenuAccelerator(MenuItem menuItem, char accelKey, GdkModifierType accelMods = GdkModifierType.CONTROL_MASK)
    {
        menuItem.addAccelerator("activate", accelGroup, accelKey, accelMods, GtkAccelFlags.VISIBLE);
    }

    /** Normalize a path so duplicate startup entries map to the same document tab. */
    string normalizeDocumentPath(string filePath)
    {
        if (filePath.length == 0)
        {
            return filePath;
        }
        return absolutePath(filePath);
    }

    /** Find an already open document tab by JSON file path. */
    DocumentTab findDocumentByPath(string filePath)
    {
        auto normalizedPath = normalizeDocumentPath(filePath);
        foreach (document; documents)
        {
            if (document.filePath == normalizedPath)
            {
                return document;
            }
        }
        return null;
    }

    /** Resolve a known-file entry path relative to the owning JSON file. */
    string resolveKnownFilePath(DocumentTab document, string knownFileName)
    {
        if (knownFileName.length == 0)
        {
            return "";
        }

        if (isAbsolute(knownFileName))
        {
            return knownFileName;
        }

        auto baseDirectory = dirName(document.filePath);
        if (baseDirectory.length == 0)
        {
            return knownFileName;
        }

        return buildNormalizedPath(baseDirectory, knownFileName);
    }

    /** Launch one known file in the user-configured external program. */
    void openKnownFileExternally(DocumentTab document, string knownFileName)
    {
        auto resolvedPath = resolveKnownFilePath(document, knownFileName);
        if (resolvedPath.length == 0)
        {
            return;
        }

        if (!exists(resolvedPath))
        {
            document.status.setText(format("Known file not found: %s", resolvedPath));
            return;
        }

        auto program = externalOpenProgram.length > 0 ? externalOpenProgram : "xdg-open";
        try
        {
            spawnProcess([program, resolvedPath], null, Config.detached);
        }
        catch (ProcessException ex)
        {
            document.status.setText(format("Failed to launch %s: %s", program, ex.msg));
        }
    }

    /** Refresh toolbar sensitivity from the global busy state and active tab presence. */
    void syncToolbarSensitivity()
    {
        auto hasCurrentDocument = currentDocument() !is null;
        // pathEntry und btnLoad entfernt
        btnReload.setSensitive(!isLoading && hasCurrentDocument);
        fileReloadMenuItem.setSensitive(!isLoading && hasCurrentDocument);
        btnCancelLoad.setSensitive(isLoading);
        fileCancelOperationMenuItem.setSensitive(isLoading);
        fileCloseMenuItem.setSensitive(!isLoading && hasCurrentDocument);
        fileOpenMenuItem.setSensitive(!isLoading);
        fileQuitMenuItem.setSensitive(true);
        filterEntry.setSensitive(!isLoading);
        filterVideo.setSensitive(!isLoading && hasCurrentDocument);
        filterAudio.setSensitive(!isLoading && hasCurrentDocument);
        filterImage.setSensitive(!isLoading && hasCurrentDocument);
        filterText.setSensitive(!isLoading && hasCurrentDocument);
        filterMediaNot.setSensitive(!isLoading && hasCurrentDocument);
        filterFileType.setSensitive(!isLoading && hasCurrentDocument);
        filterArchive.setSensitive(!isLoading && hasCurrentDocument);
        filterTorrent.setSensitive(!isLoading && hasCurrentDocument);
        btnApplyFilter.setSensitive(!isLoading && hasCurrentDocument);
        editApplyFilterMenuItem.setSensitive(!isLoading && hasCurrentDocument);
        btnClearFilter.setSensitive(!isLoading && hasCurrentDocument);
        editClearFilterMenuItem.setSensitive(!isLoading && hasCurrentDocument);
        editPreferencesMenuItem.setSensitive(!isLoading);
        editResetMetricsMenuItem.setSensitive(hasCurrentDocument);
        helpShortcutsMenuItem.setSensitive(true);
        helpAboutMenuItem.setSensitive(true);
    }

    /** Mirror the active tab's path and filter settings back into the shared toolbar. */
    void syncToolbarFromCurrentDocument()
    {
        isSyncingToolbarState = true;
        auto document = currentDocument();
        if (document is null)
        {
            filterVideo.setActive(false);
            filterAudio.setActive(false);
            filterImage.setActive(false);
            filterText.setActive(false);
            filterMediaNot.setActive(false);
            filterFileType.setActive(false);
            filterArchive.setActive(false);
            filterTorrent.setActive(false);
            syncToolbarSensitivity();
            isSyncingToolbarState = false;
            return;
        }

        // pathEntry entfernt
        filterEntry.setText(document.filterQuery);
        filterVideo.setActive(document.filterVideo);
        filterAudio.setActive(document.filterAudio);
        filterImage.setActive(document.filterImage);
        filterText.setActive(document.filterText);
        filterMediaNot.setActive(document.filterMediaNegated);
        filterFileType.setActive(document.filterFileType);
        filterArchive.setActive(document.filterArchive);
        filterTorrent.setActive(document.filterTorrent);
        syncToolbarSensitivity();
        isSyncingToolbarState = false;
    }

    /** Mirror the active tab's preview mode button state back into the preview toolbar. */
    void syncPreviewToolbarFromCurrentDocument()
    {
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }

        isSyncingToolbarState = true;
        document.detailPreviewContainButton.setActive(document.previewScaleMode == PreviewScaleMode.contain);
        document.detailPreviewFitWidthButton.setActive(document.previewScaleMode == PreviewScaleMode.fitWidth);
        document.detailPreviewFitHeightButton.setActive(document.previewScaleMode == PreviewScaleMode.fitHeight);
        document.detailPreviewCenterButton.setActive(document.previewScaleMode == PreviewScaleMode.center);
        document.detailPreviewCoverButton.setActive(document.previewScaleMode == PreviewScaleMode.cover);
        if (document.detailPreviewVolumeScale !is null)
        {
            document.detailPreviewVolumeScale.setValue(document.previewVideoVolume);
        }
        isSyncingToolbarState = false;
    }

    /** Update the preview-mode buttons of one tab without triggering toggle callbacks. */
    void syncPreviewToolbarFromDocument(DocumentTab document)
    {
        isSyncingToolbarState = true;
        document.detailPreviewContainButton.setActive(document.previewScaleMode == PreviewScaleMode.contain);
        document.detailPreviewFitWidthButton.setActive(document.previewScaleMode == PreviewScaleMode.fitWidth);
        document.detailPreviewFitHeightButton.setActive(document.previewScaleMode == PreviewScaleMode.fitHeight);
        document.detailPreviewCenterButton.setActive(document.previewScaleMode == PreviewScaleMode.center);
        document.detailPreviewCoverButton.setActive(document.previewScaleMode == PreviewScaleMode.cover);
        if (document.detailPreviewVolumeScale !is null)
        {
            document.detailPreviewVolumeScale.setValue(document.previewVideoVolume);
        }
        isSyncingToolbarState = false;
    }

    /** Apply one preview scaling mode to all open documents and refresh visible image previews. */
    void setPreviewScaleMode(PreviewScaleMode mode)
    {
        if (previewScaleMode == mode)
        {
            return;
        }

        previewScaleMode = mode;
        foreach (tab; documents)
        {
            tab.previewScaleMode = mode;
            if (tab.detailPreviewContainButton !is null)
            {
                syncPreviewToolbarFromDocument(tab);
            }
            if (tab.selectedPreviewIsImage)
            {
                refreshMediaPreview(tab);
            }
        }
    }

    /** Build the callback bundle required by the loading feedback helper. */
    LoadingStatusCallbacks loadingStatusCallbacks()
    {
        return LoadingStatusCallbacks(
            () { return isLoading; },
            (bool value) { isLoading = value; },
            () { return busyDocument; },
            (DocumentTab value) { busyDocument = value; },
            () { return progressPulseTimer; },
            (Timeout value) { progressPulseTimer = value; },
            () { syncToolbarSensitivity(); },
            (DocumentTab target, bool resizable) { setTableColumnsResizable(target, resizable); }
        );
    }

    /** Publish a global busy state while a tab-specific worker is active. */
    void setLoadingState(DocumentTab document, bool loading, string message = "")
    {
        ui.loadingstatus.setLoadingState(loadingStatusCallbacks(), document, loading, loadSpinner, progressBar, message);
    }

    /** Publish a load phase update onto the GTK main loop for a single document tab. */
    void setLoadingPhase(DocumentTab document, ulong expectedRequestId, string phaseText)
    {
        ui.loadingstatus.setLoadingPhase(loadingStatusCallbacks(), document, expectedRequestId, progressBar, phaseText);
    }

    /** Keep a document splitter divider within usable visible bounds. */
    int clampSplitPositionToVisibleBounds(DocumentTab document, Paned splitWidget, Orientation orientation, int requestedPosition)
    {
        enum int MIN_PRIMARY_EXTENT = 240;
        enum int MIN_DETAILS_EXTENT = 180;

        int totalExtent = orientation == Orientation.VERTICAL
            ? splitWidget.getAllocatedHeight() : splitWidget.getAllocatedWidth();

        if (totalExtent <= 0)
        {
            return requestedPosition;
        }
        if (totalExtent <= (MIN_PRIMARY_EXTENT + MIN_DETAILS_EXTENT))
        {
            return totalExtent / 2;
        }

        auto minPosition = MIN_PRIMARY_EXTENT;
        auto maxPosition = totalExtent - MIN_DETAILS_EXTENT;
        if (orientation == Orientation.HORIZONTAL)
        {
            auto naturalTableWidth = naturalListWidth(document);
            if (naturalTableWidth > 0 && naturalTableWidth < maxPosition)
            {
                maxPosition = naturalTableWidth;
            }

            minPosition = minimumListWidth(document);
        }
        if (requestedPosition < minPosition)
        {
            logLineVerbose("[layout] clamp low ", document.filePath,
                ": requested=", requestedPosition,
                ", min=", minPosition,
                ", max=", maxPosition,
                ", totalExtent=", totalExtent,
                ", natural=", naturalListWidth(document),
                ", minimum=", minimumListWidth(document));
            return minPosition;
        }
        if (requestedPosition > maxPosition)
        {
            logLineVerbose("[layout] clamp high ", document.filePath,
                ": requested=", requestedPosition,
                ", min=", minPosition,
                ", max=", maxPosition,
                ", totalExtent=", totalExtent,
                ", natural=", naturalListWidth(document),
                ", minimum=", minimumListWidth(document));
            return maxPosition;
        }
        logLineVerbose("[layout] clamp ok ", document.filePath,
            ": orientation=", cast(int) orientation,
            ", totalExtent=", totalExtent,
            ", requested=", requestedPosition,
            ", min=", minPosition,
            ", max=", maxPosition,
            ", natural=", naturalListWidth(document),
            ", minimum=", minimumListWidth(document));
        return requestedPosition;
    }

    /** Estimate the natural width required to show the blob list columns without truncating the split too early. */
    int preferredListSplitPosition(DocumentTab document)
    {
        return naturalListWidth(document);
    }

    /** Re-fit the horizontal splitter after GTK has real column widths available. */
    void schedulePreferredHorizontalSplit(DocumentTab document)
    {
        if (prefDetailsBelow)
        {
            return;
        }

        int attempt = 0;
        void delegate() fitLater;
        fitLater = {
            ++attempt;
            auto preferredPosition = preferredListSplitPosition(document);
            auto currentPosition = document.split.getPosition();
            auto targetPosition = preferredPosition > currentPosition ? preferredPosition
                : currentPosition;
            auto clampedPosition = clampSplitPositionToVisibleBounds(document, document.split, Orientation.HORIZONTAL, targetPosition);
            logLineVerbose("[layout] fit attempt ", attempt,
                " for ", document.filePath,
                ": current=", currentPosition,
                ", preferred=", preferredPosition,
                ", target=", targetPosition,
                ", clamped=", clampedPosition,
                ", tableNatural=", document.tableNaturalWidth,
                ", tableMinimum=", document.tableMinimumWidth);
            document.split.setPosition(clampedPosition);
            splitPositionHorizontal = clampedPosition;

            if (attempt >= 2 || clampedPosition == currentPosition)
            {
                return;
            }

            new Timeout(60, { fitLater(); return false; });
        };

        new Idle({ fitLater(); return false; });
    }

    /** Apply the shared details-pane orientation and divider position to one tab. */
    void applyDetailsPanePreference(DocumentTab document, bool captureCurrentPosition = true)
    {
        if (captureCurrentPosition)
        {
            auto currentOrientation = document.split.getOrientation();
            auto currentPosition = document.split.getPosition();
            if (currentOrientation == Orientation.VERTICAL)
            {
                splitPositionVertical = currentPosition;
            }
            else
            {
                splitPositionHorizontal = currentPosition;
            }
        }

        auto orientation = prefDetailsBelow ? Orientation.VERTICAL : Orientation.HORIZONTAL;
        auto splitPosition = prefDetailsBelow ? splitPositionVertical : splitPositionHorizontal;
        document.split.setOrientation(orientation);

        auto clampedPosition = clampSplitPositionToVisibleBounds(document, document.split, orientation, splitPosition);
        document.split.setPosition(clampedPosition);
        new Idle({
            auto realizedClamped = clampSplitPositionToVisibleBounds(document, document.split, orientation, splitPosition);
            document.split.setPosition(realizedClamped);
            if (orientation == Orientation.VERTICAL)
            {
                splitPositionVertical = realizedClamped;
            }
            else
            {
                splitPositionHorizontal = realizedClamped;
            }
            return false;
        });
    }

    /** Apply the shared details-pane preference to all open document tabs. */
    void applyDetailsPanePreferenceToAll(bool captureCurrentPosition = true)
    {
        foreach (document; documents)
        {
            applyDetailsPanePreference(document, captureCurrentPosition);
        }
    }

    void delegate(DocumentTab) updateSelectedRowDetails;
    void delegate(string, string, DocumentTab) copyTextToClipboard;
    DocumentTab delegate(string, bool) openDocumentFromPath;
    void delegate(DocumentTab) applyFilterForDocument;
    void delegate(DocumentTab, bool) loadDocument;

    /** Build and wire a new document tab widget hierarchy. */
    DocumentTab createDocumentTab(string filePath)
    {
        auto document = new DocumentTab();
        document.filePath = filePath;
        document.filterQuery = filterEntry.getText();
        document.previewScaleMode = previewScaleMode;
        document.previewVideoAutostart = previewVideoAutostart;
        document.previewVideoVolume = previewVideoVolume;

        document.tableStore = new ListStore([
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING
        ]);
        document.tableView = new TreeView(document.tableStore);
        configureTableColumns(document.tableView);
        document.tableView.addOnSizeAllocate((allocation, Widget _) {
            if (!document.pendingColumnMeasurement)
            {
                return;
            }

            document.pendingColumnMeasurement = false;
            new Idle({
                finalizeTableColumnMeasurement(
                document,
                (DocumentTab measuredDocument) {
                    schedulePreferredHorizontalSplit(measuredDocument);
                },
                (DocumentTab measuredDocument) {
                    applyDetailsPanePreference(measuredDocument, false);
                }
                );
                return false;
            });
        });

        auto scroll = new ScrolledWindow(null, null);
        scroll.setVexpand(true);
        scroll.setHexpand(true);
        scroll.add(document.tableView);

        auto previewUi = loadDetailPreviewUi(document);
        auto detailUi = loadDetailPaneUi(document);
        auto pageUi = loadDocumentPageUi(document);

        auto previewPane = previewUi.previewPane;
        auto detailsPane = detailUi.detailsPane;
        auto detailsContent = detailUi.detailsContent;
        auto previewSlot = detailUi.previewSlot;
        auto pageRoot = pageUi.pageRoot;
        auto splitSlot = pageUi.splitSlot;

        syncPreviewToolbarFromDocument(document);
        bindDetailPreviewSignals(document, DetailPreviewCallbacks(
            () => isSyncingToolbarState,
            (PreviewScaleMode mode) { setPreviewScaleMode(mode); },
            () { syncPreviewToolbarFromCurrentDocument(); },
            (bool value) { previewVideoAutostart = value; },
            (double value) { previewVideoVolume = value; }
        ));

        bindDetailPaneSignals(document, DetailPaneCallbacks(
            (DocumentTab doc, string fileName) { openKnownFileExternally(doc, fileName); },
            (string title, string text, DocumentTab doc) { copyTextToClipboard(title, text, doc); },
            (DocumentTab doc) { updateSelectedRowDetails(doc); }
        ));

        logLineVerbose("[ui] populating preview slot for ", filePath);
        previewSlot.packStart(previewPane, true, true, 0);
        document.detailPreviewSplit = detailsContent;
        detailsContent.addOnNotify((ParamSpec _, ObjectG __) {
            auto currentPosition = document.detailPreviewSplit.getPosition();
            splitPositionPreview = currentPosition;
        }, "position");
        detailsContent.addOnSizeAllocate((allocation, Widget _) {
            if (splitPositionPreview > 0 || allocation.width <= 0)
            {
                return;
            }

            auto initialPosition = cast(int) (allocation.width * 0.25);
            if (initialPosition < 1)
            {
                initialPosition = 1;
            }
            document.detailPreviewSplit.setPosition(initialPosition);
            splitPositionPreview = initialPosition;
        });

        document.split = new Paned(Orientation.HORIZONTAL);
        document.split.pack1(scroll, false, true);
        document.split.pack2(detailsPane, true, false);
        document.split.setPosition(splitPositionHorizontal);
        document.split.addOnNotify((ParamSpec _, ObjectG __) {
            auto currentOrientation = document.split.getOrientation();
            if (currentOrientation != Orientation.HORIZONTAL)
            {
                return;
            }

            auto currentPosition = document.split.getPosition();
            auto clampedPosition = clampSplitPositionToVisibleBounds(document, document.split, Orientation.HORIZONTAL, currentPosition);
            if (clampedPosition != currentPosition)
            {
                logLineVerbose("[layout] notify::position clamp for ", document.filePath,
                    ": current=", currentPosition,
                    ", clamped=", clampedPosition,
                    ", stored=", splitPositionHorizontal,
                    ", natural=", document.tableNaturalWidth,
                    ", minimum=", document.tableMinimumWidth);
                document.split.setPosition(clampedPosition);
                splitPositionHorizontal = clampedPosition;
            }
            else
            {
                logLineVerbose("[layout] notify::position ok for ", document.filePath,
                    ": position=", currentPosition,
                    ", stored=", splitPositionHorizontal,
                    ", natural=", document.tableNaturalWidth,
                    ", minimum=", document.tableMinimumWidth);
            }
        }, "position");

        document.rowDetails.setText("Selection: none");
        document.status.setText(format("Ready: %s", filePath));
        document.perfStatus.setText("Timings: load=- ms | filter=- ms | render=- ms");
        document.fileMetaStatus.setText("File metadata: version=- | root=- | keys=-");

        splitSlot.packStart(document.split, true, true, 0);
        document.pageRoot = pageRoot;
        document.pageRoot.showAll();

        clearSelectionDetails(document);
        updatePerfStatus(document);
        updateFileMetaStatus(document);
        applyDetailsPanePreference(document, false);
        return document;
    }

    /** Snapshot the current preferences, splitter state, window size, and open tabs. */
    AppState currentAppState(bool clearWindowGeometry = false)
    {
        AppState state;
        state.prefAutoApplyFilter = prefAutoApplyFilter;
        state.prefCaseSensitiveFilter = prefCaseSensitiveFilter;
        state.prefDetailsBelow = prefDetailsBelow;
        state.prefRestoreOpenFiles = prefRestoreOpenFiles;
        state.externalOpenProgram = externalOpenProgram;
        state.previewScaleMode = cast(int) previewScaleMode;
        state.previewVideoAutostart = previewVideoAutostart;
        state.splitPositionPreview = splitPositionPreview;
        state.hasSplitPositionPreview = splitPositionPreview > 0;

        auto document = currentDocument();
        state.previewVideoVolume = document is null
            ? previewVideoVolume
            : document.detailPreviewVolumeScale is null
                ? document.previewVideoVolume
                : document.detailPreviewVolumeScale.getValue();
        if (document !is null)
        {
            auto currentOrientation = document.split.getOrientation();
            auto currentSplitPosition = document.split.getPosition();
            if (currentOrientation == Orientation.VERTICAL)
            {
                splitPositionVertical = currentSplitPosition;
            }
            else
            {
                splitPositionHorizontal = currentSplitPosition;
            }

            if (document.detailPreviewSplit !is null)
            {
                splitPositionPreview = document.detailPreviewSplit.getPosition();
                state.splitPositionPreview = splitPositionPreview;
                state.hasSplitPositionPreview = true;
            }

            previewScaleMode = document.previewScaleMode;
        }

        state.splitPositionHorizontal = splitPositionHorizontal;
        state.splitPositionVertical = splitPositionVertical;
        state.splitPositionPreview = splitPositionPreview;
        state.previewScaleMode = cast(int) previewScaleMode;

        int width = lastKnownWindowWidth;
        int height = lastKnownWindowHeight;
        auto allocatedWidth = window.getAllocatedWidth();
        auto allocatedHeight = window.getAllocatedHeight();
        if (allocatedWidth >= MIN_VALID_WINDOW_WIDTH && allocatedHeight >= MIN_VALID_WINDOW_HEIGHT)
        {
            width = allocatedWidth;
            height = allocatedHeight;
        }
        if (width < MIN_VALID_WINDOW_WIDTH)
        {
            width = 960;
        }
        if (height < MIN_VALID_WINDOW_HEIGHT)
        {
            height = 640;
        }

        lastKnownWindowWidth = width;
        lastKnownWindowHeight = height;
        state.hasWindowSize = true;
        state.windowWidth = width;
        state.windowHeight = height;
        foreach (openDocument; documents)
        {
            state.openFilePaths ~= openDocument.filePath;
        }
        state.activeTabIndex = notebook.getCurrentPage();

        if (clearWindowGeometry)
        {
            state.hasWindowGeometry = false;
            state.windowX = 0;
            state.windowY = 0;
            state.windowMonitorIndex = -1;
            return state;
        }

        state.hasWindowGeometry = false;
        state.windowX = 0;
        state.windowY = 0;
        state.windowMonitorIndex = -1;
        return state;
    }

    /** Persist the current application state and surface write failures in the active tab. */
    void persistCurrentState(bool clearWindowGeometry = false)
    {
        try
        {
            saveAppState(currentAppState(clearWindowGeometry));
        }
        catch (Exception ex)
        {
            auto document = currentDocument();
            if (document !is null)
            {
                document.status.setText(format("Failed to persist app state: %s", ex.msg));
            }
        }
    }

    /** Re-render one document's row set into its list model in GTK-friendly batches. */
    void renderRows(DocumentTab document, const(BlobRow)[] rows, string filterLabel = "")
    {
        if (document.filePath.length == 0)
        {
            document.tableStore.clear();
            document.visibleRows = [];
            clearSelectionDetails(document);
            document.loadedDataVersion = -1;
            document.loadedRootShape = "-";
            document.loadedRootKeysSummary = "-";
            updateFileMetaStatus(document);
            document.status.setText("Ready.");
            return;
        }

        auto rowsCopy = appender!(BlobRow[])();
        rowsCopy.reserve(rows.length);
        foreach (row; rows)
        {
            rowsCopy.put(row);
        }
        auto rowsCopyData = rowsCopy.data;
        MonoTime renderStarted = MonoTime.currTime;
        auto localRenderRequestId = ++document.renderRequestId;
        enum size_t RENDER_BATCH_SIZE = 500;

        logLineVerbose("[render] start ", document.filePath,
            ": rows=", rowsCopyData.length,
            ", filter=", filterLabel.length > 0 ? filterLabel : "<none>");

        // Performance hack: un-couple TreeView for bulk-imports
        TreeModelIF oldModel = document.tableView.getModel();
        document.tableView.setModel(null);

        document.tableStore.clear();
        document.visibleRows = [];
        clearSelectionDetails(document);

        size_t nextIndex = 0;
        bool delegate() renderStep;
        renderStep = {
            if (localRenderRequestId != document.renderRequestId)
            {
                logLineVerbose("[render] aborted ", document.filePath);
                return false;
            }

            auto endIndex = nextIndex + RENDER_BATCH_SIZE;
            if (endIndex > rowsCopyData.length)
            {
                endIndex = rowsCopyData.length;
            }

            foreach (idx; nextIndex .. endIndex)
            {
                auto row = rowsCopyData[idx];
                auto indexText = to!string(idx + 1);
                auto sizeText = to!string(row.fileSize);
                auto checksumsText = checksumSetStatus(row);
                auto fileTypeText = boolStatusIcon(row.hasFileType);
                auto mediaInfoText = mediaInfoSummary(row);
                auto archiveText = boolStatusIcon(row.hasArchive);
                auto torrentText = boolStatusIcon(row.hasTorrent);

                auto indexSortText = format("%020d", cast(ulong) idx + 1);
                auto sizeSortText = format("%020d", row.fileSize);

                TreeIter iter;
                document.tableStore.append(iter);
                document.tableStore.set(
                    iter,
                    [
                    COL_INDEX, COL_FILE_SIZE, COL_CHECKSUM_SET, COL_FILE_TYPE,
                    COL_MEDIA_INFO, COL_HAS_ARCHIVE, COL_HAS_TORRENT,
                    COL_INDEX_SORT, COL_FILE_SIZE_SORT
                ],
                    [
                    indexText, sizeText, checksumsText, fileTypeText,
                    mediaInfoText, archiveText, torrentText, indexSortText,
                    sizeSortText
                ]
                );
            }

            nextIndex = endIndex;
            if (nextIndex < rowsCopyData.length)
            {
                document.status.setText(format("Rendering rows: %s/%s ...", nextIndex, rowsCopyData
                        .length));
                return true;
            }

            document.visibleRows = rowsCopyData.dup;
            document.lastRenderElapsedMs = cast(long)(MonoTime.currTime - renderStarted)
                .total!"msecs";
            updatePerfStatus(document);
            logLineVerbose("[render] finished ", document.filePath,
                ": rows=", rowsCopyData.length,
                ", elapsedMs=", document.lastRenderElapsedMs);

            string baseStatus;
            if (filterLabel.length > 0)
            {
                baseStatus = format(
                    "Showing %s/%s rows (duplicate digest groups: %s, filter: %s, case-sensitive: %s)",
                    rowsCopyData.length,
                    document.loadedRows.length,
                    document.loadedDuplicateGroups,
                    filterLabel,
                    prefCaseSensitiveFilter ? "yes" : "no"
                );
            }
            else
            {
                baseStatus = format(
                    "Showing %s/%s rows (duplicate digest groups: %s)",
                    rowsCopyData.length,
                    document.loadedRows.length,
                    document.loadedDuplicateGroups
                );
            }

            if (document.pendingLoadElapsedMs >= 0)
            {
                baseStatus = format("%s | load time: %s ms", baseStatus, document
                        .pendingLoadElapsedMs);
                document.pendingLoadElapsedMs = -1;
            }
            if (document.pendingStatusSuffix.length > 0)
            {
                baseStatus = format("%s | %s", baseStatus, document.pendingStatusSuffix);
                document.pendingStatusSuffix = "";
            }

            // Nach dem Laden: Spaltenbreiten einmal festziehen, danach bleiben sie stabil.
            document.pendingColumnMeasurement =
                document.tableNaturalWidth <= 0 && filterLabel.length == 0 && rowsCopyData.length == document
                    .loadedRows.length;

            // Nach dem Befüllen TreeView wieder verbinden und eine neue Layout-Runde anstoßen.
            document.tableView.setModel(document.tableStore);
            if (document.pendingColumnMeasurement)
            {
                document.tableView.queueResize();
            }

            if (busyDocument is document)
            {
                setLoadingState(document, false);
            }
            document.status.setText(baseStatus);

            return false;
        };

        new Idle(renderStep);
    }

    /** Update one document tab's detail pane from the selected row. */
    updateSelectedRowDetails = (DocumentTab document) {
        TreeModelIF model;
        TreeIter iter;
        auto selection = document.tableView.getSelection();
        if (!selection.getSelected(model, iter))
        {
            clearSelectionDetails(document);
            return;
        }

        auto idx = model.getValueString(iter, COL_INDEX);
        auto size = model.getValueString(iter, COL_FILE_SIZE);
        auto checksums = model.getValueString(iter, COL_CHECKSUM_SET);
        auto fileType = model.getValueString(iter, COL_FILE_TYPE);
        auto mediaInfo = model.getValueString(iter, COL_MEDIA_INFO);
        auto archive = model.getValueString(iter, COL_HAS_ARCHIVE);
        auto torrent = model.getValueString(iter, COL_HAS_TORRENT);
        document.rowDetails.setText(format(
                "Selection: #%s | size=%s | checksums=%s | type=%s | media=%s | archive=%s | torrent=%s",
                idx,
                size,
                checksums,
                fileType,
                mediaInfo,
                archive,
                torrent
        ));

        size_t rowIndex = 0;
        try
        {
            rowIndex = to!size_t(idx) - 1;
        }
        catch (Exception)
        {
            clearSelectionDetails(document);
            document.status.setText("Failed to resolve selected row index.");
            return;
        }
        if (rowIndex >= document.visibleRows.length)
        {
            clearSelectionDetails(document);
            document.status.setText("Selected row is outside visible data range.");
            return;
        }

        auto row = document.visibleRows[rowIndex];
        document.selectedSha1 = row.sha1;
        document.selectedFileName = row.primaryFileName;
        setDetailEntry(document.detailSha1HexEntry, digestBase64ToHex(row.sha1));
        setDetailEntry(document.detailMd5HexEntry, digestBase64ToHex(row.md5));
        setDetailEntry(document.detailXxh64HexEntry, digestBase64ToHex(row.xxh64));
        setDetailEntry(document.detailIndexEntry, idx);
        setDetailEntry(document.detailSizeEntry, format("%s bytes", row.fileSize));
        setMetadataStatusLabel(document.detailChecksumStatus, "Checksums", checksumStatusSummary(
                row));
        document.detailChecksumExpander.setSensitive(
            row.md5.length > 0 || row.sha1.length > 0 || row.xxh64.length > 0
        );
        setMetadataStatusLabel(document.detailMediaInfoStatus, "MediaInfo", mediaInfoStatusSummary(
                row));
        setMetadataStatusLabel(document.detailFileTypeStatus, "File Type", metadataPresenceSummary(
                row.hasFileType));
        setMetadataStatusLabel(document.detailArchiveStatus, "Archive", metadataPresenceSummary(
                row.hasArchive));
        setMetadataStatusLabel(document.detailTorrentStatus, "Torrent", metadataPresenceSummary(
                row.hasTorrent));
        setMetadataDetails(document.detailMediaInfoExpander, document.detailMediaInfoView, "MediaInfo", row
                .mediaInfoDetails);
        setMetadataDetails(document.detailFileTypeExpander, document.detailFileTypeView, "File Type", row
                .fileTypeDetails);
        setMetadataDetails(document.detailArchiveExpander, document.detailArchiveView, "Archive", row
                .archiveDetails);
        setMetadataDetails(document.detailTorrentExpander, document.detailTorrentView, "Torrent", row
                .torrentDetails);
        setMediaPreview(document, row);
        if (document.selectedPreviewIsVideo)
        {
            new Timeout(60, {
                if (document.selectedPreviewIsVideo)
                {
                    refreshMediaPreview(document);
                }
                return false;
            });
        }
        auto detailsText = format(
            "Selected Row Details\n\n" ~
                "Index: %s\n" ~
                "All file references: %s\n" ~
                "File size: %s bytes\n" ~
                "File references: %s\n" ~
                "Media types: video=%s | audio=%s | image=%s | text=%s\n" ~
                "Checksum set: %s\n" ~
                "MD5 (hex): %s\n" ~
                "SHA1 (hex): %s\n" ~
                "xxh64 (hex): %s\n" ~
                "Has media metadata: %s\n" ~
                "Has file type metadata: %s\n" ~
                "Has archive metadata: %s\n" ~
                "Has torrent metadata: %s\n" ~
                "\nMediaInfo details\n%s\n" ~
                "\nArchive details\n%s\n" ~
                "\nTorrent details\n%s\n" ~
                "\nRaw JSON Object\n\n" ~
                "%s\n",
            idx,
            row.knownFileNamesText,
            row.fileSize,
            row.fileCount,
            row.hasVideo ? "yes" : "no",
            row.hasAudio ? "yes" : "no",
            row.hasImage ? "yes" : "no",
            row.hasText ? "yes" : "no",
            checksumSetStatus(row),
            digestBase64ToHex(row.md5),
            digestBase64ToHex(row.sha1),
            digestBase64ToHex(row.xxh64),
            row.hasMedia ? "yes" : "no",
            row.hasFileType ? "yes" : "no",
            row.hasArchive ? "yes" : "no",
            row.hasTorrent ? "yes" : "no",
            row.mediaInfoDetails.length > 0 ? row.mediaInfoDetails : "-",
            row.archiveDetails.length > 0 ? row.archiveDetails : "-",
            row.torrentDetails.length > 0 ? row.torrentDetails
                : "-",
            row.sourceBlobDetails.length > 0 ? row.sourceBlobDetails : "{}"
        );
        document.selectedDetailsText = detailsText;
        document.btnCopySha1.setSensitive(!isLoading && document.selectedSha1.length > 0);
        document.btnCopyFile.setSensitive(!isLoading && document.selectedFileName.length > 0);
        document.btnCopyDetails.setSensitive(!isLoading && document.selectedDetailsText.length > 0);
        setKnownFilesTable(document, row);
    };

    /** Copy a selected value into the system clipboard. */
    copyTextToClipboard = (string label, string value, DocumentTab document) {
        if (value.length == 0)
        {
            document.status.setText(format("No %s value available for selected row.", label));
            return;
        }

        auto display = Display.getDefault();
        if (display is null)
        {
            document.status.setText("Clipboard unavailable: no active display.");
            return;
        }

        auto clipboard = Clipboard.getDefault(display);
        if (clipboard is null)
        {
            document.status.setText("Clipboard unavailable.");
            return;
        }

        clipboard.setText(value, -1);
        document.status.setText(format("Copied %s to clipboard.", label));
    };

    /** Continue automatic startup restoration of saved tabs one file at a time. */
    void loadNextPendingStartupPath()
    {
        if (isLoading)
        {
            return;
        }

        while (pendingStartupPaths.length > 0)
        {
            auto nextPath = pendingStartupPaths[0];
            pendingStartupPaths = pendingStartupPaths[1 .. $];

            if (findDocumentByPath(nextPath) !is null)
            {
                continue;
            }

            auto document = openDocumentFromPath(nextPath, false);
            loadDocument(document, true);
            return;
        }

        if (pendingStartupPaths.length == 0)
        {
            if (!isLoading && pendingStartupSelectIndex >= 0 && pendingStartupSelectIndex < notebook.getNPages())
            {
                notebook.setCurrentPage(pendingStartupSelectIndex);
            }

            scheduleSelfTestQuit(cli.selfTestMode, selfTestQuitScheduled, cli.selfTestDelayMs, selfTestQuitTimer, () { Main.quit(); });
            return;
        }
    }

    /** Open a document in a tab, selecting it optionally, without forcing a reload. */
    openDocumentFromPath = (string filePath, bool selectTab) {
        auto normalizedPath = normalizeDocumentPath(filePath);
        auto document = findDocumentByPath(normalizedPath);
        if (document is null)
        {
            document = createDocumentTab(normalizedPath);
            documents ~= document;
            auto pageIndex = notebook.appendPage(document.pageRoot, baseName(normalizedPath));
            notebook.setTabReorderable(document.pageRoot, true);
            if (selectTab)
            {
                notebook.setCurrentPage(pageIndex);
            }
            persistCurrentState(clearSavedWindowGeometryOnExit);
        }
        else if (selectTab)
        {
            notebook.setCurrentPage(indexOfDocument(document));
        }

        syncToolbarFromCurrentDocument();
        return document;
    };

    /** Apply the active toolbar filter settings to the current document tab. */
    void applyFilterFromEntry()
    {
        if (isSyncingToolbarState)
        {
            return;
        }
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }

        document.filterQuery = filterEntry.getText();
        document.filterVideo = filterVideo.getActive();
        document.filterAudio = filterAudio.getActive();
        document.filterImage = filterImage.getActive();
        document.filterText = filterText.getActive();
        document.filterMediaNegated = filterMediaNot.getActive();
        document.filterFileType = filterFileType.getActive();
        document.filterArchive = filterArchive.getActive();
        document.filterTorrent = filterTorrent.getActive();

        applyFilterForDocument(document);
    }

    /** Apply one document tab's stored text and media filters in a background worker. */
    applyFilterForDocument = (DocumentTab document) {
        if (isLoading)
        {
            document.status.setText(
                "Background operation in progress. Please wait before filtering.");
            return;
        }
        if (document.loadedRows.length == 0)
        {
            document.status.setText("No loaded rows to filter.");
            return;
        }

        /* Abort async filter results from previous requests, if any, by invalidating their requestId with a new one. */
        auto requestId = ++document.filterRequestId;

        /* Check the filter requirements set for this document. */
        auto query = document.filterQuery;
        auto caseSensitive = prefCaseSensitiveFilter;

        auto requireVideo = document.filterVideo;
        auto requireAudio = document.filterAudio;
        auto requireImage = document.filterImage;
        auto requireText = document.filterText;
        auto negateMediaFilter = document.filterMediaNegated;

        auto requireFileType = document.filterFileType;
        auto requireArchive = document.filterArchive;
        auto requireTorrent = document.filterTorrent;

        bool hasFilterRequirements =
            requireVideo || requireAudio || requireImage || requireText
            || requireFileType || requireArchive || requireTorrent;

        /* Duplicate the loaded rows for filtering. */
        auto sourceRows = document.loadedRows.dup;

        string mediaFilterSummary()
        {
            if (!hasFilterRequirements)
            {
                return "";
            }
            auto labels = appender!(string[])();
            if (requireVideo)
                labels.put("V");
            if (requireAudio)
                labels.put("A");
            if (requireImage)
                labels.put("I");
            if (requireText)
                labels.put("T");
            if (requireFileType)
                labels.put("FT");
            if (requireArchive)
                labels.put("AR");
            if (requireTorrent)
                labels.put("TO");
            auto summary = labels.data.join(",");
            return negateMediaFilter ? format("NOT %s", summary) : summary;
        }

        setLoadingState(document, true, format("Filtering %s rows ...", sourceRows.length));
        progressBar.setText("Filtering rows ...");

        auto worker = new Thread({
            MonoTime started = MonoTime.currTime;
            AsyncFilterResult result;
            result.query = query;
            result.caseSensitive = caseSensitive;

            try
            {
                // Get first pass filtered rows based on text query, which is the most expensive part
                // and worth doing before media-type filtering to reduce the row count for media-type checks.
                result.filteredRows = filterRowsByText(sourceRows, query, caseSensitive);
                if (hasFilterRequirements)
                {
                    auto mediaFiltered = appender!(BlobRow[])();
                    foreach (row; result.filteredRows)
                    {
                        auto matchesFileType = (requireFileType && row.hasFileType);
                        auto matchesMediaInfo =
                            (requireVideo && row.hasVideo) ||
                            (requireAudio && row.hasAudio) ||
                            (requireImage && row.hasImage) ||
                            (requireText && row.hasText);
                        matchesMediaInfo = negateMediaFilter ? !matchesMediaInfo : matchesMediaInfo;
                        auto matchesArchive = (requireArchive && row.hasArchive);
                        auto matchesTorrent = (requireTorrent && row.hasTorrent);
                        auto keepRow = matchesFileType || matchesMediaInfo || matchesArchive || matchesTorrent;
                        if (keepRow)
                        {
                            mediaFiltered.put(row);
                        }
                    }
                    result.filteredRows = mediaFiltered.data;
                }
                result.mediaStats = mediaHitStats(result.filteredRows);
            }
            catch (Exception ex)
            {
                result.error = ex.msg;
            }

            result.elapsedMs = cast(long)(MonoTime.currTime - started).total!"msecs";

            new Idle({
                if (requestId != document.filterRequestId)
                {
                    return false;
                }
                if (result.error.length > 0)
                {
                    setLoadingState(document, false, format("Filtering failed: %s", result.error));
                    return false;
                }

                document.pendingStatusSuffix = format("filter time: %s ms", result.elapsedMs);
                document.lastFilterElapsedMs = result.elapsedMs;
                updatePerfStatus(document);

                auto filterLabel = result.query;
                auto mediaSummary = mediaFilterSummary();
                if (mediaSummary.length > 0 && filterLabel.length > 0)
                {
                    filterLabel = format("%s | media:%s", filterLabel, mediaSummary);
                }
                else if (mediaSummary.length > 0)
                {
                    filterLabel = format("media:%s", mediaSummary);
                }
                if (result.mediaStats.length > 0)
                {
                    filterLabel = filterLabel.length > 0
                    ? format("%s | %s", filterLabel, result.mediaStats) : result.mediaStats;
                }
                renderRows(document, result.filteredRows, filterLabel);
                return false;
            });
        });

        worker.start();
    };

    /** Rebuild the current tab's layout measurement after manual widget relayout. */
    void relayoutCurrentDocument()
    {
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }

        logLineVerbose("[relayout] manual relayout requested for ", document.filePath);
        document.pendingColumnMeasurement = true;
        document.tableView.setModel(document.tableStore);
        document.tableView.queueResize();
    }

    /** Clear all active toolbar filter state for the current document tab. */
    void clearCurrentFilter()
    {
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }

        resetFilterState(document);
        syncToolbarFromCurrentDocument();
        renderRows(document, document.loadedRows);
    }

    /** Load and normalize the JSON file for one open document tab.
     *
     * Params:
     *   document = the document tab to load
     */
    loadDocument = (DocumentTab document, bool fitHorizontalSplitAfterLoad = true) {
        if (isLoading)
        {
            auto current = currentDocument();
            if (current !is null)
            {
                current.status.setText("A load is already in progress.");
            }
            return;
        }

        if (!exists(document.filePath))
        {
            document.status.setText(format("File not found: %s", document.filePath));
            document.tableStore.clear();
            document.tableNaturalWidth = -1;
            document.tableMinimumWidth = -1;
            document.fitHorizontalSplitAfterLoad = false;
            document.pendingColumnMeasurement = false;
            return;
        }

        auto requestId = ++document.loadRequestId;
        document.tableNaturalWidth = -1;
        document.tableMinimumWidth = -1;
        document.fitHorizontalSplitAfterLoad = fitHorizontalSplitAfterLoad;
        document.pendingColumnMeasurement = false;
        logLineVerbose("[load] start ", document.filePath,
            ", fitAfterLoad=", fitHorizontalSplitAfterLoad,
            ", verbose=", cli.argVerboseOutputs);
        setLoadingState(document, true, format("Loading %s ...", document.filePath));

        auto worker = new Thread({
            MonoTime started = MonoTime.currTime;
            AsyncLoadResult result;
            result.filePath = document.filePath;

            try
            {
                setLoadingPhase(document, requestId, "Loading scanner data via library ...");
                logLineVerbose("[load-worker] parsing ", document.filePath);
                auto blobs = deserializeDataClassJsonFile(document.filePath);
                result.dataVersion = DATA_CLASS_VERSION2;
                result.rootShape = "library";
                result.rootKeysSummary = "NamedBinaryBlob[]";

                setLoadingPhase(document, requestId, "Projecting rows for GUI ...");
                result.allRows = extractRowsFromBlobs(blobs);

                setLoadingPhase(document, requestId, "Computing duplicate groups ...");
                result.duplicateGroups = countDuplicateDigestGroups(result.allRows);
                logLineVerbose("[load-worker] done ", document.filePath,
                    ": rows=", result.allRows.length,
                    ", duplicateGroups=", result.duplicateGroups);
            }
            catch (Exception ex)
            {
                result.error = ex.msg;
                logLineVerbose("[load-worker] failed ", document.filePath, ": ", ex.msg);
            }

            result.elapsedMs = cast(long)(MonoTime.currTime - started).total!"msecs";

            new Idle({
                if (requestId != document.loadRequestId)
                {
                    return false;
                }

                if (result.error.length > 0)
                {
                    document.tableStore.clear();
                    document.loadedRows = [];
                    document.visibleRows = [];
                    document.loadedDataVersion = -1;
                    document.loadedRootShape = "-";
                    document.loadedRootKeysSummary = "-";
                    updateFileMetaStatus(document);
                    document.pendingLoadElapsedMs = -1;
                    document.pendingStatusSuffix = "";
                    clearSelectionDetails(document);
                    setLoadingState(document, false, format("Failed to parse JSON: %s", result
                    .error));
                    if (pendingStartupPaths.length > 0)
                    {
                        new Idle({ loadNextPendingStartupPath(); return false; });
                    }
                    return false;
                }

                document.loadedDuplicateGroups = result.duplicateGroups;
                document.loadedRows = result.allRows;
                document.loadedDataVersion = result.dataVersion;
                document.loadedRootShape = result.rootShape.length > 0 ? result.rootShape : "-";
                document.loadedRootKeysSummary = result.rootKeysSummary.length > 0 ? result.rootKeysSummary
                : "-";
                updateFileMetaStatus(document);
                document.pendingLoadElapsedMs = result.elapsedMs;
                document.lastLoadElapsedMs = result.elapsedMs;
                updatePerfStatus(document);

                if (prefAutoApplyFilter && (
                    document.filterQuery.length > 0 ||
                    document.filterVideo ||
                    document.filterAudio ||
                    document.filterImage ||
                    document.filterText ||
                    document.filterMediaNegated ||
                    document.filterFileType ||
                    document.filterArchive ||
                    document.filterTorrent
                    ))
                {
                    applyFilterForDocument(document);
                }
                else
                {
                    renderRows(document, document.loadedRows);
                }

                logLineVerbose("[load] queued render ", document.filePath,
                ": rows=", document.loadedRows.length,
                ", autoFilter=", prefAutoApplyFilter ? "yes" : "no");

                persistCurrentState(clearSavedWindowGeometryOnExit);
                if (pendingStartupPaths.length > 0 && !isLoading)
                {
                    new Idle({ loadNextPendingStartupPath(); return false; });
                }
                else if (cli.selfTestMode && pendingStartupPaths.length == 0 && !selfTestQuitScheduled)
                {
                    selfTestQuitScheduled = true;
                    logLine("[self-test] scheduling quit in ", cli.selfTestDelayMs, " ms");
                    selfTestQuitTimer = new Timeout(cli.selfTestDelayMs, {
                        logLine("[self-test] quitting after startup delay");
                        Main.quit();
                        return false;
                    });
                }
                return false;
            });
        });

        worker.start();
    };

    /** Cancel the currently active background request. */
    void cancelPendingLoad()
    {
        if (!isLoading || busyDocument is null)
        {
            auto document = currentDocument();
            if (document !is null)
            {
                document.status.setText("No load in progress.");
            }
            return;
        }

        ++busyDocument.loadRequestId;
        ++busyDocument.filterRequestId;
        ++busyDocument.renderRequestId;
        busyDocument.pendingLoadElapsedMs = -1;
        busyDocument.pendingStatusSuffix = "";
        setLoadingState(busyDocument, false, "Operation cancelled. Background result will be discarded.");
    }

    fileOpenMenuItem.addOnActivate((MenuItem _) {
        chooseAndLoadPath(
            window,
            FileOpenDialogCallbacks(
                () { return isLoading; },
                () { return currentDocument(); },
                (string filePath, bool selectTab) { return openDocumentFromPath(filePath, selectTab); },
                (DocumentTab document, bool selectTab) { loadDocument(document, selectTab); }
            )
        );
    });

    fileReloadMenuItem.addOnActivate((MenuItem _) {
        reloadCurrentDocument(DocumentActionCallbacks(
            () { return currentDocument(); },
            () { return notebook.getCurrentPage(); },
            () { return cast(int) documents.length; },
            (int pageIndex) { return documents[pageIndex]; },
            (int pageIndex) { notebook.removePage(pageIndex); },
            () { syncToolbarFromCurrentDocument(); },
            (bool clearGeometry) { persistCurrentState(clearGeometry); },
            () { return isLoading; },
            () { return busyDocument; },
            () { return clearSavedWindowGeometryOnExit; },
            (DocumentTab document, bool fitHorizontalSplitAfterLoad) { loadDocument(document, fitHorizontalSplitAfterLoad); }
        ));
    });

    fileCloseMenuItem.addOnActivate((MenuItem _) {
        closeCurrentDocument(DocumentActionCallbacks(
            () { return currentDocument(); },
            () { return notebook.getCurrentPage(); },
            () { return cast(int) documents.length; },
            (int pageIndex) { return documents[pageIndex]; },
            (int pageIndex) { notebook.removePage(pageIndex); documents = documents[0 .. pageIndex] ~ documents[pageIndex + 1 .. $]; },
            () { syncToolbarFromCurrentDocument(); },
            (bool clearGeometry) { persistCurrentState(clearGeometry); },
            () { return isLoading; },
            () { return busyDocument; },
            () { return clearSavedWindowGeometryOnExit; },
            (DocumentTab document, bool fitHorizontalSplitAfterLoad) { loadDocument(document, fitHorizontalSplitAfterLoad); }
        ));
    });

    fileCancelOperationMenuItem.addOnActivate((MenuItem _) { cancelPendingLoad(); });

    fileQuitMenuItem.addOnActivate((MenuItem _) {
        persistCurrentState(clearSavedWindowGeometryOnExit);
        Main.quit();
    });

    editApplyFilterMenuItem.addOnActivate((MenuItem _) { applyFilterFromEntry(); });

    editClearFilterMenuItem.addOnActivate((MenuItem _) {
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }
        resetFilterState(document);
        syncToolbarFromCurrentDocument();
        renderRows(document, document.loadedRows);
    });

    editPreferencesMenuItem.addOnActivate((MenuItem _) {
        showPreferencesDialog(
            window,
            prefAutoApplyFilter,
            prefCaseSensitiveFilter,
            prefDetailsBelow,
            prefRestoreOpenFiles,
            externalOpenProgram,
            clearSavedWindowGeometryOnExit,
            PreferencesDialogCallbacks(
                () { applyDetailsPanePreferenceToAll(); },
                (bool clearGeometry) { persistCurrentState(clearGeometry); },
                () { return currentDocument(); }
            )
        );
    });

    editResetMetricsMenuItem.addOnActivate((MenuItem _) {
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }
        resetPerfMetrics(document);
    });

    helpShortcutsMenuItem.addOnActivate((MenuItem _) { showShortcutsHelp(window); });
    helpAboutMenuItem.addOnActivate((MenuItem _) { showAbout(window); });

    attachMenuAccelerator(fileOpenMenuItem, 'o');
    attachMenuAccelerator(fileReloadMenuItem, 'r');
    attachMenuAccelerator(fileCloseMenuItem, 'w');
    attachMenuAccelerator(fileCancelOperationMenuItem, 'k');
    attachMenuAccelerator(fileQuitMenuItem, 'q');
    attachMenuAccelerator(editApplyFilterMenuItem, 'f');
    attachMenuAccelerator(editClearFilterMenuItem, 'l');
    attachMenuAccelerator(editPreferencesMenuItem, ',', GdkModifierType.CONTROL_MASK);
    attachMenuAccelerator(editResetMetricsMenuItem, 'm');

    // Apply persisted splitter orientation/position to any tabs created later.

    bindToolbarSignals(
        btnReload,
        btnRelayout,
        btnCancelLoad,
        btnApplyFilter,
        btnClearFilter,
        filterEntry,
        filterVideo,
        filterAudio,
        filterImage,
        filterText,
        filterMediaNot,
        filterFileType,
        filterArchive,
        filterTorrent,
        ToolbarBindingsCallbacks(
            () {
                reloadCurrentDocument(DocumentActionCallbacks(
                    () { return currentDocument(); },
                    () { return notebook.getCurrentPage(); },
                    () { return cast(int) documents.length; },
                    (int pageIndex) { return documents[pageIndex]; },
                    (int pageIndex) { notebook.removePage(pageIndex); documents = documents[0 .. pageIndex] ~ documents[pageIndex + 1 .. $]; },
                    () { syncToolbarFromCurrentDocument(); },
                    (bool clearGeometry) { persistCurrentState(clearGeometry); },
                    () { return isLoading; },
                    () { return busyDocument; },
                    () { return clearSavedWindowGeometryOnExit; },
                    (DocumentTab document, bool fitHorizontalSplitAfterLoad) { loadDocument(document, fitHorizontalSplitAfterLoad); }
                ));
            },
            () { relayoutCurrentDocument(); },
            () { cancelPendingLoad(); },
            () { applyFilterFromEntry(); },
            () { clearCurrentFilter(); }
        )
    );

    bindWindowLifecycleSignals(
        notebook,
        window,
        WindowLifecycleCallbacks(
            (bool clearGeometry) { persistCurrentState(clearGeometry); },
            () { return clearSavedWindowGeometryOnExit; },
            (int width, int height) {
                if (width >= MIN_VALID_WINDOW_WIDTH && height >= MIN_VALID_WINDOW_HEIGHT)
                {
                    lastKnownWindowWidth = width;
                    lastKnownWindowHeight = height;
                }
            },
            () { return allowRuntimeStatePersistence; },
            (bool value) { allowRuntimeStatePersistence = value; },
            () { return windowSizePersistTimer; },
            (Timeout value) { windowSizePersistTimer = value; }
        )
    );

    window.showAll();

    if (loadedState.hasWindowSize)
    {
        auto restoredWidth = loadedState.windowWidth;
        auto restoredHeight = loadedState.windowHeight;

        if (restoredWidth < 640)
        {
            restoredWidth = 640;
        }
        if (restoredHeight < 400)
        {
            restoredHeight = 400;
        }

        // Initial apply right after widgets are visible.
        new Idle({
            window.setDefaultSize(restoredWidth, restoredHeight);
            window.resize(restoredWidth, restoredHeight);
            lastKnownWindowWidth = restoredWidth;
            lastKnownWindowHeight = restoredHeight;
            return false;
        });

        // XFCE can apply its own first configure cycle after map; enforce once more.
        new Timeout(120, {
            window.setDefaultSize(restoredWidth, restoredHeight);
            window.resize(restoredWidth, restoredHeight);
            lastKnownWindowWidth = restoredWidth;
            lastKnownWindowHeight = restoredHeight;
            return false;
        });

        // Second delayed pass to win late WM adjustments.
        new Timeout(320, {
            window.setDefaultSize(restoredWidth, restoredHeight);
            window.resize(restoredWidth, restoredHeight);
            lastKnownWindowWidth = restoredWidth;
            lastKnownWindowHeight = restoredHeight;
            return false;
        });

        // Some WMs settle size after initial composition; enforce a final pass.
        new Timeout(700, {
            window.setDefaultSize(restoredWidth, restoredHeight);
            window.resize(restoredWidth, restoredHeight);
            lastKnownWindowWidth = restoredWidth;
            lastKnownWindowHeight = restoredHeight;
            return false;
        });

        // Final late pass to override very late WM/session adjustments.
        new Timeout(1500, {
            window.setDefaultSize(restoredWidth, restoredHeight);
            window.resize(restoredWidth, restoredHeight);
            lastKnownWindowWidth = restoredWidth;
            lastKnownWindowHeight = restoredHeight;
            allowRuntimeStatePersistence = true;
            persistCurrentState(clearSavedWindowGeometryOnExit);
            return false;
        });
    }
    else
    {
        allowRuntimeStatePersistence = true;
    }

    syncToolbarFromCurrentDocument();

    previewVideoProgressTimer = startPreviewProgressTimer(
        PreviewProgressCallbacks(
            () { return currentDocument(); },
            (DocumentTab document) { syncVideoPreviewPosition(document); },
            (DocumentTab document) { syncVideoTrackSelectors(document); },
            (DocumentTab document, bool playing) { syncVideoPlaybackButton(document, playing); }
        )
    );

    startStartupWorkflow(
        pendingStartupPaths,
        pendingStartupSelectIndex,
        prefRestoreOpenFiles,
        loadedState.openFilePaths,
        cli.jsonPaths,
        loadedState.activeTabIndex,
        cli.selfTestMode,
        selfTestQuitScheduled,
        cli.selfTestDelayMs,
        selfTestQuitTimer,
        () { loadNextPendingStartupPath(); },
        () { Main.quit(); }
    );

    Main.run();
    return 0;
}
