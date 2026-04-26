/** UI loader and signal wiring for the detail pane layout. */
module ui.detailpane;

import gtk.Box;
import gtk.Button;
import gtk.Builder;
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
import gtk.TreeViewColumn;
import gtk.c.types : GType;

import ui.builderutils : builderObject, loadUiBuilder;
import ui.documenttab : DocumentTab;
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

/** Bind the detail pane layout to a document tab. */
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
    auto detailsScroll = builderObject!ScrolledWindow(detailBuilder, "detail", "detailsScroll");
    ui.previewSlot = builderObject!Box(detailBuilder, "detail", "previewSlot");

    document.btnCopySha1 = builderObject!Button(detailBuilder, "detail", "btnCopySha1");
    document.btnCopyFile = builderObject!Button(detailBuilder, "detail", "btnCopyFile");
    document.btnCopyDetails = builderObject!Button(detailBuilder, "detail", "btnCopyDetails");

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
    detailsScroll.add(document.detailFileNamesView);

    return ui;
}

/** Wire row actions and copy buttons for the detail pane. */
void bindDetailPaneSignals(DocumentTab document, DetailPaneCallbacks callbacks)
{
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
    document.btnCopyDetails.addOnClicked((Button _) {
        callbacks.copyTextToClipboard("details", document.selectedDetailsText, document);
    });

    document.tableView.getSelection().addOnChanged((TreeSelection _) {
        callbacks.updateSelectedRowDetails(document);
    });
}