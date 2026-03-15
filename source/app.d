/** Main GTK application shell for DosierSkanilo GUI.
 *
 * This module wires together command-line startup options, JSON loading,
 * row-table rendering, and classic desktop menu actions.
 *
 * Authors: DosierSkanilo contributors
 * License: CC-BY-NC-SA 4.0
 */
module app;

import gtk.Main;
import gtk.Widget;
import gtk.Window;
import gtk.Box;
import gtk.Label;
import gtk.Button;
import gtk.Separator;
import gtk.Entry;
import gtk.Spinner;
import gtk.ProgressBar;
import gtk.ScrolledWindow;
import gtk.TextView;
import gtk.TreeView;
import gtk.ListStore;
import gtk.CellRendererText;
import gtk.TreeViewColumn;
import gtk.TreeIter;
import gtk.TreeSelection;
import gtk.TreeModelIF;
import gtk.Paned;
import gtk.MenuBar;
import gtk.Menu;
import gtk.MenuItem;
import gtk.SeparatorMenuItem;
import gtk.AccelGroup;
import gtk.Dialog;
import gtk.CheckButton;
import gtk.ToggleButton;
import gtk.FileChooserDialog;
import gtk.AboutDialog;
import gtk.MessageDialog;
import gtk.c.types : Orientation, DialogFlags, ResponseType, ButtonsType, MessageType, FileChooserAction, GtkTreeViewColumnSizing;
import glib.Idle;
import glib.Timeout;
import gobject.Type : GType;
import gtk.Clipboard;
import gdk.Display;
import gdk.MonitorG;
import gdk.c.types : GdkRectangle, GdkEventConfigure;

import core.thread : Thread;
import core.time : MonoTime;
import std.file : exists, readText, write, mkdirRecurse;
import std.format : format;
import std.json : parseJSON, JSONType, JSONValue;
import std.base64 : Base64;
import std.conv : to;
import std.getopt : getopt, config;
import std.stdio : writeln, File;
import std.array : appender;
import std.algorithm : sort;
import std.string : join;
import std.path : buildPath;
import std.process : environment;

import io.dosierjson : extractRowsFromRoot;
import model.blobrow : BlobRow;
import view.textreport : countDuplicateDigestGroups, filterRowsByText;

enum string DEFAULT_JSON_PATH = "./.filescanner.json";

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

/** Parsed startup options from command-line arguments. */
struct CliOptions {
    string jsonPath = DEFAULT_JSON_PATH;
    bool jsonPathProvided;
    bool loadOnStart;
    string filterOnStart;
    bool caseSensitiveFilter;
    bool disableAutoFilter;
    bool showHelp;
}

/** Worker result payload for background JSON loading. */
struct AsyncLoadResult {
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
struct AsyncFilterResult {
    BlobRow[] filteredRows;
    string query;
    bool caseSensitive;
    string mediaStats;
    string error;
    long elapsedMs;
}

/** Persisted UI state stored below the user's config directory. */
struct AppState {
    bool prefAutoApplyFilter = true;
    bool prefCaseSensitiveFilter;
    bool prefDetailsBelow;

    int splitPositionHorizontal = 720;
    int splitPositionVertical = 420;

    bool hasWindowGeometry;
    int windowX;
    int windowY;
    bool hasWindowSize;
    int windowWidth = 960;
    int windowHeight = 640;
    int windowMonitorIndex = -1;
}

enum string CONFIG_DIR_NAME = ".config/dosierskanilo-gui";
enum string CONFIG_FILE_NAME = "state.json";
enum string RESTORE_LOG_FILE_NAME = "restore.log";

/** Resolve the application config directory. */
string configDirPath() {
    auto home = environment.get("HOME", "");
    if (home.length == 0) {
        return "./" ~ CONFIG_DIR_NAME;
    }
    return buildPath(home, CONFIG_DIR_NAME);
}

/** Resolve the JSON state file path. */
string configFilePath() {
    return buildPath(configDirPath(), CONFIG_FILE_NAME);
}

/** Resolve the diagnostic log path used for geometry restore troubleshooting. */
string restoreLogFilePath() {
    return buildPath(configDirPath(), RESTORE_LOG_FILE_NAME);
}

/** Append a single restore diagnostic line to the per-user log file. */
void appendRestoreLog(string message) {
    try {
        mkdirRecurse(configDirPath());
        auto file = File(restoreLogFilePath(), "a");
        file.writeln(message);
        file.close();
    } catch (Exception) {
        // Diagnostics must never break app startup.
    }
}

/** Convert a JSON scalar into a bool with fallback semantics. */
bool jsonToBool(JSONValue value, bool fallback = false) {
    switch (value.type) {
        case JSONType.true_:
            return true;
        case JSONType.false_:
            return false;
        case JSONType.integer:
            return value.integer != 0;
        case JSONType.uinteger:
            return value.uinteger != 0;
        default:
            return fallback;
    }
}

/** Convert a JSON scalar into an int with fallback semantics. */
int jsonToInt(JSONValue value, int fallback = 0) {
    switch (value.type) {
        case JSONType.integer:
            return cast(int) value.integer;
        case JSONType.uinteger:
            return cast(int) value.uinteger;
        case JSONType.float_:
            return cast(int) value.floating;
        default:
            return fallback;
    }
}

/** Load persisted preferences, splitter state, and window geometry hints. */
AppState loadAppState() {
    AppState state;
    auto path = configFilePath();
    if (!exists(path)) {
        return state;
    }

    try {
        auto parsed = parseJSON(readText(path));
        if (parsed.type != JSONType.object) {
            return state;
        }

        auto root = parsed.object;
        if (auto value = "prefAutoApplyFilter" in root) {
            state.prefAutoApplyFilter = jsonToBool(*value, state.prefAutoApplyFilter);
        }
        if (auto value = "prefCaseSensitiveFilter" in root) {
            state.prefCaseSensitiveFilter = jsonToBool(*value, state.prefCaseSensitiveFilter);
        }
        if (auto value = "prefDetailsBelow" in root) {
            state.prefDetailsBelow = jsonToBool(*value, state.prefDetailsBelow);
        }

        if (auto value = "splitPositionHorizontal" in root) {
            state.splitPositionHorizontal = jsonToInt(*value, state.splitPositionHorizontal);
        }
        if (auto value = "splitPositionVertical" in root) {
            state.splitPositionVertical = jsonToInt(*value, state.splitPositionVertical);
        }

        if (auto value = "hasWindowGeometry" in root) {
            state.hasWindowGeometry = jsonToBool(*value, state.hasWindowGeometry);
        }
        if (auto value = "windowX" in root) {
            state.windowX = jsonToInt(*value, state.windowX);
        }
        if (auto value = "windowY" in root) {
            state.windowY = jsonToInt(*value, state.windowY);
        }
        if (auto value = "windowWidth" in root) {
            state.windowWidth = jsonToInt(*value, state.windowWidth);
        }
        if (auto value = "windowHeight" in root) {
            state.windowHeight = jsonToInt(*value, state.windowHeight);
        }
        if (auto value = "hasWindowSize" in root) {
            state.hasWindowSize = jsonToBool(*value, state.hasWindowSize);
        }
        if (auto value = "windowMonitorIndex" in root) {
            state.windowMonitorIndex = jsonToInt(*value, state.windowMonitorIndex);
        }
    } catch (Exception) {
        // Keep defaults on invalid state file.
    }

    return state;
}

/** Write the current application state to the JSON config file. */
void saveAppState(const(AppState) state) {
    auto dirPath = configDirPath();
    auto filePath = configFilePath();
    mkdirRecurse(dirPath);

    auto payload = format(
        "{\n" ~
        "  \"prefAutoApplyFilter\": %s,\n" ~
        "  \"prefCaseSensitiveFilter\": %s,\n" ~
        "  \"prefDetailsBelow\": %s,\n" ~
        "  \"splitPositionHorizontal\": %s,\n" ~
        "  \"splitPositionVertical\": %s,\n" ~
        "  \"hasWindowGeometry\": %s,\n" ~
        "  \"windowX\": %s,\n" ~
        "  \"windowY\": %s,\n" ~
        "  \"hasWindowSize\": %s,\n" ~
        "  \"windowWidth\": %s,\n" ~
        "  \"windowHeight\": %s,\n" ~
        "  \"windowMonitorIndex\": %s\n" ~
        "}\n",
        state.prefAutoApplyFilter ? "true" : "false",
        state.prefCaseSensitiveFilter ? "true" : "false",
        state.prefDetailsBelow ? "true" : "false",
        state.splitPositionHorizontal,
        state.splitPositionVertical,
        state.hasWindowGeometry ? "true" : "false",
        state.windowX,
        state.windowY,
        state.hasWindowSize ? "true" : "false",
        state.windowWidth,
        state.windowHeight,
        state.windowMonitorIndex
    );

    write(filePath, payload);
}

/** Map a screen position to the corresponding monitor index. */
int monitorIndexForPoint(Display display, int x, int y) {
    if (display is null) {
        return -1;
    }

    auto monitor = display.getMonitorAtPoint(x, y);
    if (monitor is null) {
        return -1;
    }

    auto monitorCount = display.getNMonitors();
    for (int i = 0; i < monitorCount; ++i) {
        if (display.getMonitor(i) is monitor) {
            return i;
        }
    }

    return -1;
}

/** Clamp window geometry to a visible monitor work area. */
void clampWindowGeometryToVisibleArea(ref int x, ref int y, ref int width, ref int height, int preferredMonitorIndex = -1) {
    auto display = Display.getDefault();
    if (display is null) {
        return;
    }

    MonitorG monitor;
    if (preferredMonitorIndex >= 0 && preferredMonitorIndex < display.getNMonitors()) {
        monitor = display.getMonitor(preferredMonitorIndex);
    }
    if (monitor is null) {
        monitor = display.getMonitorAtPoint(x, y);
    }
    if (monitor is null) {
        monitor = display.getPrimaryMonitor();
    }
    if (monitor is null && display.getNMonitors() > 0) {
        monitor = display.getMonitor(0);
    }
    if (monitor is null) {
        return;
    }

    GdkRectangle bounds;
    monitor.getWorkarea(bounds);
    if (bounds.width <= 0 || bounds.height <= 0) {
        monitor.getGeometry(bounds);
    }
    if (bounds.width <= 0 || bounds.height <= 0) {
        return;
    }

    // Keep at least a usable minimum size and clamp to monitor work area.
    if (width < 640) {
        width = 640;
    }
    if (height < 400) {
        height = 400;
    }
    if (width > bounds.width) {
        width = bounds.width;
    }
    if (height > bounds.height) {
        height = bounds.height;
    }

    auto maxX = bounds.x + bounds.width - width;
    auto maxY = bounds.y + bounds.height - height;
    if (maxX < bounds.x) {
        maxX = bounds.x;
    }
    if (maxY < bounds.y) {
        maxY = bounds.y;
    }

    if (x < bounds.x) {
        x = bounds.x;
    } else if (x > maxX) {
        x = maxX;
    }

    if (y < bounds.y) {
        y = bounds.y;
    } else if (y > maxY) {
        y = maxY;
    }
}

/** Return human-readable CLI usage text. */
string cliUsageText() {
    return
        "DosierSkanilo GUI\n" ~
        "\n" ~
        "Usage:\n" ~
        "  dosierskanilo-gui [options]\n" ~
        "\n" ~
        "Options:\n" ~
        "  -j, --json <file>         JSON file to open\n" ~
        "  -l, --load                Load on startup\n" ~
        "  -q, --query <text>        Apply initial text filter\n" ~
        "      --case-sensitive      Use case-sensitive text filtering\n" ~
        "      --no-auto-filter      Disable auto filter after load\n" ~
        "  -h, --help                Show this help text\n";
}

/** Parse CLI arguments into startup option flags.
 *
 * Params:
 *   args = command-line argument array (in/out for getopt)
 * Returns:
 *   Parsed options with defaults applied
 */
CliOptions parseCliOptions(ref string[] args) {
    CliOptions opts;

    getopt(
        args,
        config.passThrough,
        "j|json", &opts.jsonPath,
        "l|load", &opts.loadOnStart,
        "q|query", &opts.filterOnStart,
        "case-sensitive", &opts.caseSensitiveFilter,
        "no-auto-filter", &opts.disableAutoFilter,
        "h|help", &opts.showHelp
    );

    opts.jsonPathProvided = opts.jsonPath != DEFAULT_JSON_PATH;
    if (opts.jsonPathProvided) {
        opts.loadOnStart = true;
    }

    return opts;
}

/** Configure columns for the main result table.
 *
 * Params:
 *   treeView = target tree view instance
 */
void configureTableColumns(TreeView treeView) {
    void addTextColumn(string title, int modelColumn, int sortColumn = -1) {
        auto renderer = new CellRendererText();
        auto column = new TreeViewColumn();
        column.setTitle(title);
        column.packStart(renderer, false);
        column.addAttribute(renderer, "text", modelColumn);
        column.setSortColumnId(sortColumn >= 0 ? sortColumn : modelColumn);
        column.setResizable(false);
        column.setExpand(false);
        column.setSizing(GtkTreeViewColumnSizing.AUTOSIZE);
        column.setClickable(true);
        treeView.appendColumn(column);
    }

    addTextColumn("Index#", COL_INDEX, COL_INDEX_SORT);
    addTextColumn("Size", COL_FILE_SIZE, COL_FILE_SIZE_SORT);
    addTextColumn("Checksums", COL_CHECKSUM_SET);
    addTextColumn("File Type", COL_FILE_TYPE);
    addTextColumn("MediaInfo", COL_MEDIA_INFO);
    addTextColumn("Archive", COL_HAS_ARCHIVE);
    addTextColumn("Torrent", COL_HAS_TORRENT);

    treeView.setHeadersClickable(true);
}

/** Summarize checksum availability for the list view. */
string checksumSetStatus(const(BlobRow) row) {
    auto present = 0;
    if (row.md5.length > 0) {
        ++present;
    }
    if (row.sha1.length > 0) {
        ++present;
    }
    if (row.xxh64.length > 0) {
        ++present;
    }

    if (present == 0) {
        return "none";
    }
    if (present == 3) {
        return "full";
    }
    return format("partial (%s/3)", present);
}

/** Render a compact status icon for boolean table cells. */
string boolStatusIcon(bool value) {
    return value ? "🟢✓" : "🔴✗";
}

/** Summarize media subtype flags for the list view. */
string mediaInfoSummary(const(BlobRow) row) {
    auto labels = appender!(string[])();
    if (row.hasVideo) {
        labels.put("V");
    }
    if (row.hasAudio) {
        labels.put("A");
    }
    if (row.hasImage) {
        labels.put("I");
    }
    if (row.hasText) {
        labels.put("T");
    }

    if (labels.data.length > 0) {
        return labels.data.join(",");
    }
    return row.hasMedia ? "yes" : "-";
}

/** Count media subtype hits in the currently filtered row set. */
string mediaHitStats(const(BlobRow)[] rows) {
    size_t videoCount;
    size_t audioCount;
    size_t imageCount;
    size_t textCount;

    foreach (row; rows) {
        if (row.hasVideo) {
            ++videoCount;
        }
        if (row.hasAudio) {
            ++audioCount;
        }
        if (row.hasImage) {
            ++imageCount;
        }
        if (row.hasText) {
            ++textCount;
        }
    }

    return format("hits V:%s A:%s I:%s T:%s", videoCount, audioCount, imageCount, textCount);
}

/** Convert a base64-encoded digest into lowercase hexadecimal text. */
string digestBase64ToHex(string digest) {
    if (digest.length == 0) {
        return "-";
    }

    try {
        auto bytes = Base64.decode(digest);
        auto builder = appender!string();
        foreach (b; bytes) {
            builder.put(format("%02x", b));
        }
        return builder.data;
    } catch (Exception) {
        return "<invalid base64>";
    }
}

/** Populate GTK list store with projected blob rows.
 *
 * Params:
 *   store = destination list model
 *   rows = normalized rows to append
 */
void populateTableRows(ListStore store, const(BlobRow)[] rows) {
    store.clear();

    string numericSortKey(ulong value) {
        return format("%020d", value);
    }

    foreach (idx, row; rows) {
        auto indexText = to!string(idx + 1);
        auto sizeText = to!string(row.fileSize);
        auto checksumsText = checksumSetStatus(row);
        auto fileTypeText = row.fileType.length > 0 ? "yes" : "no";
        auto mediaInfoText = mediaInfoSummary(row);
        auto archiveText = boolStatusIcon(row.hasArchive);
        auto torrentText = boolStatusIcon(row.hasTorrent);

        TreeIter iter;
        store.append(iter);
        store.set(
            iter,
            [
                COL_INDEX,
                COL_FILE_SIZE,
                COL_CHECKSUM_SET,
                COL_FILE_TYPE,
                COL_MEDIA_INFO,
                COL_HAS_ARCHIVE,
                COL_HAS_TORRENT,
                COL_INDEX_SORT,
                COL_FILE_SIZE_SORT
            ],
            [
                indexText,
                sizeText,
                checksumsText,
                fileTypeText,
                mediaInfoText,
                archiveText,
                torrentText,
                numericSortKey(to!ulong(idx + 1)),
                numericSortKey(row.fileSize)
            ]
        );
    }
}

/** Program entry point.
 *
 * Params:
 *   args = process command-line arguments
 * Returns:
 *   exit code
 */
int main(string[] args) {
    auto cli = parseCliOptions(args);
    if (cli.showHelp) {
        writeln(cliUsageText());
        return 0;
    }

    auto loadedState = loadAppState();

    Main.init(args);

    auto window = new Window("DosierSkanilo GUI");
    window.setDefaultSize(loadedState.windowWidth, loadedState.windowHeight);

    auto accelGroup = new AccelGroup();
    window.addAccelGroup(accelGroup);

    auto root = new Box(Orientation.VERTICAL, 0);

    auto content = new Box(Orientation.VERTICAL, 10);
    content.setBorderWidth(10);

    auto separator = new Separator(Orientation.HORIZONTAL);

    auto toolbar = new Box(Orientation.HORIZONTAL, 8);
    auto pathEntry = new Entry();
    pathEntry.setHexpand(true);
    pathEntry.setText(DEFAULT_JSON_PATH);

    auto btnLoad = new Button("Load JSON");
    auto btnReload = new Button("Reload");
    auto btnCancelLoad = new Button("Cancel");
    btnCancelLoad.setSensitive(false);
    auto loadSpinner = new Spinner();
    loadSpinner.setVisible(false);

    auto filterEntry = new Entry();
    filterEntry.setHexpand(true);
    filterEntry.setPlaceholderText("Filter by filename or SHA1...");
    auto filterVideo = new CheckButton("V");
    filterVideo.setTooltipText("Filter to rows with video media metadata");
    auto filterAudio = new CheckButton("A");
    filterAudio.setTooltipText("Filter to rows with audio media metadata");
    auto filterImage = new CheckButton("I");
    filterImage.setTooltipText("Filter to rows with image media metadata");
    auto filterText = new CheckButton("T");
    filterText.setTooltipText("Filter to rows with text/subtitle media metadata");

    auto btnApplyFilter = new Button("Apply Filter");
    auto btnClearFilter = new Button("Clear Filter");

    auto progressBar = new ProgressBar();
    progressBar.setHexpand(true);
    progressBar.setShowText(true);
    progressBar.setText("Idle");
    progressBar.setPulseStep(0.05);
    progressBar.setVisible(false);

    toolbar.packStart(pathEntry, true, true, 0);
    toolbar.packStart(btnLoad, false, false, 0);
    toolbar.packStart(btnReload, false, false, 0);
    toolbar.packStart(btnCancelLoad, false, false, 0);
    toolbar.packStart(loadSpinner, false, false, 0);
    toolbar.packStart(filterEntry, true, true, 0);
    toolbar.packStart(filterVideo, false, false, 0);
    toolbar.packStart(filterAudio, false, false, 0);
    toolbar.packStart(filterImage, false, false, 0);
    toolbar.packStart(filterText, false, false, 0);
    toolbar.packStart(btnApplyFilter, false, false, 0);
    toolbar.packStart(btnClearFilter, false, false, 0);
    toolbar.packStart(progressBar, true, true, 0);

    auto tableStore = new ListStore([
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
    auto tableView = new TreeView(tableStore);
    configureTableColumns(tableView);

    auto scroll = new ScrolledWindow(null, null);
    scroll.setVexpand(true);
    scroll.setHexpand(true);
    scroll.add(tableView);

    auto detailsView = new TextView();
    detailsView.setEditable(false);
    detailsView.setMonospace(true);
    detailsView.getBuffer().setText(
        "No details selected yet.\n\n" ~
        "Select a table row to populate this panel.\n\n" ~
        "SHA1: <none>\n" ~
        "File: <none>\n" ~
        "Checksums: <none>\n" ~
        "Media: <none>\n"
    );

    auto detailsActions = new Box(Orientation.HORIZONTAL, 6);
    auto btnCopySha1 = new Button("Copy SHA1");
    auto btnCopyFile = new Button("Copy File");
    auto btnCopyDetails = new Button("Copy Details");
    btnCopySha1.setSensitive(false);
    btnCopyFile.setSensitive(false);
    btnCopyDetails.setSensitive(false);
    detailsActions.packStart(btnCopySha1, false, false, 0);
    detailsActions.packStart(btnCopyFile, false, false, 0);
    detailsActions.packStart(btnCopyDetails, false, false, 0);

    auto detailsScroll = new ScrolledWindow(null, null);
    detailsScroll.setVexpand(true);
    detailsScroll.setHexpand(true);
    detailsScroll.add(detailsView);

    auto detailsPane = new Box(Orientation.VERTICAL, 6);
    detailsPane.packStart(detailsActions, false, false, 0);
    detailsPane.packStart(detailsScroll, true, true, 0);

    auto split = new Paned(Orientation.HORIZONTAL);
    split.pack1(scroll, true, true);
    // Keep details pane from collapsing away entirely.
    split.pack2(detailsPane, true, false);
    split.setPosition(loadedState.splitPositionHorizontal);

    auto status = new Label("Ready.");
    status.setXalign(0.0f);

    auto perfStatus = new Label("Timings: load=- ms | filter=- ms | render=- ms");
    perfStatus.setXalign(0.0f);

    auto fileMetaStatus = new Label("File metadata: version=- | root=- | keys=-");
    fileMetaStatus.setXalign(0.0f);

    auto rowDetails = new Label("Selection: none");
    rowDetails.setXalign(0.0f);

    BlobRow[] loadedRows;
    BlobRow[] visibleRows;
    string loadedFilePath;
    size_t loadedDuplicateGroups;
    string selectedSha1;
    string selectedFileName;
    string selectedDetailsText;
    int loadedDataVersion = -1;
    string loadedRootShape = "-";
    string loadedRootKeysSummary = "-";

    bool prefAutoApplyFilter = loadedState.prefAutoApplyFilter;
    bool prefCaseSensitiveFilter = loadedState.prefCaseSensitiveFilter;
    bool prefDetailsBelow = loadedState.prefDetailsBelow;
    bool clearSavedWindowGeometryOnExit;
    bool allowRuntimeStatePersistence = !loadedState.hasWindowSize;
    int splitPositionHorizontal = loadedState.splitPositionHorizontal;
    int splitPositionVertical = loadedState.splitPositionVertical;
    int lastKnownWindowWidth = loadedState.windowWidth;
    int lastKnownWindowHeight = loadedState.windowHeight;
    int startupSizeAllocateLogCount;
    Timeout windowSizePersistTimer;
    bool isLoading;
    ulong loadRequestId;
    ulong filterRequestId;
    ulong renderRequestId;
    long pendingLoadElapsedMs = -1;
    string pendingStatusSuffix;
    Timeout progressPulseTimer;
    long lastLoadElapsedMs = -1;
    long lastFilterElapsedMs = -1;
    long lastRenderElapsedMs = -1;

    if (cli.disableAutoFilter) {
        prefAutoApplyFilter = false;
    }
    if (cli.caseSensitiveFilter) {
        prefCaseSensitiveFilter = true;
    }

    auto menuBar = new MenuBar();

    if (cli.jsonPath.length > 0) {
        pathEntry.setText(cli.jsonPath);
    }
    if (cli.filterOnStart.length > 0) {
        filterEntry.setText(cli.filterOnStart);
    }

    /** Format internal timing values for status labels. */
    string formatTimingValue(long valueMs) {
        return valueMs >= 0 ? format("%s", valueMs) : "-";
    }

    /** Refresh the performance summary label. */
    void updatePerfStatus() {
        perfStatus.setText(format(
            "Timings: load=%s ms | filter=%s ms | render=%s ms",
            formatTimingValue(lastLoadElapsedMs),
            formatTimingValue(lastFilterElapsedMs),
            formatTimingValue(lastRenderElapsedMs)
        ));
    }

    /** Refresh the metadata status label for the loaded JSON file. */
    void updateFileMetaStatus() {
        auto dataVersionText = loadedDataVersion >= 0 ? to!string(loadedDataVersion) : "-";
        fileMetaStatus.setText(format(
            "File metadata: version=%s | root=%s | keys=%s",
            dataVersionText,
            loadedRootShape,
            loadedRootKeysSummary
        ));
    }

    /** Toggle the loading UI state consistently across controls. */
    void setLoadingState(bool loading, string message = "") {
        isLoading = loading;

        pathEntry.setSensitive(!loading);
        btnLoad.setSensitive(!loading);
        btnReload.setSensitive(!loading);
        btnCancelLoad.setSensitive(loading);
        filterEntry.setSensitive(!loading);
        filterVideo.setSensitive(!loading);
        filterAudio.setSensitive(!loading);
        filterImage.setSensitive(!loading);
        filterText.setSensitive(!loading);
        btnApplyFilter.setSensitive(!loading);
        btnClearFilter.setSensitive(!loading);
        btnCopySha1.setSensitive(!loading && selectedSha1.length > 0);
        btnCopyFile.setSensitive(!loading && selectedFileName.length > 0);
        btnCopyDetails.setSensitive(!loading && selectedDetailsText.length > 0);

        if (loading) {
            loadSpinner.setVisible(true);
            loadSpinner.start();

            progressBar.setVisible(true);
            auto loadingText = message.length > 0 ? message : "Loading...";
            progressBar.setText(loadingText);
            progressBar.pulse();
            if (progressPulseTimer is null) {
                progressPulseTimer = new Timeout(120, {
                    if (!isLoading) {
                        return false;
                    }
                    progressBar.pulse();
                    return true;
                });
            }

            status.setText(loadingText);
            return;
        }

        loadSpinner.stop();
        loadSpinner.setVisible(false);

        if (progressPulseTimer !is null) {
            progressPulseTimer.stop();
            progressPulseTimer = null;
        }
        progressBar.setVisible(false);
        progressBar.setFraction(0.0);
        progressBar.setText("Idle");

        if (message.length > 0) {
            status.setText(message);
        }
    }

    /** Publish a worker phase update back onto the GTK main loop. */
    void setLoadingPhase(ulong expectedRequestId, string phaseText) {
        new Idle({
            if (expectedRequestId != loadRequestId || !isLoading) {
                return false;
            }

            status.setText(phaseText);
            progressBar.setText(phaseText);
            return false;
        });
    }

    /** Clear collected performance timings shown in the footer. */
    void resetPerfMetrics() {
        lastLoadElapsedMs = -1;
        lastFilterElapsedMs = -1;
        lastRenderElapsedMs = -1;
        updatePerfStatus();
        status.setText("Performance metrics reset.");
    }

    /** Reset selection-dependent detail fields to the empty placeholder state. */
    void clearSelectionDetails() {
        selectedSha1 = "";
        selectedFileName = "";
        selectedDetailsText = "";
        btnCopySha1.setSensitive(false);
        btnCopyFile.setSensitive(false);
        btnCopyDetails.setSensitive(false);
        rowDetails.setText("Selection: none");
        detailsView.getBuffer().setText(
            "No details selected yet.\n\n" ~
            "Select a table row to populate this panel.\n\n" ~
            "SHA1: <none>\n" ~
            "File: <none>\n" ~
            "Checksums: <none>\n" ~
            "Media: <none>\n"
        );
    }

    /** Keep the splitter divider within usable visible bounds. */
    int clampSplitPositionToVisibleBounds(Orientation orientation, int requestedPosition) {
        enum int MIN_PRIMARY_EXTENT = 240;
        enum int MIN_DETAILS_EXTENT = 180;

        int totalExtent = 0;
        if (orientation == Orientation.VERTICAL) {
            totalExtent = split.getAllocatedHeight();
        } else {
            totalExtent = split.getAllocatedWidth();
        }

        if (totalExtent <= 0) {
            return requestedPosition;
        }

        if (totalExtent <= (MIN_PRIMARY_EXTENT + MIN_DETAILS_EXTENT)) {
            return totalExtent / 2;
        }

        auto minPosition = MIN_PRIMARY_EXTENT;
        auto maxPosition = totalExtent - MIN_DETAILS_EXTENT;
        if (requestedPosition < minPosition) {
            return minPosition;
        }
        if (requestedPosition > maxPosition) {
            return maxPosition;
        }
        return requestedPosition;
    }

    /** Apply the preferred splitter orientation and the matching saved divider position. */
    void applyDetailsPanePreference(bool captureCurrentPosition = true) {
        if (captureCurrentPosition) {
            auto currentOrientation = split.getOrientation();
            auto currentPosition = split.getPosition();
            if (currentOrientation == Orientation.VERTICAL) {
                splitPositionVertical = currentPosition;
            } else {
                splitPositionHorizontal = currentPosition;
            }
        }

        auto orientation = prefDetailsBelow ? Orientation.VERTICAL : Orientation.HORIZONTAL;
        auto splitPosition = prefDetailsBelow ? splitPositionVertical : splitPositionHorizontal;

        // Keep the same paned instance and flip orientation in place.
        // Rebuilding/reparenting the children can invalidate GTK widget ownership.
        split.setOrientation(orientation);

        auto clampedPosition = clampSplitPositionToVisibleBounds(orientation, splitPosition);
        split.setPosition(clampedPosition);

        // Re-apply once after layout to clamp against real allocated size.
        new Idle({
            auto realizedClamped = clampSplitPositionToVisibleBounds(orientation, splitPosition);
            split.setPosition(realizedClamped);
            if (orientation == Orientation.VERTICAL) {
                splitPositionVertical = realizedClamped;
            } else {
                splitPositionHorizontal = realizedClamped;
            }
            return false;
        });
    }

    /** Snapshot the current preferences, splitter state, and window size. */
    AppState currentAppState(bool clearWindowGeometry = false) {
        AppState state;
        state.prefAutoApplyFilter = prefAutoApplyFilter;
        state.prefCaseSensitiveFilter = prefCaseSensitiveFilter;
        state.prefDetailsBelow = prefDetailsBelow;

        auto currentOrientation = split.getOrientation();
        auto currentSplitPosition = split.getPosition();
        if (currentOrientation == Orientation.VERTICAL) {
            splitPositionVertical = currentSplitPosition;
        } else {
            splitPositionHorizontal = currentSplitPosition;
        }

        state.splitPositionHorizontal = splitPositionHorizontal;
        state.splitPositionVertical = splitPositionVertical;

        int width = lastKnownWindowWidth;
        int height = lastKnownWindowHeight;

        auto allocatedWidth = window.getAllocatedWidth();
        auto allocatedHeight = window.getAllocatedHeight();
        if (allocatedWidth > 0 && allocatedHeight > 0) {
            width = allocatedWidth;
            height = allocatedHeight;
        }

        if (width <= 0) {
            width = 960;
        }
        if (height <= 0) {
            height = 640;
        }

        lastKnownWindowWidth = width;
        lastKnownWindowHeight = height;
        state.hasWindowSize = true;
        state.windowWidth = width;
        state.windowHeight = height;
        appendRestoreLog(format(
            "persist snapshot width=%s height=%s trackedWidth=%s trackedHeight=%s allocatedWidth=%s allocatedHeight=%s",
            state.windowWidth,
            state.windowHeight,
            lastKnownWindowWidth,
            lastKnownWindowHeight,
            allocatedWidth,
            allocatedHeight
        ));

        if (clearWindowGeometry) {
            state.hasWindowGeometry = false;
            state.windowX = 0;
            state.windowY = 0;
            state.windowMonitorIndex = -1;
            return state;
        }

        // Do not persist window position to avoid monitor jump issues.
        state.hasWindowGeometry = false;
        state.windowX = 0;
        state.windowY = 0;
        state.windowMonitorIndex = -1;
        return state;
    }


    /** Persist the current application state and surface write failures in the UI. */
    void persistCurrentState(bool clearWindowGeometry = false) {
        try {
            saveAppState(currentAppState(clearWindowGeometry));
        } catch (Exception ex) {
            status.setText(format("Failed to persist app state: %s", ex.msg));
        }
    }

    // Apply persisted splitter orientation/position once the helper is available.
    applyDetailsPanePreference(false);

    /** Re-render the current row set into the table model in small GTK-friendly batches. */
    void renderRows(const(BlobRow)[] rows, string filterLabel = "") {
        if (loadedFilePath.length == 0) {
            tableStore.clear();
            visibleRows = [];
            clearSelectionDetails();
            loadedDataVersion = -1;
            loadedRootShape = "-";
            loadedRootKeysSummary = "-";
            updateFileMetaStatus();
            status.setText("Ready.");
            return;
        }

        auto rowsCopy = rows.dup;
        MonoTime renderStarted = MonoTime.currTime;
        auto localRenderRequestId = ++renderRequestId;
        enum size_t RENDER_BATCH_SIZE = 500;

        tableStore.clear();
        visibleRows = [];
        clearSelectionDetails();

        size_t nextIndex = 0;
        bool delegate() renderStep;
        renderStep = {
            if (localRenderRequestId != renderRequestId) {
                return false;
            }

            auto endIndex = nextIndex + RENDER_BATCH_SIZE;
            if (endIndex > rowsCopy.length) {
                endIndex = rowsCopy.length;
            }

            foreach (idx; nextIndex .. endIndex) {
                auto row = rowsCopy[idx];
                auto indexText = to!string(idx + 1);
                auto sizeText = to!string(row.fileSize);
                auto checksumsText = checksumSetStatus(row);
                auto fileTypeText = row.fileType.length > 0 ? "yes" : "no";
                auto mediaInfoText = mediaInfoSummary(row);
                auto archiveText = boolStatusIcon(row.hasArchive);
                auto torrentText = boolStatusIcon(row.hasTorrent);

                auto indexSortText = format("%020d", cast(ulong) idx + 1);
                auto sizeSortText = format("%020d", row.fileSize);

                TreeIter iter;
                tableStore.append(iter);
                tableStore.set(
                    iter,
                    [
                        COL_INDEX,
                        COL_FILE_SIZE,
                        COL_CHECKSUM_SET,
                        COL_FILE_TYPE,
                        COL_MEDIA_INFO,
                        COL_HAS_ARCHIVE,
                        COL_HAS_TORRENT,
                        COL_INDEX_SORT,
                        COL_FILE_SIZE_SORT
                    ],
                    [
                        indexText,
                        sizeText,
                        checksumsText,
                        fileTypeText,
                        mediaInfoText,
                        archiveText,
                        torrentText,
                        indexSortText,
                        sizeSortText
                    ]
                );
            }

            nextIndex = endIndex;
            if (nextIndex < rowsCopy.length) {
                status.setText(format("Rendering rows: %s/%s ...", nextIndex, rowsCopy.length));
                return true;
            }

            visibleRows = rowsCopy.dup;
            lastRenderElapsedMs = cast(long) (MonoTime.currTime - renderStarted).total!"msecs";
            updatePerfStatus();
            string baseStatus;
            if (filterLabel.length > 0) {
                baseStatus = format(
                    "Showing %s/%s rows (duplicate digest groups: %s, filter: %s, case-sensitive: %s)",
                    rowsCopy.length,
                    loadedRows.length,
                    loadedDuplicateGroups,
                    filterLabel,
                    prefCaseSensitiveFilter ? "yes" : "no"
                );
            } else {
                baseStatus = format(
                    "Showing %s/%s rows (duplicate digest groups: %s)",
                    rowsCopy.length,
                    loadedRows.length,
                    loadedDuplicateGroups
                );
            }

            if (pendingLoadElapsedMs >= 0) {
                baseStatus = format("%s | load time: %s ms", baseStatus, pendingLoadElapsedMs);
                pendingLoadElapsedMs = -1;
            }

            if (pendingStatusSuffix.length > 0) {
                baseStatus = format("%s | %s", baseStatus, pendingStatusSuffix);
                pendingStatusSuffix = "";
            }

            if (isLoading) {
                setLoadingState(false);
            }
            status.setText(baseStatus);
            return false;
        };

        new Idle(renderStep);
    }

    /** Update the detail pane for the currently selected table row. */
    void updateSelectedRowDetails() {
        TreeModelIF model;
        TreeIter iter;
        auto selection = tableView.getSelection();
        if (!selection.getSelected(model, iter)) {
            clearSelectionDetails();
            return;
        }

        auto idx = model.getValueString(iter, COL_INDEX);
        auto size = model.getValueString(iter, COL_FILE_SIZE);
        auto checksums = model.getValueString(iter, COL_CHECKSUM_SET);
        auto fileType = model.getValueString(iter, COL_FILE_TYPE);
        auto mediaInfo = model.getValueString(iter, COL_MEDIA_INFO);
        auto archive = model.getValueString(iter, COL_HAS_ARCHIVE);
        auto torrent = model.getValueString(iter, COL_HAS_TORRENT);
        rowDetails.setText(format(
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
        try {
            rowIndex = to!size_t(idx) - 1;
        } catch (Exception) {
            detailsView.getBuffer().setText("Failed to resolve selected row index.");
            return;
        }

        if (rowIndex >= visibleRows.length) {
            clearSelectionDetails();
            detailsView.getBuffer().setText("Selected row is outside visible data range.");
            return;
        }

        auto row = visibleRows[rowIndex];
        selectedSha1 = row.sha1;
        selectedFileName = row.primaryFileName;
        auto detailsText = format(
            "Selected Row Details\n\n" ~
            "Index: %s\n" ~
            "Primary file: %s\n" ~
            "All file references: %s\n" ~
            "File size: %s bytes\n" ~
            "File references: %s\n" ~
            "Media types: video=%s | audio=%s | image=%s | text=%s\n" ~
            "Checksum set: %s\n" ~
            "MD5 (base64): %s\n" ~
            "MD5 (hex): %s\n" ~
            "SHA1 (base64): %s\n" ~
            "SHA1 (hex): %s\n" ~
            "xxh64 (base64): %s\n" ~
            "xxh64 (hex): %s\n" ~
            "File type: %s\n" ~
            "Has media metadata: %s\n" ~
            "Has archive metadata: %s\n" ~
            "Has torrent metadata: %s\n" ~
            "Loaded source: %s\n" ~
            "\nRaw JSON Object\n\n" ~
            "%s\n",
            idx,
            row.primaryFileName.length > 0 ? row.primaryFileName : "-",
            row.fileNamesSummary.length > 0 ? row.fileNamesSummary : "-",
            row.fileSize,
            row.fileCount,
            row.hasVideo ? "yes" : "no",
            row.hasAudio ? "yes" : "no",
            row.hasImage ? "yes" : "no",
            row.hasText ? "yes" : "no",
            checksumSetStatus(row),
            row.md5.length > 0 ? row.md5 : "-",
            digestBase64ToHex(row.md5),
            row.sha1.length > 0 ? row.sha1 : "-",
            digestBase64ToHex(row.sha1),
            row.xxh64.length > 0 ? row.xxh64 : "-",
            digestBase64ToHex(row.xxh64),
            row.fileType.length > 0 ? row.fileType : "-",
            row.hasMedia ? "yes" : "no",
            row.hasArchive ? "yes" : "no",
            row.hasTorrent ? "yes" : "no",
            loadedFilePath.length > 0 ? loadedFilePath : "-",
            row.rawJson.length > 0 ? row.rawJson : "{}"
        );
        selectedDetailsText = detailsText;
        btnCopySha1.setSensitive(!isLoading && selectedSha1.length > 0);
        btnCopyFile.setSensitive(!isLoading && selectedFileName.length > 0);
        btnCopyDetails.setSensitive(!isLoading && selectedDetailsText.length > 0);
        detailsView.getBuffer().setText(detailsText);
    }

    /** Copy a selected value into the system clipboard. */
    void copyTextToClipboard(string label, string value) {
        if (value.length == 0) {
            status.setText(format("No %s value available for selected row.", label));
            return;
        }

        auto display = Display.getDefault();
        if (display is null) {
            status.setText("Clipboard unavailable: no active display.");
            return;
        }

        auto clipboard = Clipboard.getDefault(display);
        if (clipboard is null) {
            status.setText("Clipboard unavailable.");
            return;
        }

        clipboard.setText(value, -1);
        status.setText(format("Copied %s to clipboard.", label));
    }

    /** Apply the current text and media filters in a background worker. */
    void applyFilterFromEntry() {
        if (isLoading) {
            status.setText("Background operation in progress. Please wait before filtering.");
            return;
        }

        if (loadedRows.length == 0) {
            status.setText("No loaded rows to filter.");
            return;
        }
        auto query = filterEntry.getText();
        auto caseSensitive = prefCaseSensitiveFilter;
        auto requireVideo = filterVideo.getActive();
        auto requireAudio = filterAudio.getActive();
        auto requireImage = filterImage.getActive();
        auto requireText = filterText.getActive();
        auto sourceRows = loadedRows.dup;
        auto requestId = ++filterRequestId;

        bool hasMediaTypeFilters = requireVideo || requireAudio || requireImage || requireText;

        string mediaFilterSummary() {
            if (!hasMediaTypeFilters) {
                return "";
            }
            auto labels = appender!(string[])();
            if (requireVideo) {
                labels.put("V");
            }
            if (requireAudio) {
                labels.put("A");
            }
            if (requireImage) {
                labels.put("I");
            }
            if (requireText) {
                labels.put("T");
            }
            return labels.data.join(",");
        }

        setLoadingState(true, format("Filtering %s rows ...", sourceRows.length));
        progressBar.setText("Filtering rows ...");

        auto worker = new Thread({
            MonoTime started = MonoTime.currTime;

            AsyncFilterResult result;
            result.query = query;
            result.caseSensitive = caseSensitive;

            try {
                result.filteredRows = filterRowsByText(sourceRows, query, caseSensitive);
                if (hasMediaTypeFilters) {
                    auto mediaFiltered = appender!(BlobRow[])();
                    foreach (row; result.filteredRows) {
                        auto matchesMedia =
                            (requireVideo && row.hasVideo) ||
                            (requireAudio && row.hasAudio) ||
                            (requireImage && row.hasImage) ||
                            (requireText && row.hasText);
                        if (!matchesMedia) {
                            continue;
                        }
                        mediaFiltered.put(row);
                    }
                    result.filteredRows = mediaFiltered.data;
                }
                result.mediaStats = mediaHitStats(result.filteredRows);
            } catch (Exception ex) {
                result.error = ex.msg;
            }

            result.elapsedMs = cast(long) (MonoTime.currTime - started).total!"msecs";

            new Idle({
                if (requestId != filterRequestId) {
                    return false;
                }

                if (result.error.length > 0) {
                    setLoadingState(false, format("Filtering failed: %s", result.error));
                    return false;
                }

                pendingStatusSuffix = format("filter time: %s ms", result.elapsedMs);
                lastFilterElapsedMs = result.elapsedMs;
                updatePerfStatus();
                auto filterLabel = result.query;
                auto mediaSummary = mediaFilterSummary();
                if (mediaSummary.length > 0 && filterLabel.length > 0) {
                    filterLabel = format("%s | media:%s", filterLabel, mediaSummary);
                } else if (mediaSummary.length > 0) {
                    filterLabel = format("media:%s", mediaSummary);
                }
                if (result.mediaStats.length > 0) {
                    if (filterLabel.length > 0) {
                        filterLabel = format("%s | %s", filterLabel, result.mediaStats);
                    } else {
                        filterLabel = result.mediaStats;
                    }
                }
                renderRows(result.filteredRows, filterLabel);
                return false;
            });
        });

        worker.start();
    }

    /** Load and normalize the JSON file currently referenced by the path entry. */
    void loadFromPath() {
        if (isLoading) {
            status.setText("A load is already in progress.");
            return;
        }

        auto filePath = pathEntry.getText();
        if (!exists(filePath)) {
            status.setText(format("File not found: %s", filePath));
            tableStore.clear();
            return;
        }

        auto requestId = ++loadRequestId;
        setLoadingState(true, format("Loading %s ...", filePath));

        auto worker = new Thread({
            MonoTime started = MonoTime.currTime;

            AsyncLoadResult result;
            result.filePath = filePath;

            try {
                setLoadingPhase(requestId, "Reading file from disk ...");
                auto content = readText(filePath);

                setLoadingPhase(requestId, "Parsing JSON structure ...");
                auto parsed = parseJSON(content);

                if (parsed.type == JSONType.object) {
                    result.rootShape = "object";
                    auto keysAcc = appender!(string[])();
                    foreach (key, _; parsed.object) {
                        keysAcc.put(key);
                    }
                    auto keys = keysAcc.data;
                    keys.sort();
                    result.rootKeysSummary = keys.length > 0 ? keys.join(",") : "-";

                    if ("dataVersion" in parsed.object) {
                        auto versionValue = parsed.object["dataVersion"];
                        if (versionValue.type == JSONType.integer) {
                            result.dataVersion = cast(int) versionValue.integer;
                        } else if (versionValue.type == JSONType.uinteger) {
                            result.dataVersion = cast(int) versionValue.uinteger;
                        }
                    }
                } else if (parsed.type == JSONType.array) {
                    result.rootShape = "array";
                    result.rootKeysSummary = "-";
                } else {
                    result.rootShape = "other";
                    result.rootKeysSummary = "-";
                }

                setLoadingPhase(requestId, "Normalizing rows ...");
                result.allRows = extractRowsFromRoot(parsed);

                setLoadingPhase(requestId, "Computing duplicate groups ...");
                result.duplicateGroups = countDuplicateDigestGroups(result.allRows);
            } catch (Exception ex) {
                result.error = ex.msg;
            }

            result.elapsedMs = cast(long) (MonoTime.currTime - started).total!"msecs";

            new Idle({
                if (requestId != loadRequestId) {
                    return false;
                }

                if (result.error.length > 0) {
                    tableStore.clear();
                    loadedRows = [];
                    visibleRows = [];
                    loadedFilePath = "";
                    loadedDataVersion = -1;
                    loadedRootShape = "-";
                    loadedRootKeysSummary = "-";
                    updateFileMetaStatus();
                    pendingLoadElapsedMs = -1;
                    pendingStatusSuffix = "";
                    clearSelectionDetails();
                    setLoadingState(false, format("Failed to parse JSON: %s", result.error));
                    return false;
                }

                loadedDuplicateGroups = result.duplicateGroups;
                loadedRows = result.allRows;
                loadedFilePath = result.filePath;
                loadedDataVersion = result.dataVersion;
                loadedRootShape = result.rootShape.length > 0 ? result.rootShape : "-";
                loadedRootKeysSummary = result.rootKeysSummary.length > 0 ? result.rootKeysSummary : "-";
                updateFileMetaStatus();
                pendingLoadElapsedMs = result.elapsedMs;
                lastLoadElapsedMs = result.elapsedMs;
                updatePerfStatus();

                if (prefAutoApplyFilter && (
                    filterEntry.getText().length > 0 ||
                    filterVideo.getActive() ||
                    filterAudio.getActive() ||
                    filterImage.getActive() ||
                    filterText.getActive()
                )) {
                    applyFilterFromEntry();
                } else {
                    renderRows(loadedRows);
                }
                return false;
            });
        });

        worker.start();
    }

    /** Open a file chooser and load the selected JSON file. */
    void chooseAndLoadPath() {
        if (isLoading) {
            status.setText("A load is already in progress.");
            return;
        }

        auto chooser = new FileChooserDialog(
            "Open JSON",
            window,
            FileChooserAction.OPEN,
            ["_Cancel", "_Open"],
            [ResponseType.CANCEL, ResponseType.ACCEPT]
        );

        auto currentPath = pathEntry.getText();
        if (currentPath.length > 0) {
            chooser.setFilename(currentPath);
        }

        auto response = chooser.run();
        if (response == cast(int) ResponseType.ACCEPT) {
            auto selectedPath = chooser.getFilename();
            if (selectedPath.length > 0) {
                pathEntry.setText(selectedPath);
                loadFromPath();
            }
        }

        chooser.destroy();
    }

    /** Cancel any in-flight background load or filter request. */
    void cancelPendingLoad() {
        if (!isLoading) {
            status.setText("No load in progress.");
            return;
        }

        // Invalidate pending load/filter work and any in-progress batched render.
        ++loadRequestId;
        ++filterRequestId;
        ++renderRequestId;
        pendingLoadElapsedMs = -1;
        pendingStatusSuffix = "";
        setLoadingState(false, "Operation cancelled. Background result will be discarded.");
    }

    /** Show and apply user preferences that affect filtering and layout. */
    void showPreferencesDialog() {
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

        auto optClearWindowGeometry = new CheckButton("Delete saved window positions on save");
        optClearWindowGeometry.setActive(false);

        prefsBox.packStart(optAutoApply, false, false, 0);
        prefsBox.packStart(optCaseSensitive, false, false, 0);
        prefsBox.packStart(optDetailsBelow, false, false, 0);
        prefsBox.packStart(optClearWindowGeometry, false, false, 0);
        contentArea.packStart(prefsBox, true, true, 0);

        dialog.showAll();
        auto response = dialog.run();

        if (response == cast(int) ResponseType.OK) {
            prefAutoApplyFilter = optAutoApply.getActive();
            prefCaseSensitiveFilter = optCaseSensitive.getActive();
            auto oldDetailsBelow = prefDetailsBelow;
            prefDetailsBelow = optDetailsBelow.getActive();
            if (prefDetailsBelow != oldDetailsBelow) {
                applyDetailsPanePreference();
            }
            auto clearGeometry = optClearWindowGeometry.getActive();
            clearSavedWindowGeometryOnExit = clearGeometry;
            persistCurrentState(clearGeometry);
            status.setText(clearGeometry ? "Preferences saved. Stored window positions were deleted." : "Preferences saved.");
        }

        dialog.destroy();
    }

    /** Show the keyboard shortcut overview dialog. */
    void showShortcutsHelp() {
        auto dialog = new MessageDialog(
            window,
            DialogFlags.MODAL,
            MessageType.INFO,
            ButtonsType.CLOSE,
            "Keyboard Shortcuts\n\n" ~
            "Ctrl+O  Open JSON\n" ~
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
    void showAbout() {
        auto dialog = new AboutDialog();
        dialog.setTransientFor(window);
        dialog.setModal(true);
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

    auto fileOpen = new MenuItem((MenuItem _) {
        chooseAndLoadPath();
    }, "_Open JSON", "file.open", true, accelGroup, 'o');

    auto fileReload = new MenuItem((MenuItem _) {
        loadFromPath();
    }, "_Reload", "file.reload", true, accelGroup, 'r');

    auto fileCancelOperation = new MenuItem((MenuItem _) {
        cancelPendingLoad();
    }, "_Cancel Current Operation", "file.cancelOperation", true, accelGroup, 'k');

    auto fileQuit = new MenuItem((MenuItem _) {
        persistCurrentState(clearSavedWindowGeometryOnExit);
        Main.quit();
    }, "_Quit", "file.quit", true, accelGroup, 'q');

    fileMenu.append(fileOpen);
    fileMenu.append(fileReload);
    fileMenu.append(fileCancelOperation);
    fileMenu.append(new SeparatorMenuItem());
    fileMenu.append(fileQuit);
    menuBar.append(fileMenuItem);

    auto editMenuItem = new MenuItem("_Edit");
    auto editMenu = new Menu();
    editMenuItem.setSubmenu(editMenu);

    auto editApplyFilter = new MenuItem((MenuItem _) {
        applyFilterFromEntry();
    }, "_Apply Filter", "edit.applyFilter", true, accelGroup, 'f');

    auto editClearFilter = new MenuItem((MenuItem _) {
        filterEntry.setText("");
        filterVideo.setActive(false);
        filterAudio.setActive(false);
        filterImage.setActive(false);
        filterText.setActive(false);
        renderRows(loadedRows);
    }, "C_lear Filter", "edit.clearFilter", true, accelGroup, 'l');

    auto editPreferences = new MenuItem((MenuItem _) {
        showPreferencesDialog();
    }, "_Preferences", "edit.preferences", true, accelGroup, ',');

    auto editResetMetrics = new MenuItem((MenuItem _) {
        resetPerfMetrics();
    }, "_Reset Metrics", "edit.resetMetrics", true, accelGroup, 'm');

    editMenu.append(editApplyFilter);
    editMenu.append(editClearFilter);
    editMenu.append(new SeparatorMenuItem());
    editMenu.append(editResetMetrics);
    editMenu.append(editPreferences);
    menuBar.append(editMenuItem);

    auto helpMenuItem = new MenuItem("_Help");
    auto helpMenu = new Menu();
    helpMenuItem.setSubmenu(helpMenu);

    auto helpShortcuts = new MenuItem((MenuItem _) {
        showShortcutsHelp();
    }, "_Keyboard Shortcuts", true);

    auto helpAbout = new MenuItem((MenuItem _) {
        showAbout();
    }, "_About", true);

    helpMenu.append(helpShortcuts);
    helpMenu.append(new SeparatorMenuItem());
    helpMenu.append(helpAbout);
    menuBar.append(helpMenuItem);

    btnLoad.addOnClicked((Button _) {
        loadFromPath();
    });

    btnReload.addOnClicked((Button _) {
        loadFromPath();
    });

    btnCancelLoad.addOnClicked((Button _) {
        cancelPendingLoad();
    });

    btnApplyFilter.addOnClicked((Button _) {
        applyFilterFromEntry();
    });

    btnClearFilter.addOnClicked((Button _) {
        filterEntry.setText("");
        filterVideo.setActive(false);
        filterAudio.setActive(false);
        filterImage.setActive(false);
        filterText.setActive(false);
        renderRows(loadedRows);
    });

    btnCopySha1.addOnClicked((Button _) {
        copyTextToClipboard("SHA1", selectedSha1);
    });

    btnCopyFile.addOnClicked((Button _) {
        copyTextToClipboard("file name", selectedFileName);
    });

    btnCopyDetails.addOnClicked((Button _) {
        copyTextToClipboard("details", selectedDetailsText);
    });

    pathEntry.addOnActivate((Entry _) {
        loadFromPath();
    });

    filterEntry.addOnActivate((Entry _) {
        applyFilterFromEntry();
    });

    filterVideo.addOnToggled((ToggleButton _) {
        applyFilterFromEntry();
    });

    filterAudio.addOnToggled((ToggleButton _) {
        applyFilterFromEntry();
    });

    filterImage.addOnToggled((ToggleButton _) {
        applyFilterFromEntry();
    });

    filterText.addOnToggled((ToggleButton _) {
        applyFilterFromEntry();
    });

    tableView.getSelection().addOnChanged((TreeSelection _) {
        updateSelectedRowDetails();
    });

    window.addOnDestroy((Widget _) {
        persistCurrentState(clearSavedWindowGeometryOnExit);
        Main.quit();
    });

    window.addOnConfigure((GdkEventConfigure* event, Widget _) {
        if (event !is null && event.width > 0 && event.height > 0) {
            lastKnownWindowWidth = event.width;
            lastKnownWindowHeight = event.height;
            appendRestoreLog(format(
                "configure width=%s height=%s runtimePersistence=%s",
                event.width,
                event.height,
                allowRuntimeStatePersistence ? "on" : "off"
            ));
        }
        return false;
    });

    window.addOnSizeAllocate((allocation, Widget _) {
        if (allocation.width > 0 && allocation.height > 0) {
            lastKnownWindowWidth = allocation.width;
            lastKnownWindowHeight = allocation.height;

            if (startupSizeAllocateLogCount < 8) {
                ++startupSizeAllocateLogCount;
                appendRestoreLog(format(
                    "size-allocate[%s] width=%s height=%s runtimePersistence=%s",
                    startupSizeAllocateLogCount,
                    allocation.width,
                    allocation.height,
                    allowRuntimeStatePersistence ? "on" : "off"
                ));
            }

            // Persist size shortly after resize settles, independent of quit path.
            if (allowRuntimeStatePersistence) {
                if (windowSizePersistTimer !is null) {
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

    content.packStart(separator, false, false, 0);
    content.packStart(toolbar, false, false, 0);
    content.packStart(split, true, true, 0);
    content.packStart(rowDetails, false, false, 0);
    content.packStart(status, false, false, 0);
    content.packStart(perfStatus, false, false, 0);
    content.packStart(fileMetaStatus, false, false, 0);

    root.packStart(menuBar, false, false, 0);
    root.packStart(content, true, true, 0);

    window.add(root);
    window.showAll();
    appendRestoreLog(format(
        "startup loaded hasWindowSize=%s width=%s height=%s splitH=%s splitV=%s prefDetailsBelow=%s",
        loadedState.hasWindowSize ? "true" : "false",
        loadedState.windowWidth,
        loadedState.windowHeight,
        loadedState.splitPositionHorizontal,
        loadedState.splitPositionVertical,
        loadedState.prefDetailsBelow ? "true" : "false"
    ));

    if (loadedState.hasWindowSize) {
        auto restoredWidth = loadedState.windowWidth;
        auto restoredHeight = loadedState.windowHeight;

        if (restoredWidth < 640) {
            restoredWidth = 640;
        }
        if (restoredHeight < 400) {
            restoredHeight = 400;
        }

        // Initial apply right after widgets are visible.
        new Idle({
            appendRestoreLog(format("apply idle width=%s height=%s", restoredWidth, restoredHeight));
            window.setDefaultSize(restoredWidth, restoredHeight);
            window.resize(restoredWidth, restoredHeight);
            lastKnownWindowWidth = restoredWidth;
            lastKnownWindowHeight = restoredHeight;
            return false;
        });

        // XFCE can apply its own first configure cycle after map; enforce once more.
        new Timeout(120, {
            appendRestoreLog(format("apply t120 width=%s height=%s", restoredWidth, restoredHeight));
            window.setDefaultSize(restoredWidth, restoredHeight);
            window.resize(restoredWidth, restoredHeight);
            lastKnownWindowWidth = restoredWidth;
            lastKnownWindowHeight = restoredHeight;
            return false;
        });

        // Second delayed pass to win late WM adjustments.
        new Timeout(320, {
            appendRestoreLog(format("apply t320 width=%s height=%s", restoredWidth, restoredHeight));
            window.setDefaultSize(restoredWidth, restoredHeight);
            window.resize(restoredWidth, restoredHeight);
            lastKnownWindowWidth = restoredWidth;
            lastKnownWindowHeight = restoredHeight;
            return false;
        });

        // Some WMs settle size after initial composition; enforce a final pass.
        new Timeout(700, {
            appendRestoreLog(format("apply t700 width=%s height=%s", restoredWidth, restoredHeight));
            window.setDefaultSize(restoredWidth, restoredHeight);
            window.resize(restoredWidth, restoredHeight);
            lastKnownWindowWidth = restoredWidth;
            lastKnownWindowHeight = restoredHeight;
            return false;
        });

        // Final late pass to override very late WM/session adjustments.
        new Timeout(1500, {
            appendRestoreLog(format("apply t1500 width=%s height=%s", restoredWidth, restoredHeight));
            window.setDefaultSize(restoredWidth, restoredHeight);
            window.resize(restoredWidth, restoredHeight);
            lastKnownWindowWidth = restoredWidth;
            lastKnownWindowHeight = restoredHeight;
            allowRuntimeStatePersistence = true;
            persistCurrentState(clearSavedWindowGeometryOnExit);
            appendRestoreLog(format(
                "finalized width=%s height=%s persistedWidth=%s persistedHeight=%s",
                window.getAllocatedWidth(),
                window.getAllocatedHeight(),
                lastKnownWindowWidth,
                lastKnownWindowHeight
            ));
            return false;
        });
    } else {
        allowRuntimeStatePersistence = true;
    }

    if (cli.loadOnStart) {
        loadFromPath();
    }

    Main.run();
    // Fallback persistence for quit paths that may bypass window destroy.
    persistCurrentState(clearSavedWindowGeometryOnExit);
    return 0;
}
