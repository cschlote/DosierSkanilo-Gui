/** UI loader and signal wiring for the detail pane layout. */
module ui.detailpane;

import gtk.Box;
import gtk.Button;
import gtk.Builder;
import gtk.CellRendererText;
import gtk.Entry;
import gtk.Expander;
import gtk.Grid;
import gtk.Label;
import gtk.ListStore;
import gtk.Paned;
import gtk.ScrolledWindow;
import gtk.TextView;
import gtk.TreeIter;
import gtk.TreeView;
import gtk.TreeModelIF;
import gtk.TreePath;
import gtk.TreeSelection;
import gtk.TreeStore;
import gtk.TreeViewColumn;
import gtk.c.types : GType;

import ui.builderutils : builderObject, loadUiBuilder;
import ui.documenttab : DocumentTab;
import ui.nestedentrylogic : nestedEntryCopyPath;
import ui.tablecolumns : configureKnownFilesColumns;

/** Widgets from the detail pane layout. */
struct DetailPaneUi
{
    Box detailsPane;
    Paned detailsContent;
    Box previewSlot;
}

/** Callbacks needed to wire detail pane UI signals. */
struct DetailPaneCallbacks
{
    void delegate(DocumentTab, string) openKnownFileExternally;
    void delegate(string, string, DocumentTab) copyTextToClipboard;
    void delegate(DocumentTab) updateSelectedRowDetails;
}

/** Bind the detail pane layout to a document tab.
 *
 * Params:
 *     document = Active document tab that receives the detail widgets.
 * Returns: A struct with the detail pane widgets.
 * Throws: Any missing builder object or GtkBuilder parse failure is propagated.
 */
DetailPaneUi loadDetailPaneUi(DocumentTab document)
{
    auto detailBuilder = loadUiBuilder!"source/ui/detailpane.ui"("detail");
    document.detailBuilder = detailBuilder;

    DetailPaneUi ui;
    ui.detailsPane = builderObject!Box(detailBuilder, "detail", "detailsPane");
    auto detailsActions = builderObject!Box(detailBuilder, "detail", "detailsActions");
    ui.detailsContent = builderObject!Paned(detailBuilder, "detail", "detailsContent");
    auto detailsBody = builderObject!Box(detailBuilder, "detail", "detailsBody");
    auto detailVisuals = builderObject!Box(detailBuilder, "detail", "detailVisuals");
    auto detailGrid = builderObject!Grid(detailBuilder, "detail", "detailGrid");
    document.detailFileNamesLabel = builderObject!Label(detailBuilder, "detail", "detailFileNamesLabel");
    document.detailPreviousFileButton = builderObject!Button(detailBuilder, "detail",
        "detailPreviousFileButton");
    document.detailNextFileButton = builderObject!Button(detailBuilder, "detail",
        "detailNextFileButton");
    auto detailsScroll = builderObject!ScrolledWindow(detailBuilder, "detail", "detailsScroll");
    ui.previewSlot = builderObject!Box(detailBuilder, "detail", "previewSlot");

    document.btnCopySha1 = builderObject!Button(detailBuilder, "detail", "btnCopySha1");
    document.btnCopyFile = builderObject!Button(detailBuilder, "detail", "btnCopyFile");
    document.btnCopyPath = builderObject!Button(detailBuilder, "detail", "btnCopyPath");
    document.btnCopyDetails = builderObject!Button(detailBuilder, "detail", "btnCopyDetails");

    document.detailChecksumExpander = builderObject!Expander(detailBuilder, "detail", "detailChecksumExpander");
    document.detailChecksumStatus = builderObject!Label(detailBuilder, "detail", "detailChecksumStatus");
    document.detailFallbackExpander = builderObject!Expander(detailBuilder, "detail",
        "detailFallbackExpander");
    document.detailFallbackStatus = builderObject!Label(detailBuilder, "detail", "detailFallbackStatus");
    document.detailFallbackStore = new TreeStore([GType.STRING, GType.STRING]);
    document.detailFallbackTreeView = builderObject!TreeView(detailBuilder, "detail",
        "detailFallbackTreeView");
    document.detailFallbackTreeView.setModel(document.detailFallbackStore);
    configureFallbackTree(document.detailFallbackTreeView);
    document.detailMediaInfoExpander = builderObject!Expander(detailBuilder, "detail", "detailMediaInfoExpander");
    document.detailMediaInfoStatus = builderObject!Label(detailBuilder, "detail", "detailMediaInfoStatus");
    document.detailMediaInfoStore = new TreeStore([GType.STRING, GType.STRING,
        GType.STRING]);
    document.detailMediaInfoTreeView = builderObject!TreeView(detailBuilder, "detail",
        "detailMediaInfoTreeView");
    document.detailMediaInfoTreeView.setModel(document.detailMediaInfoStore);
    configureMediaInfoTree(document.detailMediaInfoTreeView);
    document.detailFileTypeExpander = builderObject!Expander(detailBuilder, "detail", "detailFileTypeExpander");
    document.detailFileTypeStatus = builderObject!Label(detailBuilder, "detail", "detailFileTypeStatus");
    document.detailFileTypeLabel = builderObject!Label(detailBuilder, "detail",
        "detailFileTypeLabel");
    document.detailArchiveExpander = builderObject!Expander(detailBuilder, "detail", "detailArchiveExpander");
    document.detailArchiveStatus = builderObject!Label(detailBuilder, "detail", "detailArchiveStatus");
    document.detailArchiveView = builderObject!TextView(detailBuilder, "detail", "detailArchiveView");
    document.detailArchiveTreeStore = new TreeStore([GType.STRING, GType.STRING,
        GType.STRING, GType.STRING, GType.STRING, GType.STRING, GType.STRING]);
    document.detailArchiveTreeView = builderObject!TreeView(detailBuilder, "detail",
        "detailArchiveTreeView");
    document.detailArchiveTreeView.setModel(document.detailArchiveTreeStore);
    configureNestedEntryTree(document.detailArchiveTreeView);
    document.detailTorrentExpander = builderObject!Expander(detailBuilder, "detail", "detailTorrentExpander");
    document.detailTorrentStatus = builderObject!Label(detailBuilder, "detail", "detailTorrentStatus");
    document.detailTorrentView = builderObject!TextView(detailBuilder, "detail", "detailTorrentView");
    document.detailTorrentTreeStore = new TreeStore([GType.STRING, GType.STRING,
        GType.STRING, GType.STRING, GType.STRING, GType.STRING, GType.STRING]);
    document.detailTorrentTreeView = builderObject!TreeView(detailBuilder, "detail",
        "detailTorrentTreeView");
    document.detailTorrentTreeView.setModel(document.detailTorrentTreeStore);
    configureNestedEntryTree(document.detailTorrentTreeView);
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
    detailsScroll.add(document.detailFileNamesView);
    document.detailFileNamesView.getSelection().addOnChanged((TreeSelection _) {
        TreeModelIF model;
        TreeIter iter;
        if (!document.detailFileNamesView.getSelection().getSelected(model, iter))
            return;
        auto selectedFileName = model.getValueString(iter, 0);
        if (selectedFileName.length > 0)
        {
            document.selectedFileName = selectedFileName;
            document.selectedFilePath = selectedFileName;
        }
        auto count = model.iterNChildren(null);
        document.detailPreviousFileButton.setSensitive(count > 1);
        document.detailNextFileButton.setSensitive(count > 1);
    });

    return ui;
}

private void configureNestedEntryTree(TreeView treeView)
{
    auto nameRenderer = new CellRendererText();
    auto nameColumn = new TreeViewColumn();
    nameColumn.setTitle("Entry");
    nameColumn.packStart(nameRenderer, true);
    nameColumn.addAttribute(nameRenderer, "text", 0);
    nameColumn.setExpand(true);
    treeView.appendColumn(nameColumn);

    auto sizeRenderer = new CellRendererText();
    auto sizeColumn = new TreeViewColumn();
    sizeColumn.setTitle("Size");
    sizeColumn.packStart(sizeRenderer, false);
    sizeColumn.addAttribute(sizeRenderer, "text", 1);
    treeView.appendColumn(sizeColumn);
}

private void configureMediaInfoTree(TreeView treeView)
{
    void addColumn(string title, int modelColumn, bool expand)
    {
        auto renderer = new CellRendererText();
        auto column = new TreeViewColumn();
        column.setTitle(title);
        column.packStart(renderer, true);
        column.addAttribute(renderer, "text", modelColumn);
        column.setResizable(true);
        column.setExpand(expand);
        treeView.appendColumn(column);
    }

    addColumn("Stream", 0, false);
    addColumn("Format", 1, false);
    addColumn("Properties", 2, true);
    treeView.setHeadersClickable(false);
}

private void configureFallbackTree(TreeView treeView)
{
    auto propertyRenderer = new CellRendererText();
    auto propertyColumn = new TreeViewColumn();
    propertyColumn.setTitle("Property");
    propertyColumn.packStart(propertyRenderer, true);
    propertyColumn.addAttribute(propertyRenderer, "text", 0);
    propertyColumn.setResizable(true);
    treeView.appendColumn(propertyColumn);

    auto valueRenderer = new CellRendererText();
    auto valueColumn = new TreeViewColumn();
    valueColumn.setTitle("Value");
    valueColumn.packStart(valueRenderer, true);
    valueColumn.addAttribute(valueRenderer, "text", 1);
    valueColumn.setResizable(true);
    valueColumn.setExpand(true);
    treeView.appendColumn(valueColumn);
    treeView.setHeadersClickable(false);
}

private void bindNestedEntryActivation(TreeView treeView, DocumentTab document,
    string entryLabel, DetailPaneCallbacks callbacks)
{
    treeView.addOnRowActivated((TreePath path, TreeViewColumn column, TreeView activatedView) {
        auto model = activatedView.getModel();
        auto iter = new TreeIter();
        if (!model.getIter(iter, path))
            return;
        string entryPath;
        if (nestedEntryCopyPath(model.getValueString(iter, 3),
                model.getValueString(iter, 2), entryPath))
            callbacks.copyTextToClipboard(entryLabel, entryPath, document);
    });
}

/** Wire row actions and copy buttons for the detail pane.
 *
 * Params:
 *     document = Active document tab that owns the detail pane widgets.
 *     callbacks = Action hooks used to open files and copy text.
 * Returns: Nothing.
 * Throws: None.
 */
void bindDetailPaneSignals(DocumentTab document, DetailPaneCallbacks callbacks)
{
    bindNestedEntryActivation(document.detailArchiveTreeView, document,
        "archive entry path", callbacks);
    bindNestedEntryActivation(document.detailTorrentTreeView, document,
        "torrent file path", callbacks);

    void selectRelativeFile(bool next)
    {
        TreeModelIF model;
        TreeIter iter;
        auto selection = document.detailFileNamesView.getSelection();
        if (!selection.getSelected(model, iter))
            return;
        auto path = model.getPath(iter);
        if (next)
            path.next();
        else if (!path.prev())
            return;
        selection.selectPath(path);
    }

    document.detailPreviousFileButton.addOnClicked((Button _) { selectRelativeFile(false); });
    document.detailNextFileButton.addOnClicked((Button _) { selectRelativeFile(true); });

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

        callbacks.openKnownFileExternally(document, knownFileName);
    });

    document.btnCopySha1.addOnClicked((Button _) {
        callbacks.copyTextToClipboard("SHA1", document.selectedSha1, document);
    });
    document.btnCopyFile.addOnClicked((Button _) {
        callbacks.copyTextToClipboard("file name", document.selectedFileName, document);
    });
    document.btnCopyPath.addOnClicked((Button _) {
        callbacks.copyTextToClipboard("file path", document.selectedFilePath, document);
    });
    document.btnCopyDetails.addOnClicked((Button _) {
        callbacks.copyTextToClipboard("details", document.selectedDetailsText, document);
    });

    document.tableView.getSelection().addOnChanged((TreeSelection _) {
        if (!document.syncingTreeSelection)
            callbacks.updateSelectedRowDetails(document);
    });
}

@("activating a later-page nested leaf copies its full path")
unittest
{
    import gtk.Main : Main;
    import std.process : environment;

    if (environment.get("DOSIER_GUI_ACTIVATION_TEST", "") != "1")
        return;
    string[] args = ["dosierskanilo-gui-tests"];
    assert(Main.initCheck(args), "GTK activation test requires a usable display.");

    auto store = new TreeStore([GType.STRING, GType.STRING, GType.STRING,
        GType.STRING, GType.STRING, GType.STRING, GType.STRING]);
    auto leaf = store.createIter(null);
    store.setValue(leaf, 0, "entry-250.txt");
    store.setValue(leaf, 1, "12 bytes");
    store.setValue(leaf, 2, "test/folder/entry-250.txt");
    store.setValue(leaf, 3, "File");
    auto treeView = new TreeView(store);
    auto document = new DocumentTab();
    string copiedLabel;
    string copiedPath;
    DetailPaneCallbacks callbacks;
    callbacks.copyTextToClipboard = (string label, string value, DocumentTab _) {
        copiedLabel = label;
        copiedPath = value;
    };
    bindNestedEntryActivation(treeView, document, "torrent file path", callbacks);

    auto path = new TreePath();
    path.appendIndex(0);
    treeView.rowActivated(path, null);

    assert(copiedLabel == "torrent file path");
    assert(copiedPath == "test/folder/entry-250.txt");
}
