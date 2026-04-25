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
import gdk.Screen;
import glib.Idle;
import glib.Timeout;
import gobject.Value;
import gobject.Type : GType;
import gobject.ObjectG : ObjectG;
import gobject.ParamSpec : ParamSpec;
import gtk.Builder;
import gtk.AboutDialog;
import gtk.AccelGroup;
import gtk.Box;
import gtk.Button;
import gtk.AspectFrame;
import gtk.c.types : ButtonsType, DialogFlags, FileChooserAction, MessageType, Orientation, ResponseType;
import gtk.CheckButton;
import gtk.Clipboard;
import gtk.ComboBoxText;
import gtk.CssProvider;
import gtk.Dialog;
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
import gtk.MessageDialog;
import gtk.Notebook;
import gtk.Paned;
import gtk.ProgressBar;
import gtk.Range;
import gtk.Scale;
import gtk.ScrolledWindow;
import gtk.Separator;
import gtk.SeparatorMenuItem;
import gtk.Spinner;
import gtk.TextView;
import gtk.ToggleButton;
import gtk.TreeIter;
import gtk.TreeModelIF;
import gtk.TreeSelection;
import gtk.TreePath;
import gtk.StyleContext;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.Widget;
import gtk.Window;
import gtk.c.types : GtkAlign, GtkIconSize, GtkReliefStyle, GtkShadowType, GtkTreeViewColumnSizing, GTK_STYLE_PROVIDER_PRIORITY_APPLICATION;

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
import ui.documenttab : COL_CHECKSUM_SET, COL_FILE_SIZE, COL_FILE_SIZE_SORT, COL_FILE_TYPE, COL_HAS_ARCHIVE, COL_HAS_TORRENT, COL_INDEX, COL_INDEX_SORT, COL_MEDIA_INFO, DocumentTab, PreviewScaleMode, clampPreviewScaleMode;
import ui.detailswidgets : setDetailEntry,
    setMetadataStatusLabel, setMetadataDetails, setKnownFilesTable, setMediaPreview,
    refreshMediaPreview, syncVideoPreviewWindow, setVideoPreviewVolume, playVideoPreview,
    pauseVideoPreview, jumpVideoPreview, stopVideoPreview, syncVideoPreviewPosition,
    seekVideoPreview, syncVideoPlaybackButton, syncVideoTrackSelectors;
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

enum int MIN_VALID_WINDOW_WIDTH = 320;
enum int MIN_VALID_WINDOW_HEIGHT = 240;

private __gshared CssProvider applicationCssProvider;

/** Install application-scoped CSS classes used by the Builder and widget factory helpers. */
private void installApplicationCss()
{
    if (applicationCssProvider !is null)
    {
        return;
    }

    auto screen = Screen.getDefault();
    if (screen is null)
    {
        return;
    }

    auto provider = new CssProvider();
    provider.loadFromData(q"CSS
.digest-entry {
    font-family: Monospace;
    font-size: 10pt;
}

.document-status-label {
    padding-top: 2px;
    padding-bottom: 2px;
}

.preview-title {
    font-weight: 600;
}

.preview-summary {
    font-size: 0.95em;
}
CSS");

    StyleContext.addProviderForScreen(screen, provider, GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    applicationCssProvider = provider;
}

/** Summarize checksum availability for the list view. */
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

/** Render a compact status icon for boolean table cells. */
string boolStatusIcon(bool value)
{
    return value ? "✓" : "○";
}

/** Summarize media subtype flags for the list view. */
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

/** Estimate the natural width required for the blob table columns. */
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

/** Estimate or return the cached natural width of the blob table. */
int naturalListWidth(DocumentTab document)
{
    return document.tableNaturalWidth > 0 ? document.tableNaturalWidth
        : measureTableColumnsWidth(document);
}

/** Estimate or return the cached minimum width that keeps the first two columns visible. */
int minimumListWidth(DocumentTab document)
{
    return document.tableMinimumWidth > 0 ? document.tableMinimumWidth
        : measureTableColumnsWidth(document, 2);
}

/** Measure the table columns once and freeze them at their natural widths. */
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

/** Measure table widths after GTK has finished laying out the current model. */
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
 *   rows = array of BlobRow to count media subtype hits
 * Returns:
 *   formatted string with counts of each media subtype
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
 *   digest = base64-encoded digest string
 * Returns:
 *   lowercase hexadecimal representation of the digest, or an error placeholder if the input is invalid
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

/** Retrieve a typed object from a GtkBuilder layout.
 *
 * Params:
 *   builder = builder instance owning the object
 *   builderLabel = short context label for diagnostics
 *   objectName = exact object id to resolve
 * Returns:
 *   the requested widget cast to the expected type
 */
private T builderObject(T)(Builder builder, string builderLabel, string objectName)
{
    logLineVerbose("[ui] builder lookup start ", builderLabel, ".", objectName);
    auto object = builder.getObject(objectName);
    if (object is null)
    {
        auto objectCount = builder.getObjects().length;
        logLine("[ui] missing GtkBuilder object ", builderLabel, ".", objectName,
            " (objects=", objectCount, ")");
        throw new Exception(format("Missing GtkBuilder object: %s.%s", builderLabel, objectName));
    }

    logLineVerbose("[ui] builder lookup ok ", builderLabel, ".", objectName);

    return cast(T) object;
}

/** Retrieve a typed object from a GtkBuilder layout, or return null if missing. */
private T builderObjectOrNull(T)(Builder builder, string builderLabel, string objectName)
{
    logLineVerbose("[ui] builder lookup start ", builderLabel, ".", objectName);
    auto object = builder.getObject(objectName);
    if (object is null)
    {
        logLine("[ui] missing GtkBuilder object ", builderLabel, ".", objectName,
            " (objects=", builder.getObjects().length, ")");
        return null;
    }

    logLineVerbose("[ui] builder lookup ok ", builderLabel, ".", objectName);
    return cast(T) object;
}

/** Program entry point.
 *
 * Params:
 *   args = process command-line arguments
 * Returns:
 *   exit code
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
    auto menuBarSlot = builderObject!Box(mainBuilder, "main", "menuBarSlot");
    auto content = builderObject!Box(mainBuilder, "main", "content");
    auto separator = builderObject!Separator(mainBuilder, "main", "separator");
    auto toolbar = builderObject!Box(mainBuilder, "main", "toolbar");
    auto btnReload = builderObject!Button(mainBuilder, "main", "btnReload");
    auto btnRelayout = builderObject!Button(mainBuilder, "main", "btnRelayout");
    auto btnCancelLoad = builderObject!Button(mainBuilder, "main", "btnCancelLoad");
    auto loadSpinner = builderObject!Spinner(mainBuilder, "main", "loadSpinner");
    auto filterEntry = builderObject!Entry(mainBuilder, "main", "filterEntry");
    auto filterMediaNot = builderObject!CheckButton(mainBuilder, "main", "filterMediaNot");
    auto filterVideo = builderObject!CheckButton(mainBuilder, "main", "filterVideo");
    auto filterAudio = builderObject!CheckButton(mainBuilder, "main", "filterAudio");
    auto filterImage = builderObject!CheckButton(mainBuilder, "main", "filterImage");
    auto filterText = builderObject!CheckButton(mainBuilder, "main", "filterText");
    auto filterFileType = builderObject!CheckButton(mainBuilder, "main", "filterFileType");
    auto filterArchive = builderObject!CheckButton(mainBuilder, "main", "filterArchive");
    auto filterTorrent = builderObject!CheckButton(mainBuilder, "main", "filterTorrent");
    auto btnApplyFilter = builderObject!Button(mainBuilder, "main", "btnApplyFilter");
    auto btnClearFilter = builderObject!Button(mainBuilder, "main", "btnClearFilter");
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

    auto menuBar = new MenuBar();

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

    /** Render a compact summary for media flags in the details form. */
    string mediaInfoStatusSummary(const(BlobRow) row)
    {
        if (!row.hasMedia)
        {
            return format("%s none", boolStatusIcon(false));
        }
        return format(
            "%s present | V %s  A %s  I %s  T %s",
            boolStatusIcon(true),
            boolStatusIcon(row.hasVideo),
            boolStatusIcon(row.hasAudio),
            boolStatusIcon(row.hasImage),
            boolStatusIcon(row.hasText)
        );
    }

    /** Render a compact summary for checksum availability in the details form. */
    string checksumStatusSummary(const(BlobRow) row)
    {
        return format(
            "MD5 %s  SHA1 %s  xxh64 %s",
            boolStatusIcon(row.md5.length > 0),
            boolStatusIcon(row.sha1.length > 0),
            boolStatusIcon(row.xxh64.length > 0)
        );
    }

    /** Render a compact summary for boolean metadata blocks in the details form. */
    string metadataPresenceSummary(bool value)
    {
        return value ? format("%s present", boolStatusIcon(true)) : format("%s none", boolStatusIcon(
                false));
    }

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
        btnCancelLoad.setSensitive(isLoading);
        filterEntry.setSensitive(!isLoading && hasCurrentDocument);
        filterVideo.setSensitive(!isLoading && hasCurrentDocument);
        filterAudio.setSensitive(!isLoading && hasCurrentDocument);
        filterImage.setSensitive(!isLoading && hasCurrentDocument);
        filterText.setSensitive(!isLoading && hasCurrentDocument);
        filterMediaNot.setSensitive(!isLoading && hasCurrentDocument);
        filterFileType.setSensitive(!isLoading && hasCurrentDocument);
        filterArchive.setSensitive(!isLoading && hasCurrentDocument);
        filterTorrent.setSensitive(!isLoading && hasCurrentDocument);
        btnApplyFilter.setSensitive(!isLoading && hasCurrentDocument);
        btnClearFilter.setSensitive(!isLoading && hasCurrentDocument);
    }

    /** Mirror the active tab's path and filter settings back into the shared toolbar. */
    void syncToolbarFromCurrentDocument()
    {
        isSyncingToolbarState = true;
        auto document = currentDocument();
        if (document is null)
        {
            filterEntry.setText("");
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

    /** Refresh the performance summary label for a document tab. */
    void updatePerfStatus(DocumentTab document)
    {
        document.perfStatus.setText(format(
                "Timings: load=%s ms | filter=%s ms | render=%s ms",
                formatTimingValue(document.lastLoadElapsedMs),
                formatTimingValue(document.lastFilterElapsedMs),
                formatTimingValue(document.lastRenderElapsedMs)
        ));
    }

    /** Refresh the metadata status label for a document tab. */
    void updateFileMetaStatus(DocumentTab document)
    {
        auto dataVersionText = document.loadedDataVersion >= 0 ? to!string(
            document.loadedDataVersion) : "-";
        document.fileMetaStatus.setText(format(
                "File metadata: version=%s | root=%s | keys=%s",
                dataVersionText,
                document.loadedRootShape,
                document.loadedRootKeysSummary
        ));
    }

    /** Publish a global busy state while a tab-specific worker is active. */
    void setLoadingState(DocumentTab document, bool loading, string message = "")
    {
        isLoading = loading;
        busyDocument = loading ? document : null;
        syncToolbarSensitivity();

        // Spalten bleiben nicht-resizable, damit die gemessenen Breiten stabil bleiben.
        setTableColumnsResizable(document, false);

        if (loading)
        {
            loadSpinner.setVisible(true);
            loadSpinner.start();
            progressBar.setVisible(true);
            auto loadingText = message.length > 0 ? message : "Loading...";
            progressBar.setText(loadingText);
            progressBar.pulse();
            if (progressPulseTimer is null)
            {
                progressPulseTimer = new Timeout(120, {
                    if (!isLoading)
                    {
                        return false;
                    }
                    progressBar.pulse();
                    return true;
                });
            }
            if (document !is null)
            {
                document.status.setText(loadingText);
                document.btnCopySha1.setSensitive(false);
                document.btnCopyFile.setSensitive(false);
                document.btnCopyDetails.setSensitive(false);
            }
            return;
        }

        loadSpinner.stop();
        loadSpinner.setVisible(false);
        if (progressPulseTimer !is null)
        {
            progressPulseTimer.stop();
            progressPulseTimer = null;
        }
        progressBar.setVisible(false);
        progressBar.setFraction(0.0);
        progressBar.setText("Idle");

        if (document !is null)
        {
            document.btnCopySha1.setSensitive(document.selectedSha1.length > 0);
            document.btnCopyFile.setSensitive(document.selectedFileName.length > 0);
            document.btnCopyDetails.setSensitive(document.selectedDetailsText.length > 0);
            if (message.length > 0)
            {
                document.status.setText(message);
            }
        }
    }

    /** Publish a load phase update onto the GTK main loop for a single document tab. */
    void setLoadingPhase(DocumentTab document, ulong expectedRequestId, string phaseText)
    {
        new Idle({
            if (!isLoading || busyDocument !is document || expectedRequestId != document
            .loadRequestId)
            {
                return false;
            }

            document.status.setText(phaseText);
            progressBar.setText(phaseText);
            return false;
        });
    }

    /** Clear collected performance timings for the active document tab. */
    void resetPerfMetrics()
    {
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }
        document.lastLoadElapsedMs = -1;
        document.lastFilterElapsedMs = -1;
        document.lastRenderElapsedMs = -1;
        updatePerfStatus(document);
        document.status.setText("Performance metrics reset.");
    }

    /** Reset selection-dependent detail fields to the empty placeholder state. */
    void clearSelectionDetails(DocumentTab document)
    {
        document.selectedSha1 = "";
        document.selectedFileName = "";
        document.selectedDetailsText = "";
        document.selectedPreviewPath = "";
        document.selectedPreviewIsImage = false;
        document.selectedPreviewIsVideo = false;
        document.selectedPreviewCandidatePath = "";
        document.selectedPreviewCandidateExists = false;
        document.selectedPreviewSourcePath = "";
        document.selectedPreviewSourcePixbuf = null;
        setDetailEntry(document.detailSha1HexEntry, "");
        setDetailEntry(document.detailMd5HexEntry, "");
        setDetailEntry(document.detailXxh64HexEntry, "");
        setDetailEntry(document.detailIndexEntry, "");
        setDetailEntry(document.detailSizeEntry, "");
        setMetadataStatusLabel(document.detailChecksumStatus, "Checksums", checksumStatusSummary(
                BlobRow.init));
        document.detailChecksumExpander.setSensitive(false);
        document.detailChecksumExpander.setExpanded(false);
        setMetadataStatusLabel(document.detailMediaInfoStatus, "MediaInfo", format("%s unavailable", boolStatusIcon(
                false)));
        setMetadataStatusLabel(document.detailFileTypeStatus, "File Type", format("%s unavailable", boolStatusIcon(
                false)));
        setMetadataStatusLabel(document.detailArchiveStatus, "Archive", format("%s unavailable", boolStatusIcon(
                false)));
        setMetadataStatusLabel(document.detailTorrentStatus, "Torrent", format("%s unavailable", boolStatusIcon(
                false)));
        setMetadataDetails(document.detailMediaInfoExpander, document.detailMediaInfoView, "MediaInfo", "");
        setMetadataDetails(document.detailFileTypeExpander, document.detailFileTypeView, "File Type", "");
        setMetadataDetails(document.detailArchiveExpander, document.detailArchiveView, "Archive", "");
        setMetadataDetails(document.detailTorrentExpander, document.detailTorrentView, "Torrent", "");
        setKnownFilesTable(document, BlobRow.init);
        if (document.detailPreviewImage !is null)
        {
            document.detailPreviewImage.clear();
        }
        stopVideoPreview(document);
        if (document.detailPreviewVideoFrame !is null)
        {
            document.detailPreviewVideoFrame.setVisible(false);
        }
        if (document.detailPreviewVideoControls !is null)
        {
            document.detailPreviewVideoControls.setVisible(false);
        }
        if (document.detailPreviewSummary !is null)
        {
            document.detailPreviewSummary.setText("No preview available.");
        }
        document.btnCopySha1.setSensitive(false);
        document.btnCopyFile.setSensitive(false);
        document.btnCopyDetails.setSensitive(false);
        document.rowDetails.setText("Selection: none");
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

        auto previewBuilder = new Builder();
        logLineVerbose("[ui] loading preview builder for ", filePath);
        previewBuilder.addFromString(import("source/ui/detailpreview.ui"));
        document.previewBuilder = previewBuilder;
        logLineVerbose("[ui] preview builder loaded, objects=", previewBuilder.getObjects().length);

        auto previewPane = builderObject!Box(previewBuilder, "preview", "previewPane");
        document.detailPreviewTitle = builderObject!Label(previewBuilder, "preview", "detailPreviewTitle");
        document.detailPreviewSummary = builderObject!Label(previewBuilder, "preview", "detailPreviewSummary");
        document.detailPreviewImageControls = builderObject!Box(previewBuilder, "preview", "previewControls");
        document.detailPreviewScroll = builderObject!ScrolledWindow(previewBuilder, "preview", "detailPreviewScroll");
        document.detailPreviewImage = builderObject!Image(previewBuilder, "preview", "detailPreviewImage");
        document.detailPreviewVideoFrame = builderObject!AspectFrame(previewBuilder, "preview", "detailPreviewVideoFrame");
        document.detailPreviewVideoArea = builderObject!DrawingArea(previewBuilder, "preview", "detailPreviewVideoArea");
        document.detailPreviewVideoControls = builderObject!Box(previewBuilder, "preview", "detailPreviewVideoControls");
        document.detailPreviewVideoArea.setDoubleBuffered(false);

        document.detailPreviewAutostartButton = builderObject!CheckButton(previewBuilder, "preview", "detailPreviewAutostartButton");
        document.detailPreviewJumpBackButton = builderObject!Button(previewBuilder, "preview", "detailPreviewJumpBackButton");
        document.detailPreviewPlayButton = builderObject!Button(previewBuilder, "preview", "detailPreviewPlayButton");
        document.detailPreviewJumpForwardButton = builderObject!Button(previewBuilder, "preview", "detailPreviewJumpForwardButton");
        document.detailPreviewPositionLabel = builderObject!Label(previewBuilder, "preview", "detailPreviewPositionLabel");
        document.detailPreviewPositionScale = builderObject!Scale(previewBuilder, "preview", "detailPreviewPositionScale");
        document.detailPreviewVolumeScale = builderObject!Scale(previewBuilder, "preview", "detailPreviewVolumeScale");
        document.detailPreviewTrackSelectorsRow = builderObject!Box(previewBuilder, "preview", "previewTrackSelectorsRow");
        document.detailPreviewVideoTrackBox = builderObject!Box(previewBuilder, "preview", "detailPreviewVideoTrackBox");
        document.detailPreviewAudioTrackBox = builderObject!Box(previewBuilder, "preview", "detailPreviewAudioTrackBox");
        document.detailPreviewSubtitleTrackBox = builderObject!Box(previewBuilder, "preview", "detailPreviewSubtitleTrackBox");
        document.detailPreviewVideoTrackCombo = builderObject!ComboBoxText(previewBuilder, "preview", "detailPreviewVideoTrackCombo");
        document.detailPreviewAudioTrackCombo = builderObject!ComboBoxText(previewBuilder, "preview", "detailPreviewAudioTrackCombo");
        document.detailPreviewSubtitleTrackCombo = builderObject!ComboBoxText(previewBuilder, "preview", "detailPreviewSubtitleTrackCombo");
        document.detailPreviewContainButton = builderObject!ToggleButton(previewBuilder, "preview", "detailPreviewContainButton");
        document.detailPreviewFitWidthButton = builderObject!ToggleButton(previewBuilder, "preview", "detailPreviewFitWidthButton");
        document.detailPreviewFitHeightButton = builderObject!ToggleButton(previewBuilder, "preview", "detailPreviewFitHeightButton");
        document.detailPreviewCenterButton = builderObject!ToggleButton(previewBuilder, "preview", "detailPreviewCenterButton");
        document.detailPreviewCoverButton = builderObject!ToggleButton(previewBuilder, "preview", "detailPreviewCoverButton");

        auto detailBuilder = new Builder();
        logLineVerbose("[ui] loading detail builder for ", filePath);
        detailBuilder.addFromString(import("source/ui/detailpane.ui"));
        document.detailBuilder = detailBuilder;
        logLineVerbose("[ui] detail builder loaded, objects=", detailBuilder.getObjects().length);

        auto pageBuilder = new Builder();
        logLineVerbose("[ui] loading page builder for ", filePath);
        pageBuilder.addFromString(import("source/ui/documentpage.ui"));
        document.pageBuilder = pageBuilder;
        logLineVerbose("[ui] page builder loaded, objects=", pageBuilder.getObjects().length);

        auto pageRoot = builderObject!Box(pageBuilder, "page", "pageRoot");
        auto splitSlot = builderObject!Box(pageBuilder, "page", "splitSlot");
        document.rowDetails = builderObject!Label(pageBuilder, "page", "rowDetails");
        document.status = builderObject!Label(pageBuilder, "page", "status");
        document.perfStatus = builderObject!Label(pageBuilder, "page", "perfStatus");
        document.fileMetaStatus = builderObject!Label(pageBuilder, "page", "fileMetaStatus");

        auto detailsPane = builderObject!Box(detailBuilder, "detail", "detailsPane");
        auto detailsActions = builderObject!Box(detailBuilder, "detail", "detailsActions");
        auto detailsContent = builderObject!Paned(detailBuilder, "detail", "detailsContent");
        auto detailsBody = builderObject!Box(detailBuilder, "detail", "detailsBody");
        auto detailVisuals = builderObject!Box(detailBuilder, "detail", "detailVisuals");
        auto detailGrid = builderObject!Grid(detailBuilder, "detail", "detailGrid");
        document.detailFileNamesLabel = builderObject!Label(detailBuilder, "detail", "detailFileNamesLabel");
        auto detailsScroll = builderObject!ScrolledWindow(detailBuilder, "detail", "detailsScroll");
        auto previewSlot = builderObject!Box(detailBuilder, "detail", "previewSlot");

        document.btnCopySha1 = builderObject!Button(detailBuilder, "detail", "btnCopySha1");
        document.btnCopyFile = builderObject!Button(detailBuilder, "detail", "btnCopyFile");
        document.btnCopyDetails = builderObject!Button(detailBuilder, "detail", "btnCopyDetails");

        document.detailPreviewAutostartButton.setActive(document.previewVideoAutostart);
        document.detailPreviewAutostartButton.addOnToggled((ToggleButton button) {
            if (isSyncingToolbarState)
            {
                return;
            }

            document.previewVideoAutostart = button.getActive();
            previewVideoAutostart = document.previewVideoAutostart;

            if (!document.selectedPreviewIsVideo)
            {
                return;
            }

            if (document.previewVideoAutostart)
            {
                playVideoPreview(document);
            }
            else
            {
                pauseVideoPreview(document);
            }
        });
        document.detailPreviewJumpBackButton.addOnClicked((Button _) {
            jumpVideoPreview(document, -10);
        });

        document.detailPreviewPlayButton.addOnClicked((Button _) {
            if (document.previewVideoPlayer is null)
            {
                playVideoPreview(document);
                return;
            }

            GstState state;
            GstState pending;
            auto stateResult = document.previewVideoPlayer.getState(state, pending, 0);
            if (stateResult == GstStateChangeReturn.FAILURE || state == GstState.NULL)
            {
                playVideoPreview(document);
                return;
            }

            if (state == GstState.PLAYING)
            {
                pauseVideoPreview(document);
            }
            else
            {
                playVideoPreview(document);
            }
        });

        document.detailPreviewJumpForwardButton.addOnClicked((Button _) {
            jumpVideoPreview(document, 10);
        });

        document.detailPreviewVideoTrackCombo.addOnChanged((ComboBoxText combo) {
            if (isSyncingToolbarState || document.previewVideoTrackSyncing || document.previewVideoPlayer is null)
            {
                return;
            }

            auto active = combo.getActive();
            if (active >= 0)
            {
                document.previewVideoPlayer.setProperty("current-video", new Value(active));
            }
        });
        document.detailPreviewAudioTrackCombo.addOnChanged((ComboBoxText combo) {
            if (isSyncingToolbarState || document.previewVideoTrackSyncing || document.previewVideoPlayer is null)
            {
                return;
            }

            auto active = combo.getActive();
            if (active >= 0)
            {
                document.previewVideoPlayer.setProperty("current-audio", new Value(active));
            }
        });
        document.detailPreviewSubtitleTrackCombo.addOnChanged((ComboBoxText combo) {
            if (isSyncingToolbarState || document.previewVideoTrackSyncing || document.previewVideoPlayer is null)
            {
                return;
            }

            auto active = combo.getActive();
            if (active >= 0)
            {
                document.previewVideoPlayer.setProperty("current-text", new Value(active - 1));
            }
        });

        document.detailPreviewPositionScale.addOnValueChanged((Range range) {
            if (isSyncingToolbarState || document.previewVideoPositionSyncing)
            {
                return;
            }

            if (!seekVideoPreview(document, range.getValue()))
            {
                return;
            }

            syncVideoPreviewPosition(document);
        });

        document.detailPreviewVolumeScale.setValue(document.previewVideoVolume);
        document.detailPreviewVolumeScale.addOnValueChanged((Range range) {
            if (isSyncingToolbarState)
            {
                return;
            }

            setVideoPreviewVolume(document, range.getValue());
            previewVideoVolume = document.previewVideoVolume;
        });

        document.detailPreviewScroll.addOnSizeAllocate((allocation, Widget _) {
            if (document.selectedPreviewPath.length == 0 || !document.selectedPreviewIsImage)
            {
                return;
            }
            refreshMediaPreview(document);
        });

        document.detailPreviewVideoArea.addOnRealize((Widget _) {
            syncVideoPreviewWindow(document);
            if (document.selectedPreviewIsVideo)
            {
                refreshMediaPreview(document);
            }
        });

        document.detailPreviewVideoArea.addOnSizeAllocate((allocation, Widget _) {
            if (document.selectedPreviewIsVideo)
            {
                syncVideoPreviewWindow(document, allocation.width, allocation.height);
            }
        });

        document.detailPreviewContainButton.addOnToggled((ToggleButton button) {
            if (isSyncingToolbarState || !button.getActive())
            {
                return;
            }
            setPreviewScaleMode(PreviewScaleMode.contain);
            syncPreviewToolbarFromCurrentDocument();
        });
        document.detailPreviewFitWidthButton.addOnToggled((ToggleButton button) {
            if (isSyncingToolbarState || !button.getActive())
            {
                return;
            }
            setPreviewScaleMode(PreviewScaleMode.fitWidth);
            syncPreviewToolbarFromCurrentDocument();
        });
        document.detailPreviewFitHeightButton.addOnToggled((ToggleButton button) {
            if (isSyncingToolbarState || !button.getActive())
            {
                return;
            }
            setPreviewScaleMode(PreviewScaleMode.fitHeight);
            syncPreviewToolbarFromCurrentDocument();
        });
        document.detailPreviewCenterButton.addOnToggled((ToggleButton button) {
            if (isSyncingToolbarState || !button.getActive())
            {
                return;
            }
            setPreviewScaleMode(PreviewScaleMode.center);
            syncPreviewToolbarFromCurrentDocument();
        });
        document.detailPreviewCoverButton.addOnToggled((ToggleButton button) {
            if (isSyncingToolbarState || !button.getActive())
            {
                return;
            }
            setPreviewScaleMode(PreviewScaleMode.cover);
            syncPreviewToolbarFromCurrentDocument();
        });

        syncPreviewToolbarFromDocument(document);

        document.detailChecksumExpander = builderObject!Expander(detailBuilder, "detail", "detailChecksumExpander");
        document.detailChecksumStatus = builderObject!Label(detailBuilder, "detail", "detailChecksumStatus");
        document.detailMediaInfoExpander = builderObject!Expander(detailBuilder, "detail", "detailMediaInfoExpander");
        document.detailMediaInfoStatus = builderObject!Label(detailBuilder, "detail", "detailMediaInfoStatus");
        document.detailMediaInfoView = builderObject!TextView(detailBuilder, "detail", "detailMediaInfoView");
        document.detailFileTypeExpander = builderObject!Expander(detailBuilder, "detail", "detailFileTypeExpander");
        document.detailFileTypeStatus = builderObject!Label(detailBuilder, "detail", "detailFileTypeStatus");
        document.detailFileTypeView = builderObject!TextView(detailBuilder, "detail", "detailFileTypeView");
        document.detailArchiveExpander = builderObject!Expander(detailBuilder, "detail", "detailArchiveExpander");
        document.detailArchiveStatus = builderObject!Label(detailBuilder, "detail", "detailArchiveStatus");
        document.detailArchiveView = builderObject!TextView(detailBuilder, "detail", "detailArchiveView");
        document.detailTorrentExpander = builderObject!Expander(detailBuilder, "detail", "detailTorrentExpander");
        document.detailTorrentStatus = builderObject!Label(detailBuilder, "detail", "detailTorrentStatus");
        document.detailTorrentView = builderObject!TextView(detailBuilder, "detail", "detailTorrentView");
        document.detailIndexEntry = builderObject!Entry(detailBuilder, "detail", "detailIndexEntry");
        document.detailSizeEntry = builderObject!Entry(detailBuilder, "detail", "detailSizeEntry");
        document.detailSha1HexEntry = builderObject!Entry(detailBuilder, "detail", "detailSha1HexEntry");
        document.detailMd5HexEntry = builderObject!Entry(detailBuilder, "detail", "detailMd5HexEntry");
        document.detailXxh64HexEntry = builderObject!Entry(detailBuilder, "detail", "detailXxh64HexEntry");

        document.detailFileNamesStore = new ListStore([
            GType.STRING, GType.STRING
        ]);
        document.detailFileNamesView = new TreeView(document.detailFileNamesStore);
        configureKnownFilesColumns(document.detailFileNamesView);
        document.detailFileNamesView.addOnRowActivated((TreePath path, TreeViewColumn column, TreeView treeView) {
            TreeModelIF model;
            TreeIter iter;
            auto selection = document.detailFileNamesView.getSelection();
            if (!selection.getSelected(model, iter))
            {
                return;
            }

            auto knownFileName = model.getValueString(iter, 0);
            if (knownFileName.length == 0)
            {
                return;
            }

            openKnownFileExternally(document, knownFileName);
        });

        logLineVerbose("[ui] populating known-files scroll for ", filePath);
        detailsScroll.add(document.detailFileNamesView);
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

        document.btnCopySha1.addOnClicked((Button _) {
            copyTextToClipboard("SHA1", document.selectedSha1, document);
        });
        document.btnCopyFile.addOnClicked((Button _) {
            copyTextToClipboard("file name", document.selectedFileName, document);
        });
        document.btnCopyDetails.addOnClicked((Button _) {
            copyTextToClipboard("details", document.selectedDetailsText, document);
        });
        document.tableView.getSelection().addOnChanged((TreeSelection _) {
            updateSelectedRowDetails(document);
        });

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
        state.previewVideoVolume = previewVideoVolume;
        state.splitPositionPreview = splitPositionPreview;
        state.hasSplitPositionPreview = splitPositionPreview > 0;

        auto document = currentDocument();
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

            if (cli.selfTestMode && !selfTestQuitScheduled)
            {
                selfTestQuitScheduled = true;
                logLine("[self-test] scheduling quit in ", cli.selfTestDelayMs, " ms");
                selfTestQuitTimer = new Timeout(cli.selfTestDelayMs, {
                    logLine("[self-test] quitting after startup delay");
                    Main.quit();
                    return false;
                });
            }
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

    /** Open a file chooser and create or select the corresponding document tab. */
    void chooseAndLoadPath()
    {
        if (isLoading)
        {
            auto document = currentDocument();
            if (document !is null)
            {
                document.status.setText("A load is already in progress.");
            }
            return;
        }

        auto chooser = new FileChooserDialog(
            "Open JSON",
            window,
            FileChooserAction.OPEN,
            ["_Cancel", "_Open"],
            [ResponseType.CANCEL, ResponseType.ACCEPT]
        );

        // pathEntry entfernt

        auto response = chooser.run();
        if (response == cast(int) ResponseType.ACCEPT)
        {
            auto selectedPath = chooser.getFilename();
            if (selectedPath.length > 0)
            {
                auto document = openDocumentFromPath(selectedPath, true);
                if (document.loadedRows.length == 0)
                {
                    loadDocument(document, true);
                }
            }
        }

        chooser.destroy();
    }

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

    /** Reload the currently selected document tab from disk. */
    void reloadCurrentDocument()
    {
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }
        logLineVerbose("[reload] ", document.filePath, ", split=", splitPositionHorizontal);
        loadDocument(document, false);
    }

    /** Close the currently selected document tab and persist the remaining open set. */
    void closeCurrentDocument()
    {
        auto pageIndex = notebook.getCurrentPage();
        if (pageIndex < 0 || pageIndex >= documents.length)
        {
            return;
        }
        auto document = documents[pageIndex];
        if (isLoading && busyDocument is document)
        {
            document.status.setText("Cannot close a tab while it is loading.");
            return;
        }

        notebook.removePage(pageIndex);
        documents = documents[0 .. pageIndex] ~ documents[pageIndex + 1 .. $];
        syncToolbarFromCurrentDocument();
        persistCurrentState(clearSavedWindowGeometryOnExit);
    }

    // Apply persisted splitter orientation/position to any tabs created later.

    /** Show and apply user preferences that affect filtering and layout. */
    void showPreferencesDialog()
    {
        auto dialog = new Dialog(
            "Preferences",
            window,
            DialogFlags.MODAL,
            ["_Cancel", "_Save"],
            [ResponseType.CANCEL, ResponseType.OK]
        );

        auto contentArea = dialog.getContentArea();
        auto prefsBox = new Box(Orientation.VERTICAL, 8);
        prefsBox.setBorderWidth(8);

        auto optAutoApply = new CheckButton("Auto-apply filter after load/reload");
        optAutoApply.setActive(prefAutoApplyFilter);

        auto optCaseSensitive = new CheckButton("Case-sensitive text filtering");
        optCaseSensitive.setActive(prefCaseSensitiveFilter);

        auto optDetailsBelow = new CheckButton("Show details below list (instead of on the right)");
        optDetailsBelow.setActive(prefDetailsBelow);

        auto optRestoreOpenFiles = new CheckButton("Reopen previously open data files on startup");
        optRestoreOpenFiles.setActive(prefRestoreOpenFiles);

        auto lblExternalOpenProgram = new Label("External opener program");
        lblExternalOpenProgram.setXalign(0.0f);
        auto entryExternalOpenProgram = new Entry();
        entryExternalOpenProgram.setText(externalOpenProgram);
        entryExternalOpenProgram.setPlaceholderText("xdg-open");

        auto optClearWindowGeometry = new CheckButton("Delete saved window positions on save");
        optClearWindowGeometry.setActive(false);

        prefsBox.packStart(optAutoApply, false, false, 0);
        prefsBox.packStart(optCaseSensitive, false, false, 0);
        prefsBox.packStart(optDetailsBelow, false, false, 0);
        prefsBox.packStart(optRestoreOpenFiles, false, false, 0);
        prefsBox.packStart(lblExternalOpenProgram, false, false, 0);
        prefsBox.packStart(entryExternalOpenProgram, false, false, 0);
        prefsBox.packStart(optClearWindowGeometry, false, false, 0);
        contentArea.packStart(prefsBox, true, true, 0);

        dialog.showAll();
        auto response = dialog.run();

        if (response == cast(int) ResponseType.OK)
        {
            prefAutoApplyFilter = optAutoApply.getActive();
            prefCaseSensitiveFilter = optCaseSensitive.getActive();
            prefRestoreOpenFiles = optRestoreOpenFiles.getActive();
            auto oldDetailsBelow = prefDetailsBelow;
            prefDetailsBelow = optDetailsBelow.getActive();
            if (prefDetailsBelow != oldDetailsBelow)
            {
                applyDetailsPanePreferenceToAll();
            }
            auto newExternalOpenProgram = entryExternalOpenProgram.getText();
            externalOpenProgram = newExternalOpenProgram.length > 0 ? newExternalOpenProgram : "xdg-open";
            auto clearGeometry = optClearWindowGeometry.getActive();
            clearSavedWindowGeometryOnExit = clearGeometry;
            persistCurrentState(clearGeometry);
            auto document = currentDocument();
            if (document !is null)
            {
                document.status.setText(clearGeometry ? "Preferences saved. Stored window positions were deleted."
                        : "Preferences saved.");
            }
        }

        dialog.destroy();
    }

    /** Show the keyboard shortcut overview dialog. */
    void showShortcutsHelp()
    {
        auto dialog = new MessageDialog(
            window,
            DialogFlags.MODAL,
            MessageType.INFO,
            ButtonsType.CLOSE,
            "Keyboard Shortcuts\n\n" ~
                "Ctrl+O  Open JSON\n" ~
                "Ctrl+W  Close Current Tab\n" ~
                "Ctrl+R  Reload\n" ~
                "Ctrl+K  Cancel Current Operation\n" ~
                "Ctrl+F  Apply Filter\n" ~
                "Ctrl+L  Clear Filter\n" ~
                "Ctrl+,  Preferences\n" ~
                "Ctrl+Q  Quit"
        );
        dialog.run();
        dialog.destroy();
    }

    /** Show the About dialog for the desktop frontend. */
    void showAbout()
    {
        auto dialog = new AboutDialog();
        dialog.setTransientFor(window);
        dialog.setModal(true);
        dialog.setLogoIconName("help-about");
        dialog.setProgramName("DosierSkanilo GUI");
        dialog.setVersion("0.1.0");
        dialog.setComments("Desktop frontend for DosierSkanilo.");
        dialog.setAuthors(["Carsten Schlote"]);
        dialog.run();
        dialog.destroy();
    }

    auto fileMenuItem = new MenuItem("_File");
    auto fileMenu = new Menu();
    fileMenuItem.setSubmenu(fileMenu);

    auto fileOpen = new MenuItem((MenuItem _) { chooseAndLoadPath(); }, "_Open JSON", "file.open", true, accelGroup, 'o');

    auto fileReload = new MenuItem((MenuItem _) { reloadCurrentDocument(); }, "_Reload", "file.reload", true, accelGroup, 'r');

    auto fileClose = new MenuItem((MenuItem _) { closeCurrentDocument(); }, "_Close Current Tab", "file.close", true, accelGroup, 'w');

    auto fileCancelOperation = new MenuItem((MenuItem _) { cancelPendingLoad(); }, "_Cancel Current Operation", "file.cancelOperation", true, accelGroup, 'k');

    auto fileQuit = new MenuItem((MenuItem _) {
        persistCurrentState(clearSavedWindowGeometryOnExit);
        Main.quit();
    }, "_Quit", "file.quit", true, accelGroup, 'q');

    fileMenu.append(fileOpen);
    fileMenu.append(fileClose);
    fileMenu.append(fileReload);
    fileMenu.append(fileCancelOperation);
    fileMenu.append(new SeparatorMenuItem());
    fileMenu.append(fileQuit);
    menuBar.append(fileMenuItem);

    auto editMenuItem = new MenuItem("_Edit");
    auto editMenu = new Menu();
    editMenuItem.setSubmenu(editMenu);

    auto editApplyFilter = new MenuItem((MenuItem _) { applyFilterFromEntry(); }, "_Apply Filter", "edit.applyFilter", true, accelGroup, 'f');

    auto editClearFilter = new MenuItem((MenuItem _) {
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }
        document.filterQuery = "";
        document.filterVideo = false;
        document.filterAudio = false;
        document.filterImage = false;
        document.filterText = false;
        document.filterMediaNegated = false;
        document.filterFileType = false;
        document.filterArchive = false;
        document.filterTorrent = false;
        syncToolbarFromCurrentDocument();
        renderRows(document, document.loadedRows);
    }, "C_lear Filter", "edit.clearFilter", true, accelGroup, 'l');

    auto editPreferences = new MenuItem((MenuItem _) { showPreferencesDialog(); }, "_Preferences", "edit.preferences", true, accelGroup, ',');

    auto editResetMetrics = new MenuItem((MenuItem _) { resetPerfMetrics(); }, "_Reset Metrics", "edit.resetMetrics", true, accelGroup, 'm');

    editMenu.append(editApplyFilter);
    editMenu.append(editClearFilter);
    editMenu.append(new SeparatorMenuItem());
    editMenu.append(editResetMetrics);
    editMenu.append(editPreferences);
    menuBar.append(editMenuItem);

    auto helpMenuItem = new MenuItem("_Help");
    auto helpMenu = new Menu();
    helpMenuItem.setSubmenu(helpMenu);

    auto helpShortcuts = new MenuItem((MenuItem _) { showShortcutsHelp(); }, "_Keyboard Shortcuts", true);

    auto helpAbout = new MenuItem((MenuItem _) { showAbout(); }, "_About", true);

    helpMenu.append(helpShortcuts);
    helpMenu.append(new SeparatorMenuItem());
    helpMenu.append(helpAbout);
    menuBar.append(helpMenuItem);

    // btnLoad entfernt

    btnReload.addOnClicked((Button _) { reloadCurrentDocument(); });

    btnRelayout.addOnClicked((Button _) {
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }

        logLineVerbose("[relayout] manual relayout requested for ", document.filePath);
        document.pendingColumnMeasurement = true;
        document.tableView.setModel(document.tableStore);
        document.tableView.queueResize();
    });

    btnCancelLoad.addOnClicked((Button _) { cancelPendingLoad(); });

    btnApplyFilter.addOnClicked((Button _) { applyFilterFromEntry(); });

    btnClearFilter.addOnClicked((Button _) {
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }
        document.filterQuery = "";
        document.filterVideo = false;
        document.filterAudio = false;
        document.filterImage = false;
        document.filterText = false;
        document.filterMediaNegated = false;
        document.filterFileType = false;
        document.filterArchive = false;
        document.filterTorrent = false;
        syncToolbarFromCurrentDocument();
        renderRows(document, document.loadedRows);
    });

    // pathEntry entfernt

    filterEntry.addOnActivate((Entry _) { applyFilterFromEntry(); });

    filterVideo.addOnToggled((ToggleButton _) { applyFilterFromEntry(); });

    filterAudio.addOnToggled((ToggleButton _) { applyFilterFromEntry(); });

    filterImage.addOnToggled((ToggleButton _) { applyFilterFromEntry(); });

    filterText.addOnToggled((ToggleButton _) { applyFilterFromEntry(); });

    filterMediaNot.addOnToggled((ToggleButton _) { applyFilterFromEntry(); });

    filterFileType.addOnToggled((ToggleButton _) { applyFilterFromEntry(); });

    filterArchive.addOnToggled((ToggleButton _) { applyFilterFromEntry(); });

    filterTorrent.addOnToggled((ToggleButton _) { applyFilterFromEntry(); });

    notebook.addOnSwitchPage((Widget pageWidget, uint pageNum, Notebook tabNotebook) {
        syncToolbarFromCurrentDocument();
        persistCurrentState(clearSavedWindowGeometryOnExit);
    });

    window.addOnDestroy((Widget _) {
        persistCurrentState(clearSavedWindowGeometryOnExit);
        Main.quit();
    });

    window.addOnConfigure((GdkEventConfigure* event, Widget _) {
        if (event !is null && event.width >= MIN_VALID_WINDOW_WIDTH && event.height >= MIN_VALID_WINDOW_HEIGHT)
        {
            lastKnownWindowWidth = event.width;
            lastKnownWindowHeight = event.height;
        }
        return false;
    });

    window.addOnSizeAllocate((allocation, Widget _) {
        if (allocation.width >= MIN_VALID_WINDOW_WIDTH && allocation.height >= MIN_VALID_WINDOW_HEIGHT)
        {
            lastKnownWindowWidth = allocation.width;
            lastKnownWindowHeight = allocation.height;

            // Persist size shortly after resize settles, independent of quit path.
            if (allowRuntimeStatePersistence)
            {
                if (windowSizePersistTimer !is null)
                {
                    windowSizePersistTimer.stop();
                    windowSizePersistTimer = null;
                }
                windowSizePersistTimer = new Timeout(350, {
                    persistCurrentState(clearSavedWindowGeometryOnExit);
                    windowSizePersistTimer = null;
                    return false;
                });
            }
        }
    });

    menuBarSlot.packStart(menuBar, false, false, 0);
    window.add(root);
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

    previewVideoProgressTimer = new Timeout(250, {
        auto document = currentDocument();
        if (document !is null && document.selectedPreviewIsVideo && document.previewVideoPlayer !is null)
        {
            syncVideoPreviewPosition(document);
            syncVideoTrackSelectors(document);

            GstState state;
            GstState pending;
            if (document.previewVideoPlayer.getState(state, pending, 0) != GstStateChangeReturn.FAILURE)
            {
                syncVideoPlaybackButton(document, state == GstState.PLAYING);
            }
        }
        return true;
    });

    foreach (savedPath; loadedState.openFilePaths)
    {
        pendingStartupPaths ~= savedPath;
    }
    foreach (startupPath; cli.jsonPaths)
    {
        pendingStartupPaths ~= startupPath;
    }

    if (pendingStartupPaths.length > 0)
    {
        if (prefRestoreOpenFiles && loadedState.openFilePaths.length > 0)
        {
            pendingStartupSelectIndex = loadedState.activeTabIndex;
        }
        loadNextPendingStartupPath();
    }
    else if (cli.selfTestMode && !selfTestQuitScheduled)
    {
        selfTestQuitScheduled = true;
        logLine("[self-test] scheduling quit in ", cli.selfTestDelayMs, " ms");
        selfTestQuitTimer = new Timeout(cli.selfTestDelayMs, {
            logLine("[self-test] quitting after startup delay");
            Main.quit();
            return false;
        });
    }

    Main.run();
    return 0;
}
