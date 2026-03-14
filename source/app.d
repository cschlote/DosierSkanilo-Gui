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
import gtk.AboutDialog;
import gtk.MessageDialog;
import gtk.c.types : Orientation, DialogFlags, ResponseType, ButtonsType, MessageType;
import glib.Idle;
import glib.Timeout;
import gobject.Type : GType;

import core.thread : Thread;
import core.time : MonoTime;
import std.file : exists, readText;
import std.format : format;
import std.json : parseJSON;
import std.conv : to;
import std.getopt : getopt, config;
import std.stdio : writeln;

import io.dosierjson : extractRowsFromRoot;
import model.blobrow : BlobRow;
import view.textreport : countDuplicateDigestGroups, filterDuplicateRows, filterRowsByText;

enum string DEFAULT_JSON_PATH = "./.filescanner.json";

enum int COL_INDEX = 0;
enum int COL_FILE_SIZE = 1;
enum int COL_FILE_COUNT = 2;
enum int COL_HAS_MEDIA = 3;
enum int COL_SHA1 = 4;
enum int COL_FILE_NAME = 5;
enum int COL_COUNT = 6;

/** Parsed startup options from command-line arguments. */
struct CliOptions {
    string jsonPath = DEFAULT_JSON_PATH;
    bool jsonPathProvided;
    bool loadOnStart;
    bool duplicatesOnStart;
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
    bool duplicatesOnly;
    string error;
    long elapsedMs;
}

/** Worker result payload for background text filtering. */
struct AsyncFilterResult {
    BlobRow[] filteredRows;
    string query;
    bool caseSensitive;
    string error;
    long elapsedMs;
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
        "  -d, --duplicates          Load duplicate-only view on startup\n" ~
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
        "d|duplicates", &opts.duplicatesOnStart,
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
    void addTextColumn(string title, int modelColumn) {
        auto renderer = new CellRendererText();
        auto column = new TreeViewColumn();
        column.setTitle(title);
        column.packStart(renderer, true);
        column.addAttribute(renderer, "text", modelColumn);
        column.setSortColumnId(modelColumn);
        column.setResizable(true);
        column.setClickable(true);
        treeView.appendColumn(column);
    }

    addTextColumn("#", COL_INDEX);
    addTextColumn("Size", COL_FILE_SIZE);
    addTextColumn("Files", COL_FILE_COUNT);
    addTextColumn("Media", COL_HAS_MEDIA);
    addTextColumn("SHA1 (base64)", COL_SHA1);
    addTextColumn("Primary file", COL_FILE_NAME);

    treeView.setHeadersClickable(true);
}

/** Populate GTK list store with projected blob rows.
 *
 * Params:
 *   store = destination list model
 *   rows = normalized rows to append
 */
void populateTableRows(ListStore store, const(BlobRow)[] rows) {
    store.clear();

    foreach (idx, row; rows) {
        auto indexText = to!string(idx + 1);
        auto sizeText = to!string(row.fileSize);
        auto filesText = to!string(row.fileCount);
        auto mediaText = row.hasMedia ? "yes" : "no";
        auto shaText = row.sha1.length > 0 ? row.sha1 : "-";
        auto fileText = row.primaryFileName.length > 0 ? row.primaryFileName : "-";

        TreeIter iter;
        store.append(iter);
        store.set(
            iter,
            [COL_INDEX, COL_FILE_SIZE, COL_FILE_COUNT, COL_HAS_MEDIA, COL_SHA1, COL_FILE_NAME],
            [indexText, sizeText, filesText, mediaText, shaText, fileText]
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

    Main.init(args);

    auto window = new Window("DosierSkanilo GUI");
    window.setDefaultSize(960, 640);
    window.addOnDestroy((Widget _) {
        Main.quit();
    });

    auto accelGroup = new AccelGroup();
    window.addAccelGroup(accelGroup);

    auto root = new Box(Orientation.VERTICAL, 0);

    auto content = new Box(Orientation.VERTICAL, 10);
    content.setBorderWidth(10);

    auto title = new Label("DosierSkanilo Datafile Viewer");
    title.setXalign(0.0f);

    auto subtitle = new Label("Classic GTK shell with menus, shortcuts, preferences, and help.\n");
    subtitle.setXalign(0.0f);

    auto separator = new Separator(Orientation.HORIZONTAL);

    auto toolbar = new Box(Orientation.HORIZONTAL, 8);
    auto pathEntry = new Entry();
    pathEntry.setHexpand(true);
    pathEntry.setText(DEFAULT_JSON_PATH);

    auto btnLoad = new Button("Load JSON");
    auto btnLoadDupes = new Button("Load Duplicates Only");
    auto btnReload = new Button("Reload");
    auto btnCancelLoad = new Button("Cancel");
    btnCancelLoad.setSensitive(false);
    auto loadSpinner = new Spinner();
    loadSpinner.setVisible(false);

    auto filterEntry = new Entry();
    filterEntry.setHexpand(true);
    filterEntry.setPlaceholderText("Filter by filename or SHA1...");

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
    toolbar.packStart(btnLoadDupes, false, false, 0);
    toolbar.packStart(btnReload, false, false, 0);
    toolbar.packStart(btnCancelLoad, false, false, 0);
    toolbar.packStart(loadSpinner, false, false, 0);
    toolbar.packStart(filterEntry, true, true, 0);
    toolbar.packStart(btnApplyFilter, false, false, 0);
    toolbar.packStart(btnClearFilter, false, false, 0);
    toolbar.packStart(progressBar, true, true, 0);

    auto tableStore = new ListStore([
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
    detailsView.getBuffer().setText("No row selected.");

    auto detailsScroll = new ScrolledWindow(null, null);
    detailsScroll.setVexpand(true);
    detailsScroll.setHexpand(true);
    detailsScroll.add(detailsView);

    auto split = new Paned(Orientation.HORIZONTAL);
    split.add1(scroll);
    split.add2(detailsScroll);
    split.setPosition(720);

    auto status = new Label("Ready.");
    status.setXalign(0.0f);

    auto perfStatus = new Label("Timings: load=- ms | filter=- ms | render=- ms");
    perfStatus.setXalign(0.0f);

    auto rowDetails = new Label("Selection: none");
    rowDetails.setXalign(0.0f);

    BlobRow[] loadedRows;
    BlobRow[] visibleRows;
    string loadedFilePath;
    size_t loadedDuplicateGroups;
    bool loadedDuplicatesOnly;

    bool prefDefaultDuplicatesOnly = false;
    bool prefAutoApplyFilter = true;
    bool prefCaseSensitiveFilter = false;
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

    string formatTimingValue(long valueMs) {
        return valueMs >= 0 ? format("%s", valueMs) : "-";
    }

    void updatePerfStatus() {
        perfStatus.setText(format(
            "Timings: load=%s ms | filter=%s ms | render=%s ms",
            formatTimingValue(lastLoadElapsedMs),
            formatTimingValue(lastFilterElapsedMs),
            formatTimingValue(lastRenderElapsedMs)
        ));
    }

    void setLoadingState(bool loading, string message = "") {
        isLoading = loading;

        pathEntry.setSensitive(!loading);
        btnLoad.setSensitive(!loading);
        btnLoadDupes.setSensitive(!loading);
        btnReload.setSensitive(!loading);
        btnCancelLoad.setSensitive(loading);
        filterEntry.setSensitive(!loading);
        btnApplyFilter.setSensitive(!loading);
        btnClearFilter.setSensitive(!loading);

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

    void resetPerfMetrics() {
        lastLoadElapsedMs = -1;
        lastFilterElapsedMs = -1;
        lastRenderElapsedMs = -1;
        updatePerfStatus();
        status.setText("Performance metrics reset.");
    }

    void renderRows(const(BlobRow)[] rows, string filterLabel = "") {
        if (loadedFilePath.length == 0) {
            tableStore.clear();
            visibleRows = [];
            rowDetails.setText("Selection: none");
            detailsView.getBuffer().setText("No row selected.");
            status.setText("Ready.");
            return;
        }

        auto rowsCopy = rows.dup;
        MonoTime renderStarted = MonoTime.currTime;
        auto localRenderRequestId = ++renderRequestId;
        enum size_t RENDER_BATCH_SIZE = 500;

        tableStore.clear();
        visibleRows = [];
        rowDetails.setText("Selection: none");
        detailsView.getBuffer().setText("No row selected.");

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
                auto filesText = to!string(row.fileCount);
                auto mediaText = row.hasMedia ? "yes" : "no";
                auto shaText = row.sha1.length > 0 ? row.sha1 : "-";
                auto fileText = row.primaryFileName.length > 0 ? row.primaryFileName : "-";

                TreeIter iter;
                tableStore.append(iter);
                tableStore.set(
                    iter,
                    [COL_INDEX, COL_FILE_SIZE, COL_FILE_COUNT, COL_HAS_MEDIA, COL_SHA1, COL_FILE_NAME],
                    [indexText, sizeText, filesText, mediaText, shaText, fileText]
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
            auto mode = loadedDuplicatesOnly ? "duplicates" : "all";
            string baseStatus;
            if (filterLabel.length > 0) {
                baseStatus = format(
                    "Showing %s/%s rows (%s mode, duplicate digest groups: %s, filter: %s, case-sensitive: %s)",
                    rowsCopy.length,
                    loadedRows.length,
                    mode,
                    loadedDuplicateGroups,
                    filterLabel,
                    prefCaseSensitiveFilter ? "yes" : "no"
                );
            } else {
                baseStatus = format(
                    "Showing %s/%s rows (%s mode, duplicate digest groups: %s)",
                    rowsCopy.length,
                    loadedRows.length,
                    mode,
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

    void updateSelectedRowDetails() {
        TreeModelIF model;
        TreeIter iter;
        auto selection = tableView.getSelection();
        if (!selection.getSelected(model, iter)) {
            rowDetails.setText("Selection: none");
            detailsView.getBuffer().setText("No row selected.");
            return;
        }

        auto idx = model.getValueString(iter, COL_INDEX);
        auto size = model.getValueString(iter, COL_FILE_SIZE);
        auto files = model.getValueString(iter, COL_FILE_COUNT);
        auto media = model.getValueString(iter, COL_HAS_MEDIA);
        auto fileName = model.getValueString(iter, COL_FILE_NAME);
        rowDetails.setText(format(
            "Selection: #%s | size=%s | files=%s | media=%s | file=%s",
            idx,
            size,
            files,
            media,
            fileName
        ));

        size_t rowIndex = 0;
        try {
            rowIndex = to!size_t(idx) - 1;
        } catch (Exception) {
            detailsView.getBuffer().setText("Failed to resolve selected row index.");
            return;
        }

        if (rowIndex >= visibleRows.length) {
            detailsView.getBuffer().setText("Selected row is outside visible data range.");
            return;
        }

        auto row = visibleRows[rowIndex];
        auto detailsText = format(
            "Selected Row Details\n\n" ~
            "Index: %s\n" ~
            "Primary file: %s\n" ~
            "File size: %s bytes\n" ~
            "File references: %s\n" ~
            "SHA1 (base64): %s\n" ~
            "File type: %s\n" ~
            "Has media metadata: %s\n" ~
            "Loaded source: %s\n",
            idx,
            row.primaryFileName.length > 0 ? row.primaryFileName : "-",
            row.fileSize,
            row.fileCount,
            row.sha1.length > 0 ? row.sha1 : "-",
            row.fileType.length > 0 ? row.fileType : "-",
            row.hasMedia ? "yes" : "no",
            loadedFilePath.length > 0 ? loadedFilePath : "-"
        );
        detailsView.getBuffer().setText(detailsText);
    }

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
        auto sourceRows = loadedRows.dup;
        auto requestId = ++filterRequestId;

        setLoadingState(true, format("Filtering %s rows ...", sourceRows.length));

        auto worker = new Thread({
            MonoTime started = MonoTime.currTime;

            AsyncFilterResult result;
            result.query = query;
            result.caseSensitive = caseSensitive;

            try {
                result.filteredRows = filterRowsByText(sourceRows, query, caseSensitive);
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
                renderRows(result.filteredRows, result.query);
                return false;
            });
        });

        worker.start();
    }

    void loadFromPath(bool duplicatesOnly = false) {
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
            result.duplicatesOnly = duplicatesOnly;

            try {
                setLoadingPhase(requestId, "Reading file from disk ...");
                auto content = readText(filePath);

                setLoadingPhase(requestId, "Parsing JSON structure ...");
                auto parsed = parseJSON(content);

                setLoadingPhase(requestId, "Normalizing rows ...");
                result.allRows = extractRowsFromRoot(parsed);

                setLoadingPhase(requestId, "Computing duplicate groups ...");
                result.duplicateGroups = countDuplicateDigestGroups(result.allRows);
            } catch (Exception ex) {
                result.error = ex.msg;
            }
    progressBar.setText("Filtering rows ...");

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
                    pendingLoadElapsedMs = -1;
                    pendingStatusSuffix = "";
                    rowDetails.setText("Selection: none");
                    detailsView.getBuffer().setText("No row selected.");
                    setLoadingState(false, format("Failed to parse JSON: %s", result.error));
                    return false;
                }

                loadedDuplicateGroups = result.duplicateGroups;
                loadedRows = result.duplicatesOnly ? filterDuplicateRows(result.allRows) : result.allRows;
                loadedFilePath = result.filePath;
                loadedDuplicatesOnly = result.duplicatesOnly;
                pendingLoadElapsedMs = result.elapsedMs;
                lastLoadElapsedMs = result.elapsedMs;
                updatePerfStatus();

                if (prefAutoApplyFilter && filterEntry.getText().length > 0) {
                    applyFilterFromEntry();
                } else {
                    renderRows(loadedRows);
                }
                return false;
            });
        });

        worker.start();
    }

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

        auto optDefaultDupes = new CheckButton("Start normal loads in duplicate-only mode");
        optDefaultDupes.setActive(prefDefaultDuplicatesOnly);

        auto optAutoApply = new CheckButton("Auto-apply filter after load/reload");
        optAutoApply.setActive(prefAutoApplyFilter);

        auto optCaseSensitive = new CheckButton("Case-sensitive text filtering");
        optCaseSensitive.setActive(prefCaseSensitiveFilter);

        prefsBox.packStart(optDefaultDupes, false, false, 0);
        prefsBox.packStart(optAutoApply, false, false, 0);
        prefsBox.packStart(optCaseSensitive, false, false, 0);
        contentArea.packStart(prefsBox, true, true, 0);

        dialog.showAll();
        auto response = dialog.run();

        if (response == cast(int) ResponseType.OK) {
            prefDefaultDuplicatesOnly = optDefaultDupes.getActive();
            prefAutoApplyFilter = optAutoApply.getActive();
            prefCaseSensitiveFilter = optCaseSensitive.getActive();
            status.setText("Preferences saved.");
        }

        dialog.destroy();
    }

    void showShortcutsHelp() {
        auto dialog = new MessageDialog(
            window,
            DialogFlags.MODAL,
            MessageType.INFO,
            ButtonsType.CLOSE,
            "Keyboard Shortcuts\n\n" ~
            "Ctrl+O  Open JSON\n" ~
            "Ctrl+D  Open Duplicates Only\n" ~
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

    void showAbout() {
        auto dialog = new AboutDialog();
        dialog.setTransientFor(window);
        dialog.setModal(true);
        dialog.setProgramName("DosierSkanilo GUI");
        dialog.setVersion("0.1.0");
        dialog.setComments("Classic GTK desktop frontend for DosierSkanilo JSON data files.");
        dialog.setAuthors(["Carsten Schlote"]);
        dialog.run();
        dialog.destroy();
    }

    auto fileMenuItem = new MenuItem("_File");
    auto fileMenu = new Menu();
    fileMenuItem.setSubmenu(fileMenu);

    auto fileOpen = new MenuItem((MenuItem _) {
        loadFromPath(prefDefaultDuplicatesOnly);
    }, "_Open JSON", "file.open", true, accelGroup, 'o');

    auto fileOpenDupes = new MenuItem((MenuItem _) {
        loadFromPath(true);
    }, "Open _Duplicates Only", "file.open.dupes", true, accelGroup, 'd');

    auto fileReload = new MenuItem((MenuItem _) {
        loadFromPath(loadedDuplicatesOnly);
    }, "_Reload", "file.reload", true, accelGroup, 'r');

    auto fileCancelOperation = new MenuItem((MenuItem _) {
        cancelPendingLoad();
    }, "_Cancel Current Operation", "file.cancelOperation", true, accelGroup, 'k');

    auto fileQuit = new MenuItem((MenuItem _) {
        Main.quit();
    }, "_Quit", "file.quit", true, accelGroup, 'q');

    fileMenu.append(fileOpen);
    fileMenu.append(fileOpenDupes);
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
        loadFromPath(prefDefaultDuplicatesOnly);
    });

    btnLoadDupes.addOnClicked((Button _) {
        loadFromPath(true);
    });

    btnReload.addOnClicked((Button _) {
        loadFromPath(loadedDuplicatesOnly);
    });

    btnCancelLoad.addOnClicked((Button _) {
        cancelPendingLoad();
    });

    btnApplyFilter.addOnClicked((Button _) {
        applyFilterFromEntry();
    });

    btnClearFilter.addOnClicked((Button _) {
        filterEntry.setText("");
        renderRows(loadedRows);
    });

    pathEntry.addOnActivate((Entry _) {
        loadFromPath(prefDefaultDuplicatesOnly);
    });

    filterEntry.addOnActivate((Entry _) {
        applyFilterFromEntry();
    });

    tableView.getSelection().addOnChanged((TreeSelection _) {
        updateSelectedRowDetails();
    });

    content.packStart(title, false, false, 0);
    content.packStart(subtitle, false, false, 0);
    content.packStart(separator, false, false, 0);
    content.packStart(toolbar, false, false, 0);
    content.packStart(split, true, true, 0);
    content.packStart(rowDetails, false, false, 0);
    content.packStart(status, false, false, 0);
    content.packStart(perfStatus, false, false, 0);

    root.packStart(menuBar, false, false, 0);
    root.packStart(content, true, true, 0);

    window.add(root);
    window.showAll();

    if (cli.loadOnStart) {
        loadFromPath(cli.duplicatesOnStart || prefDefaultDuplicatesOnly);
    }

    Main.run();
    return 0;
}
