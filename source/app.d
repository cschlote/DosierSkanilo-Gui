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
import gtk.c.types : Orientation, DialogFlags, ResponseType, ButtonsType, MessageType, FileChooserAction;
import glib.Idle;
import glib.Timeout;
import gobject.Type : GType;
import gtk.Clipboard;
import gdk.Display;

import core.thread : Thread;
import core.time : MonoTime;
import std.file : exists, readText;
import std.format : format;
import std.json : parseJSON, JSONType;
import std.base64 : Base64;
import std.conv : to;
import std.getopt : getopt, config;
import std.stdio : writeln;
import std.array : appender;
import std.algorithm : sort;
import std.string : join;

import io.dosierjson : extractRowsFromRoot;
import model.blobrow : BlobRow;
import view.textreport : countDuplicateDigestGroups, filterDuplicateRows, filterRowsByText;

enum string DEFAULT_JSON_PATH = "./.filescanner.json";

enum int COL_INDEX = 0;
enum int COL_FILE_SIZE = 1;
enum int COL_FILE_COUNT = 2;
enum int COL_MEDIA_VIDEO = 3;
enum int COL_MEDIA_AUDIO = 4;
enum int COL_MEDIA_IMAGE = 5;
enum int COL_MEDIA_TEXT = 6;
enum int COL_HAS_ARCHIVE = 7;
enum int COL_HAS_TORRENT = 8;
enum int COL_CHECKSUM_SET = 9;
enum int COL_FILE_NAME = 10;
enum int COL_INDEX_SORT = 11;
enum int COL_FILE_SIZE_SORT = 12;
enum int COL_FILE_COUNT_SORT = 13;
enum int COL_COUNT = 14;

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
    void addTextColumn(string title, int modelColumn, int sortColumn = -1) {
        auto renderer = new CellRendererText();
        auto column = new TreeViewColumn();
        column.setTitle(title);
        column.packStart(renderer, true);
        column.addAttribute(renderer, "text", modelColumn);
        column.setSortColumnId(sortColumn >= 0 ? sortColumn : modelColumn);
        column.setResizable(true);
        column.setClickable(true);
        treeView.appendColumn(column);
    }

    addTextColumn("#", COL_INDEX, COL_INDEX_SORT);
    addTextColumn("Size", COL_FILE_SIZE, COL_FILE_SIZE_SORT);
    addTextColumn("Files", COL_FILE_COUNT, COL_FILE_COUNT_SORT);
    addTextColumn("Video", COL_MEDIA_VIDEO);
    addTextColumn("Audio", COL_MEDIA_AUDIO);
    addTextColumn("Image", COL_MEDIA_IMAGE);
    addTextColumn("Text", COL_MEDIA_TEXT);
    addTextColumn("Archive", COL_HAS_ARCHIVE);
    addTextColumn("Torrent", COL_HAS_TORRENT);
    addTextColumn("Checksums", COL_CHECKSUM_SET);
    addTextColumn("Primary file", COL_FILE_NAME);

    treeView.setHeadersClickable(true);
}

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

string boolStatusIcon(bool value) {
    return value ? "🟢✓" : "🔴✗";
}

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
        auto filesText = to!string(row.fileCount);
        auto videoText = boolStatusIcon(row.hasVideo);
        auto audioText = boolStatusIcon(row.hasAudio);
        auto imageText = boolStatusIcon(row.hasImage);
        auto textText = boolStatusIcon(row.hasText);
        auto archiveText = boolStatusIcon(row.hasArchive);
        auto torrentText = boolStatusIcon(row.hasTorrent);
        auto checksumsText = checksumSetStatus(row);
        auto fileText = row.primaryFileName.length > 0 ? row.primaryFileName : "-";

        TreeIter iter;
        store.append(iter);
        store.set(
            iter,
            [
                COL_INDEX,
                COL_FILE_SIZE,
                COL_FILE_COUNT,
                COL_MEDIA_VIDEO,
                COL_MEDIA_AUDIO,
                COL_MEDIA_IMAGE,
                COL_MEDIA_TEXT,
                COL_HAS_ARCHIVE,
                COL_HAS_TORRENT,
                COL_CHECKSUM_SET,
                COL_FILE_NAME,
                COL_INDEX_SORT,
                COL_FILE_SIZE_SORT,
                COL_FILE_COUNT_SORT
            ],
            [
                indexText,
                sizeText,
                filesText,
                videoText,
                audioText,
                imageText,
                textText,
                archiveText,
                torrentText,
                checksumsText,
                fileText,
                numericSortKey(to!ulong(idx + 1)),
                numericSortKey(row.fileSize),
                numericSortKey(to!ulong(row.fileCount))
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
    toolbar.packStart(btnLoadDupes, false, false, 0);
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
    split.add1(scroll);
    split.add2(detailsPane);
    split.setPosition(720);

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
    bool loadedDuplicatesOnly;
    string selectedSha1;
    string selectedFileName;
    string selectedDetailsText;
    int loadedDataVersion = -1;
    string loadedRootShape = "-";
    string loadedRootKeysSummary = "-";

    bool prefDefaultDuplicatesOnly = false;
    bool prefAutoApplyFilter = true;
    bool prefCaseSensitiveFilter = false;
    bool prefDetailsBelow;
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

    void updateFileMetaStatus() {
        auto dataVersionText = loadedDataVersion >= 0 ? to!string(loadedDataVersion) : "-";
        fileMetaStatus.setText(format(
            "File metadata: version=%s | root=%s | keys=%s",
            dataVersionText,
            loadedRootShape,
            loadedRootKeysSummary
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

    void clearSelectionDetails() {
        selectedSha1 = "";
        selectedFileName = "";
        selectedDetailsText = "";
        btnCopySha1.setSensitive(false);
        btnCopyFile.setSensitive(false);
        btnCopyDetails.setSensitive(false);
        rowDetails.setText("Selection: none");
        detailsView.getBuffer().setText("No row selected.");
    }

    void applyDetailsPanePreference() {
        auto orientation = prefDetailsBelow ? Orientation.VERTICAL : Orientation.HORIZONTAL;
        auto splitPosition = prefDetailsBelow ? 420 : 720;

        // Keep the same paned instance and flip orientation in place.
        // Rebuilding/reparenting the children can invalidate GTK widget ownership.
        split.setOrientation(orientation);
        split.setPosition(splitPosition);
    }

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
                auto filesText = to!string(row.fileCount);
                auto videoText = boolStatusIcon(row.hasVideo);
                auto audioText = boolStatusIcon(row.hasAudio);
                auto imageText = boolStatusIcon(row.hasImage);
                auto textText = boolStatusIcon(row.hasText);
                auto archiveText = boolStatusIcon(row.hasArchive);
                auto torrentText = boolStatusIcon(row.hasTorrent);
                auto checksumsText = checksumSetStatus(row);
                auto fileText = row.primaryFileName.length > 0 ? row.primaryFileName : "-";

                auto indexSortText = format("%020d", cast(ulong) idx + 1);
                auto sizeSortText = format("%020d", row.fileSize);
                auto filesSortText = format("%020d", cast(ulong) row.fileCount);

                TreeIter iter;
                tableStore.append(iter);
                tableStore.set(
                    iter,
                    [
                        COL_INDEX,
                        COL_FILE_SIZE,
                        COL_FILE_COUNT,
                        COL_MEDIA_VIDEO,
                        COL_MEDIA_AUDIO,
                        COL_MEDIA_IMAGE,
                        COL_MEDIA_TEXT,
                        COL_HAS_ARCHIVE,
                        COL_HAS_TORRENT,
                        COL_CHECKSUM_SET,
                        COL_FILE_NAME,
                        COL_INDEX_SORT,
                        COL_FILE_SIZE_SORT,
                        COL_FILE_COUNT_SORT
                    ],
                    [
                        indexText,
                        sizeText,
                        filesText,
                        videoText,
                        audioText,
                        imageText,
                        textText,
                        archiveText,
                        torrentText,
                        checksumsText,
                        fileText,
                        indexSortText,
                        sizeSortText,
                        filesSortText
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
            clearSelectionDetails();
            return;
        }

        auto idx = model.getValueString(iter, COL_INDEX);
        auto size = model.getValueString(iter, COL_FILE_SIZE);
        auto files = model.getValueString(iter, COL_FILE_COUNT);
        auto video = model.getValueString(iter, COL_MEDIA_VIDEO);
        auto audio = model.getValueString(iter, COL_MEDIA_AUDIO);
        auto image = model.getValueString(iter, COL_MEDIA_IMAGE);
        auto text = model.getValueString(iter, COL_MEDIA_TEXT);
        auto checksums = model.getValueString(iter, COL_CHECKSUM_SET);
        auto fileName = model.getValueString(iter, COL_FILE_NAME);
        rowDetails.setText(format(
            "Selection: #%s | size=%s | files=%s | V=%s A=%s I=%s T=%s | checksums=%s | file=%s",
            idx,
            size,
            files,
            video,
            audio,
            image,
            text,
            checksums,
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
                        if (requireVideo && !row.hasVideo) {
                            continue;
                        }
                        if (requireAudio && !row.hasAudio) {
                            continue;
                        }
                        if (requireImage && !row.hasImage) {
                            continue;
                        }
                        if (requireText && !row.hasText) {
                            continue;
                        }
                        mediaFiltered.put(row);
                    }
                    result.filteredRows = mediaFiltered.data;
                }
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
                renderRows(result.filteredRows, filterLabel);
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
                loadedRows = result.duplicatesOnly ? filterDuplicateRows(result.allRows) : result.allRows;
                loadedFilePath = result.filePath;
                loadedDuplicatesOnly = result.duplicatesOnly;
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

    void chooseAndLoadPath(bool duplicatesOnly = false) {
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
                loadFromPath(duplicatesOnly);
            }
        }

        chooser.destroy();
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

        auto optDetailsBelow = new CheckButton("Show details below list (instead of on the right)");
        optDetailsBelow.setActive(prefDetailsBelow);

        prefsBox.packStart(optDefaultDupes, false, false, 0);
        prefsBox.packStart(optAutoApply, false, false, 0);
        prefsBox.packStart(optCaseSensitive, false, false, 0);
        prefsBox.packStart(optDetailsBelow, false, false, 0);
        contentArea.packStart(prefsBox, true, true, 0);

        dialog.showAll();
        auto response = dialog.run();

        if (response == cast(int) ResponseType.OK) {
            prefDefaultDuplicatesOnly = optDefaultDupes.getActive();
            prefAutoApplyFilter = optAutoApply.getActive();
            prefCaseSensitiveFilter = optCaseSensitive.getActive();
            auto oldDetailsBelow = prefDetailsBelow;
            prefDetailsBelow = optDetailsBelow.getActive();
            if (prefDetailsBelow != oldDetailsBelow) {
                applyDetailsPanePreference();
            }
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
        dialog.setComments("Desktop frontend for DosierSkanilo.");
        dialog.setAuthors(["Carsten Schlote"]);
        dialog.run();
        dialog.destroy();
    }

    auto fileMenuItem = new MenuItem("_File");
    auto fileMenu = new Menu();
    fileMenuItem.setSubmenu(fileMenu);

    auto fileOpen = new MenuItem((MenuItem _) {
        chooseAndLoadPath(prefDefaultDuplicatesOnly);
    }, "_Open JSON", "file.open", true, accelGroup, 'o');

    auto fileOpenDupes = new MenuItem((MenuItem _) {
        chooseAndLoadPath(true);
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
        loadFromPath(prefDefaultDuplicatesOnly);
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

    if (cli.loadOnStart) {
        loadFromPath(cli.duplicatesOnStart || prefDefaultDuplicatesOnly);
    }

    Main.run();
    return 0;
}
