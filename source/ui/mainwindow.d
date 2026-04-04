/** Main GTK application shell for DosierSkanilo GUI.
 *
 * This module wires together command-line startup options, JSON loading,
 * row-table rendering, and classic desktop menu actions.
 *
 * Authors: DosierSkanilo contributors
 * License: CC-BY-NC-SA 4.0
 */
module ui.mainwindow;

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
import gtk.Grid;
import gtk.Expander;
import gtk.TreeView;
import gtk.ListStore;
import gtk.TreeIter;
import gtk.TreeSelection;
import gtk.TreeModelIF;
import gtk.Paned;
import gtk.Notebook;
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
import gdk.c.types : GdkEventConfigure;

import core.thread : Thread;
import core.time : MonoTime;
import std.file : exists;
import std.format : format;
import std.base64 : Base64;
import std.conv : to;
import std.stdio : writeln;
import std.array : appender;
import std.algorithm : sort;
import std.string : join, replace;
import std.path : baseName;

import cli.commandline : CliOptions, parseCliOptions, cliUsageText;
import io.dosierjson : extractRowsFromBlobs;
import model.blobrow : BlobRow;
import ui.appstate : AppState, loadAppState, saveAppState;
import ui.documenttab : DocumentTab, COL_INDEX, COL_FILE_SIZE, COL_CHECKSUM_SET,
    COL_FILE_TYPE, COL_MEDIA_INFO, COL_HAS_ARCHIVE, COL_HAS_TORRENT,
    COL_INDEX_SORT, COL_FILE_SIZE_SORT;
import ui.detailswidgets : createDetailEntry, createDetailTextView,
    createDetailCaption, setDetailEntry, setEntryMonospace,
    setMetadataStatusLabel, setMetadataDetails, setKnownFilesTable;
import ui.tablecolumns : setTableColumnsResizable, configureTableColumns, configureKnownFilesColumns;
import view.textreport : countDuplicateDigestGroups, filterRowsByText;
import dosierskanilo.model.namedbinaryblob : DATA_CLASS_VERSION2, deserializeDataClassJsonFile;

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

/** Expand the stored filename summary into one line per known file name. */
string stackedFileNames(string fileNamesSummary)
{
    if (fileNamesSummary.length == 0)
    {
        return "-";
    }
    return fileNamesSummary.replace(", ", "\n");
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

/** Count media subtype hits in the currently filtered row set. */
string mediaHitStats(const(BlobRow)[] rows)
{
    size_t videoCount;
    size_t audioCount;
    size_t imageCount;
    size_t textCount;

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
    }

    return format("hits V:%s A:%s I:%s T:%s", videoCount, audioCount, imageCount, textCount);
}

/** Convert a base64-encoded digest into lowercase hexadecimal text. */
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
 *   args = process command-line arguments
 * Returns:
 *   exit code
 */
int runMainWindow(string[] args)
{
    auto cli = parseCliOptions(args);
    if (cli.showHelp)
    {
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
    auto filterMediaNot = new CheckButton("NOT");
    filterMediaNot.setTooltipText("Invert the selected media-type filters");

    auto btnApplyFilter = new Button("Apply Filter");
    auto btnClearFilter = new Button("Clear Filter");

    auto progressBar = new ProgressBar();
    progressBar.setHexpand(true);
    progressBar.setShowText(true);
    progressBar.setText("Idle");
    progressBar.setPulseStep(0.05);
    progressBar.setVisible(false);

    toolbar.packStart(btnReload, false, false, 0);
    toolbar.packStart(btnCancelLoad, false, false, 0);
    toolbar.packStart(loadSpinner, false, false, 0);
    toolbar.packStart(filterEntry, true, true, 0);
    toolbar.packStart(filterVideo, false, false, 0);
    toolbar.packStart(filterAudio, false, false, 0);
    toolbar.packStart(filterImage, false, false, 0);
    toolbar.packStart(filterText, false, false, 0);
    toolbar.packStart(filterMediaNot, false, false, 0);
    toolbar.packStart(btnApplyFilter, false, false, 0);
    toolbar.packStart(btnClearFilter, false, false, 0);
    toolbar.packStart(progressBar, true, true, 0);

    auto notebook = new Notebook();
    notebook.setHexpand(true);
    notebook.setVexpand(true);

    DocumentTab[] documents;
    string[] pendingStartupPaths;
    int pendingStartupSelectIndex = -1;

    bool prefAutoApplyFilter = loadedState.prefAutoApplyFilter;
    bool prefCaseSensitiveFilter = loadedState.prefCaseSensitiveFilter;
    bool prefDetailsBelow = loadedState.prefDetailsBelow;
    bool prefRestoreOpenFiles = loadedState.prefRestoreOpenFiles;
    bool clearSavedWindowGeometryOnExit;
    bool allowRuntimeStatePersistence = !loadedState.hasWindowSize;
    bool isSyncingToolbarState;
    int splitPositionHorizontal = loadedState.splitPositionHorizontal;
    int splitPositionVertical = loadedState.splitPositionVertical;
    int lastKnownWindowWidth = loadedState.windowWidth;
    int lastKnownWindowHeight = loadedState.windowHeight;
    Timeout windowSizePersistTimer;
    bool isLoading;
    DocumentTab busyDocument;
    Timeout progressPulseTimer;

    if (cli.disableAutoFilter)
    {
        prefAutoApplyFilter = false;
    }
    if (cli.caseSensitiveFilter)
    {
        prefCaseSensitiveFilter = true;
    }

    auto menuBar = new MenuBar();

    if (cli.jsonPath.length > 0)
    {
        // pathEntry entfernt
    }
    if (cli.filterOnStart.length > 0)
    {
        filterEntry.setText(cli.filterOnStart);
    }

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

    /** Find an already open document tab by JSON file path. */
    DocumentTab findDocumentByPath(string filePath)
    {
        foreach (document; documents)
        {
            if (document.filePath == filePath)
            {
                return document;
            }
        }
        return null;
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
        syncToolbarSensitivity();
        isSyncingToolbarState = false;
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

        // Während Laden: Spalten-Resizing deaktivieren
        setTableColumnsResizable(document, !loading ? true : false);

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
        setMetadataStatusLabel(document.detailArchiveStatus, "Archive", format("%s unavailable", boolStatusIcon(
                false)));
        setMetadataStatusLabel(document.detailTorrentStatus, "Torrent", format("%s unavailable", boolStatusIcon(
                false)));
        setMetadataDetails(document.detailMediaInfoExpander, document.detailMediaInfoView, "MediaInfo", "");
        setMetadataDetails(document.detailArchiveExpander, document.detailArchiveView, "Archive", "");
        setMetadataDetails(document.detailTorrentExpander, document.detailTorrentView, "Torrent", "");
        setKnownFilesTable(document, "", 0);
        document.btnCopySha1.setSensitive(false);
        document.btnCopyFile.setSensitive(false);
        document.btnCopyDetails.setSensitive(false);
        document.rowDetails.setText("Selection: none");
    }

    /** Keep a document splitter divider within usable visible bounds. */
    int clampSplitPositionToVisibleBounds(Paned splitWidget, Orientation orientation, int requestedPosition)
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
        if (requestedPosition < minPosition)
        {
            return minPosition;
        }
        if (requestedPosition > maxPosition)
        {
            return maxPosition;
        }
        return requestedPosition;
    }

    /** Estimate the natural width required to show the blob list columns without truncating the split too early. */
    int preferredListSplitPosition(DocumentTab document)
    {
        enum int LIST_PADDING = 112;
        enum int MIN_LIST_WIDTH = 420;

        foreach (columnIndex; 0 .. 7)
        {
            auto column = document.tableView.getColumn(columnIndex);
            if (column !is null)
            {
                column.queueResize();
            }
        }
        document.tableView.columnsAutosize();

        int totalWidth = 0;
        foreach (columnIndex; 0 .. 7)
        {
            auto column = document.tableView.getColumn(columnIndex);
            if (column is null || !column.getVisible())
            {
                continue;
            }
            totalWidth += column.getWidth();
        }

        if (totalWidth <= 0)
        {
            return splitPositionHorizontal;
        }

        totalWidth += LIST_PADDING;
        return totalWidth < MIN_LIST_WIDTH ? MIN_LIST_WIDTH : totalWidth;
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
            auto clampedPosition = clampSplitPositionToVisibleBounds(document.split, Orientation.HORIZONTAL, targetPosition);
            document.split.setPosition(clampedPosition);
            splitPositionHorizontal = clampedPosition;

            if (attempt >= 4)
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
        if (orientation == Orientation.HORIZONTAL)
        {
            auto preferredPosition = preferredListSplitPosition(document);
            if (splitPosition < preferredPosition)
            {
                splitPosition = preferredPosition;
            }
        }
        document.split.setOrientation(orientation);

        auto clampedPosition = clampSplitPositionToVisibleBounds(document.split, orientation, splitPosition);
        document.split.setPosition(clampedPosition);
        new Idle({
            auto realizedClamped = clampSplitPositionToVisibleBounds(document.split, orientation, splitPosition);
            document.split.setPosition(realizedClamped);
            if (orientation == Orientation.VERTICAL)
            {
                splitPositionVertical = realizedClamped;
            }
            else
            {
                splitPositionHorizontal = realizedClamped;
                schedulePreferredHorizontalSplit(document);
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
    void delegate(DocumentTab) loadDocument;

    /** Build and wire a new document tab widget hierarchy. */
    DocumentTab createDocumentTab(string filePath)
    {
        auto document = new DocumentTab();
        document.filePath = filePath;

        void attachField(Grid grid, int row, int column, string caption, Entry entry, int entryWidth = 1)
        {
            auto label = createDetailCaption(caption);
            grid.attach(label, column, row, 1, 1);
            grid.attach(entry, column + 1, row, entryWidth, 1);
        }

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

        auto scroll = new ScrolledWindow(null, null);
        scroll.setVexpand(true);
        scroll.setHexpand(true);
        scroll.add(document.tableView);

        document.detailChecksumStatus = new Label("");
        document.detailChecksumStatus.setXalign(0.0f);
        document.detailMediaInfoStatus = new Label("");
        document.detailMediaInfoStatus.setXalign(0.0f);
        document.detailArchiveStatus = new Label("");
        document.detailArchiveStatus.setXalign(0.0f);
        document.detailTorrentStatus = new Label("");
        document.detailTorrentStatus.setXalign(0.0f);

        document.detailChecksumExpander = new Expander("");
        document.detailMediaInfoView = createDetailTextView(true);
        document.detailArchiveView = createDetailTextView(true);
        document.detailTorrentView = createDetailTextView(true);
        document.detailMediaInfoExpander = new Expander("");
        document.detailArchiveExpander = new Expander("");
        document.detailTorrentExpander = new Expander("");
        document.detailChecksumExpander.setLabelWidget(document.detailChecksumStatus);
        document.detailMediaInfoExpander.setLabelWidget(document.detailMediaInfoStatus);
        document.detailArchiveExpander.setLabelWidget(document.detailArchiveStatus);
        document.detailTorrentExpander.setLabelWidget(document.detailTorrentStatus);

        auto checksumGrid = new Grid();
        checksumGrid.setColumnSpacing(10);
        checksumGrid.setRowSpacing(6);

        document.detailSha1HexEntry = createDetailEntry(40);
        document.detailMd5HexEntry = createDetailEntry(40);
        document.detailXxh64HexEntry = createDetailEntry(40);
        setEntryMonospace(document.detailSha1HexEntry);
        setEntryMonospace(document.detailMd5HexEntry);
        setEntryMonospace(document.detailXxh64HexEntry);
        attachField(checksumGrid, 0, 0, "SHA1 (hex)", document.detailSha1HexEntry, 3);
        attachField(checksumGrid, 1, 0, "MD5 (hex)", document.detailMd5HexEntry, 3);
        attachField(checksumGrid, 2, 0, "xxh64 (hex)", document.detailXxh64HexEntry, 3);

        document.detailChecksumExpander.add(checksumGrid);
        document.detailMediaInfoExpander.add(document.detailMediaInfoView);
        document.detailArchiveExpander.add(document.detailArchiveView);
        document.detailTorrentExpander.add(document.detailTorrentView);

        auto detailVisuals = new Box(Orientation.VERTICAL, 4);
        detailVisuals.packStart(document.detailChecksumExpander, false, false, 0);
        detailVisuals.packStart(document.detailMediaInfoExpander, false, false, 0);
        detailVisuals.packStart(document.detailArchiveExpander, false, false, 0);
        detailVisuals.packStart(document.detailTorrentExpander, false, false, 0);

        auto detailGrid = new Grid();
        detailGrid.setColumnSpacing(10);
        detailGrid.setRowSpacing(6);

        document.detailIndexEntry = createDetailEntry(10);
        document.detailSizeEntry = createDetailEntry(14);
        attachField(detailGrid, 0, 0, "Index", document.detailIndexEntry);
        attachField(detailGrid, 0, 2, "File size", document.detailSizeEntry);

        document.detailFileNamesStore = new ListStore([
            GType.STRING, GType.STRING
        ]);
        document.detailFileNamesView = new TreeView(document.detailFileNamesStore);
        configureKnownFilesColumns(document.detailFileNamesView);

        document.detailFileNamesLabel = createDetailCaption("Known file names (0)");

        auto detailsActions = new Box(Orientation.HORIZONTAL, 6);
        document.btnCopySha1 = new Button("Copy SHA1");
        document.btnCopyFile = new Button("Copy File");
        document.btnCopyDetails = new Button("Copy Details");
        document.btnCopySha1.setSensitive(false);
        document.btnCopyFile.setSensitive(false);
        document.btnCopyDetails.setSensitive(false);
        detailsActions.packStart(document.btnCopySha1, false, false, 0);
        detailsActions.packStart(document.btnCopyFile, false, false, 0);
        detailsActions.packStart(document.btnCopyDetails, false, false, 0);

        auto detailsScroll = new ScrolledWindow(null, null);
        detailsScroll.setVexpand(true);
        detailsScroll.setHexpand(true);
        detailsScroll.add(document.detailFileNamesView);

        auto detailsBody = new Box(Orientation.VERTICAL, 10);
        detailsBody.setBorderWidth(6);
        detailsBody.packStart(detailVisuals, false, false, 0);
        detailsBody.packStart(detailGrid, false, false, 0);
        detailsBody.packStart(document.detailFileNamesLabel, false, false, 0);
        detailsBody.packStart(detailsScroll, true, true, 0);

        auto detailsPane = new Box(Orientation.VERTICAL, 6);
        detailsPane.packStart(detailsActions, false, false, 0);
        detailsPane.packStart(detailsBody, true, true, 0);

        document.split = new Paned(Orientation.HORIZONTAL);
        document.split.pack1(scroll, false, true);
        document.split.pack2(detailsPane, true, false);
        document.split.setPosition(splitPositionHorizontal);

        document.rowDetails = new Label("Selection: none");
        document.rowDetails.setXalign(0.0f);
        document.status = new Label(format("Ready: %s", filePath));
        document.status.setXalign(0.0f);
        document.perfStatus = new Label("Timings: load=- ms | filter=- ms | render=- ms");
        document.perfStatus.setXalign(0.0f);
        document.fileMetaStatus = new Label("File metadata: version=- | root=- | keys=-");
        document.fileMetaStatus.setXalign(0.0f);

        document.pageRoot = new Box(Orientation.VERTICAL, 0);
        document.pageRoot.packStart(document.split, true, true, 0);
        document.pageRoot.packStart(document.rowDetails, false, false, 0);
        document.pageRoot.packStart(document.status, false, false, 0);
        document.pageRoot.packStart(document.perfStatus, false, false, 0);
        document.pageRoot.packStart(document.fileMetaStatus, false, false, 0);
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
        }

        state.splitPositionHorizontal = splitPositionHorizontal;
        state.splitPositionVertical = splitPositionVertical;

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

        auto rowsCopy = rows.dup;
        MonoTime renderStarted = MonoTime.currTime;
        auto localRenderRequestId = ++document.renderRequestId;
        enum size_t RENDER_BATCH_SIZE = 500;

        // Performance-Optimierung: TreeView während Bulk-Import abkoppeln
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
                return false;
            }

            auto endIndex = nextIndex + RENDER_BATCH_SIZE;
            if (endIndex > rowsCopy.length)
            {
                endIndex = rowsCopy.length;
            }

            foreach (idx; nextIndex .. endIndex)
            {
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
            if (nextIndex < rowsCopy.length)
            {
                document.status.setText(format("Rendering rows: %s/%s ...", nextIndex, rowsCopy
                        .length));
                return true;
            }

            document.visibleRows = rowsCopy.dup;
            document.lastRenderElapsedMs = cast(long)(MonoTime.currTime - renderStarted)
                .total!"msecs";
            updatePerfStatus(document);

            string baseStatus;
            if (filterLabel.length > 0)
            {
                baseStatus = format(
                    "Showing %s/%s rows (duplicate digest groups: %s, filter: %s, case-sensitive: %s)",
                    rowsCopy.length,
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
                    rowsCopy.length,
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

            if (busyDocument is document)
            {
                setLoadingState(document, false);
            }
            // Nach dem Laden: Spalten-Resizing aktivieren und Autosizing
            setTableColumnsResizable(document, true);
            document.tableView.columnsAutosize();
            new Idle({ applyDetailsPanePreference(document, false); return false; });
            document.status.setText(baseStatus);

            // Nach dem Befüllen TreeView wieder verbinden
            document.tableView.setModel(document.tableStore);

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
        setMetadataStatusLabel(document.detailArchiveStatus, "Archive", metadataPresenceSummary(
                row.hasArchive));
        setMetadataStatusLabel(document.detailTorrentStatus, "Torrent", metadataPresenceSummary(
                row.hasTorrent));
        setMetadataDetails(document.detailMediaInfoExpander, document.detailMediaInfoView, "MediaInfo", row
                .mediaInfoDetails);
        setMetadataDetails(document.detailArchiveExpander, document.detailArchiveView, "Archive", row
                .archiveDetails);
        setMetadataDetails(document.detailTorrentExpander, document.detailTorrentView, "Torrent", row
                .torrentDetails);
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
                "Has archive metadata: %s\n" ~
                "Has torrent metadata: %s\n" ~
                "\nMediaInfo details\n%s\n" ~
                "\nArchive details\n%s\n" ~
                "\nTorrent details\n%s\n" ~
                "\nRaw JSON Object\n\n" ~
                "%s\n",
            idx,
            row.fileNamesDetails.length > 0 ? row.fileNamesDetails : stackedFileNames(row.fileNamesSummary),
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
            row.hasArchive ? "yes" : "no",
            row.hasTorrent ? "yes" : "no",
            row.mediaInfoDetails.length > 0 ? row.mediaInfoDetails : "-",
            row.archiveDetails.length > 0 ? row.archiveDetails : "-",
            row.torrentDetails.length > 0 ? row.torrentDetails : "-",
            row.rawJson.length > 0 ? row.rawJson : "{}"
        );
        document.selectedDetailsText = detailsText;
        document.btnCopySha1.setSensitive(!isLoading && document.selectedSha1.length > 0);
        document.btnCopyFile.setSensitive(!isLoading && document.selectedFileName.length > 0);
        document.btnCopyDetails.setSensitive(!isLoading && document.selectedDetailsText.length > 0);
        setKnownFilesTable(
            document,
            row.fileNamesDetails.length > 0 ? row.fileNamesDetails
                : stackedFileNames(row.fileNamesSummary),
            row.fileCount
        );
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
        if (isLoading || pendingStartupPaths.length == 0)
        {
            if (!isLoading && pendingStartupSelectIndex >= 0 && pendingStartupSelectIndex < notebook.getNPages())
            {
                notebook.setCurrentPage(pendingStartupSelectIndex);
            }
            return;
        }

        auto nextPath = pendingStartupPaths[0];
        pendingStartupPaths = pendingStartupPaths[1 .. $];
        auto document = openDocumentFromPath(nextPath, false);
        loadDocument(document);
    }

    /** Open a document in a tab, selecting it optionally, without forcing a reload. */
    openDocumentFromPath = (string filePath, bool selectTab) {
        auto document = findDocumentByPath(filePath);
        if (document is null)
        {
            document = createDocumentTab(filePath);
            documents ~= document;
            auto pageIndex = notebook.appendPage(document.pageRoot, baseName(filePath));
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

        auto query = document.filterQuery;
        auto caseSensitive = prefCaseSensitiveFilter;
        auto requireVideo = document.filterVideo;
        auto requireAudio = document.filterAudio;
        auto requireImage = document.filterImage;
        auto requireText = document.filterText;
        auto negateMediaFilter = document.filterMediaNegated;
        auto sourceRows = document.loadedRows.dup;
        auto requestId = ++document.filterRequestId;
        bool hasMediaTypeFilters = requireVideo || requireAudio || requireImage || requireText;

        string mediaFilterSummary()
        {
            if (!hasMediaTypeFilters)
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
                result.filteredRows = filterRowsByText(sourceRows, query, caseSensitive);
                if (hasMediaTypeFilters)
                {
                    auto mediaFiltered = appender!(BlobRow[])();
                    foreach (row; result.filteredRows)
                    {
                        auto matchesMedia =
                            (requireVideo && row.hasVideo) ||
                            (requireAudio && row.hasAudio) ||
                            (requireImage && row.hasImage) ||
                            (requireText && row.hasText);
                        auto keepRow = negateMediaFilter ? !matchesMedia : matchesMedia;
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

    /** Load and normalize the JSON file for one open document tab. */
    loadDocument = (DocumentTab document) {
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
            return;
        }

        auto requestId = ++document.loadRequestId;
        setLoadingState(document, true, format("Loading %s ...", document.filePath));

        auto worker = new Thread({
            MonoTime started = MonoTime.currTime;
            AsyncLoadResult result;
            result.filePath = document.filePath;

            try
            {
                setLoadingPhase(document, requestId, "Loading scanner data via library ...");
                auto blobs = deserializeDataClassJsonFile(document.filePath);
                result.dataVersion = DATA_CLASS_VERSION2;
                result.rootShape = "library";
                result.rootKeysSummary = "NamedBinaryBlob[]";

                setLoadingPhase(document, requestId, "Projecting rows for GUI ...");
                result.allRows = extractRowsFromBlobs(blobs);

                setLoadingPhase(document, requestId, "Computing duplicate groups ...");
                result.duplicateGroups = countDuplicateDigestGroups(result.allRows);
            }
            catch (Exception ex)
            {
                result.error = ex.msg;
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
                    document.filterMediaNegated
                    ))
                {
                    applyFilterForDocument(document);
                }
                else
                {
                    renderRows(document, document.loadedRows);
                }

                persistCurrentState(clearSavedWindowGeometryOnExit);
                if (pendingStartupPaths.length > 0 && !isLoading)
                {
                    new Idle({ loadNextPendingStartupPath(); return false; });
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
                    loadDocument(document);
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

    /** Open the path from the toolbar as a new or existing tab and load if needed. */
    void loadFromPath()
    {
        // pathEntry entfernt
    }

    /** Reload the currently selected document tab from disk. */
    void reloadCurrentDocument()
    {
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }
        loadDocument(document);
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

        auto optClearWindowGeometry = new CheckButton("Delete saved window positions on save");
        optClearWindowGeometry.setActive(false);

        prefsBox.packStart(optAutoApply, false, false, 0);
        prefsBox.packStart(optCaseSensitive, false, false, 0);
        prefsBox.packStart(optDetailsBelow, false, false, 0);
        prefsBox.packStart(optRestoreOpenFiles, false, false, 0);
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

    content.packStart(separator, false, false, 0);
    content.packStart(toolbar, false, false, 0);
    content.packStart(notebook, true, true, 0);

    root.packStart(menuBar, false, false, 0);
    root.packStart(content, true, true, 0);

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

    if (cli.loadOnStart)
    {
        loadFromPath();
    }
    else if (prefRestoreOpenFiles && loadedState.openFilePaths.length > 0)
    {
        pendingStartupPaths = loadedState.openFilePaths.dup;
        pendingStartupSelectIndex = loadedState.activeTabIndex;
        loadNextPendingStartupPath();
    }

    Main.run();
    // Fallback persistence for quit paths that may bypass window destroy.
    persistCurrentState(clearSavedWindowGeometryOnExit);
    return 0;
}
