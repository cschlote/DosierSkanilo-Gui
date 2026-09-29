/** UI helpers for toolbar and filter signal wiring. */
module ui.toolbarbindings;

import gtk.Button;
import gtk.Entry;
import gtk.ToggleButton;

import ui.documenttab : DocumentTab;

/** Callbacks required by the toolbar controls. */
struct ToolbarBindingsCallbacks
{
    void delegate() reloadCurrentDocument;
    void delegate() relayoutCurrentDocument;
    void delegate() cancelPendingLoad;
    void delegate() applyFilterFromEntry;
    void delegate() clearCurrentFilter;
}

void bindToolbarButtons(Button btnReload, Button btnRelayout, Button btnCancelLoad,
    Button btnApplyFilter, Button btnClearFilter, ToolbarBindingsCallbacks callbacks)
{
    btnReload.addOnClicked((Button _) { callbacks.reloadCurrentDocument(); });
    btnRelayout.addOnClicked((Button _) { callbacks.relayoutCurrentDocument(); });
    btnCancelLoad.addOnClicked((Button _) { callbacks.cancelPendingLoad(); });
    btnApplyFilter.addOnClicked((Button _) { callbacks.applyFilterFromEntry(); });
    btnClearFilter.addOnClicked((Button _) { callbacks.clearCurrentFilter(); });
}

void bindToolbarButtons(Button btnReload, Button btnRelayout, Button btnCancelLoad,
    ToolbarBindingsCallbacks callbacks)
{
    btnReload.addOnClicked((Button _) { callbacks.reloadCurrentDocument(); });
    btnRelayout.addOnClicked((Button _) { callbacks.relayoutCurrentDocument(); });
    btnCancelLoad.addOnClicked((Button _) { callbacks.cancelPendingLoad(); });
}

void bindFilterSignals(Entry filterEntry, ToggleButton filterVideo, ToggleButton filterAudio,
    ToggleButton filterImage, ToggleButton filterText, ToggleButton filterMediaNot,
    ToggleButton filterFileType, ToggleButton filterArchive, ToggleButton filterTorrent,
    void delegate() applyFilter)
{
    filterEntry.addOnActivate((Entry _) { applyFilter(); });
    filterVideo.addOnToggled((ToggleButton _) { applyFilter(); });
    filterAudio.addOnToggled((ToggleButton _) { applyFilter(); });
    filterImage.addOnToggled((ToggleButton _) { applyFilter(); });
    filterText.addOnToggled((ToggleButton _) { applyFilter(); });
    filterMediaNot.addOnToggled((ToggleButton _) { applyFilter(); });
    filterFileType.addOnToggled((ToggleButton _) { applyFilter(); });
    filterArchive.addOnToggled((ToggleButton _) { applyFilter(); });
    filterTorrent.addOnToggled((ToggleButton _) { applyFilter(); });
}

/** Copy the active tab's filter widgets into the query state used by data sources. */
void captureDocumentFilterState(DocumentTab document)
{
    auto text = document.filterEntry.getText();
    document.filterQuery = text is null ? "" : text;
    document.filterVideo = document.filterVideoWidget.getActive();
    document.filterAudio = document.filterAudioWidget.getActive();
    document.filterImage = document.filterImageWidget.getActive();
    document.filterText = document.filterTextWidget.getActive();
    document.filterMediaNegated = document.filterMediaNotWidget.getActive();
    document.filterFileType = document.filterFileTypeWidget.getActive();
    document.filterArchive = document.filterArchiveWidget.getActive();
    document.filterTorrent = document.filterTorrentWidget.getActive();
}

/** Bind toolbar buttons and filter controls to their handlers.
 *
 * Params:
 *     btnReload = Reload button.
 *     btnRelayout = Relayout button.
 *     btnCancelLoad = Cancel-load button.
 *     btnApplyFilter = Apply-filter button.
 *     btnClearFilter = Clear-filter button.
 *     filterEntry = Text entry used for free-form filtering.
 *     filterVideo = Video filter toggle.
 *     filterAudio = Audio filter toggle.
 *     filterImage = Image filter toggle.
 *     filterText = Text filter toggle.
 *     filterMediaNot = Negated media filter toggle.
 *     filterFileType = File-type filter toggle.
 *     filterArchive = Archive filter toggle.
 *     filterTorrent = Torrent filter toggle.
 *     callbacks = Action callbacks for the toolbar controls.
 * Returns: Nothing.
 * Throws: None.
 */
void bindToolbarSignals(
    Button btnReload,
    Button btnRelayout,
    Button btnCancelLoad,
    Button btnApplyFilter,
    Button btnClearFilter,
    Entry filterEntry,
    ToggleButton filterVideo,
    ToggleButton filterAudio,
    ToggleButton filterImage,
    ToggleButton filterText,
    ToggleButton filterMediaNot,
    ToggleButton filterFileType,
    ToggleButton filterArchive,
    ToggleButton filterTorrent,
    ToolbarBindingsCallbacks callbacks
)
{
    bindToolbarButtons(btnReload, btnRelayout, btnCancelLoad, btnApplyFilter, btnClearFilter, callbacks);
    bindFilterSignals(filterEntry, filterVideo, filterAudio, filterImage, filterText,
        filterMediaNot, filterFileType, filterArchive, filterTorrent,
        callbacks.applyFilterFromEntry);
}

@("per-tab media and presence toggles are copied before applying filters")
unittest
{
    import gtk.CheckButton;
    import gtk.Main : Main;
    import std.process : environment;

    if (environment.get("DOSIER_GUI_FILTER_TEST", "") != "1")
        return;
    string[] args = ["dosierskanilo-gui-tests"];
    assert(Main.initCheck(args), "GTK filter test requires a usable display.");

    auto document = new DocumentTab();
    document.filterEntry = new Entry();
    document.filterEntry.setText("sample-query");
    document.filterVideoWidget = new CheckButton();
    document.filterAudioWidget = new CheckButton();
    document.filterImageWidget = new CheckButton();
    document.filterTextWidget = new CheckButton();
    document.filterMediaNotWidget = new CheckButton();
    document.filterFileTypeWidget = new CheckButton();
    document.filterArchiveWidget = new CheckButton();
    document.filterTorrentWidget = new CheckButton();

    bool applied;
    bindFilterSignals(document.filterEntry, document.filterVideoWidget,
        document.filterAudioWidget, document.filterImageWidget,
        document.filterTextWidget, document.filterMediaNotWidget,
        document.filterFileTypeWidget, document.filterArchiveWidget,
        document.filterTorrentWidget, () {
            captureDocumentFilterState(document);
            applied = true;
        });
    document.filterVideoWidget.setActive(true);
    document.filterAudioWidget.setActive(true);
    document.filterTextWidget.setActive(true);
    document.filterMediaNotWidget.setActive(true);
    document.filterFileTypeWidget.setActive(true);
    document.filterTorrentWidget.setActive(true);

    assert(applied);
    assert(document.filterQuery == "sample-query");
    assert(document.filterVideo && document.filterAudio && document.filterText);
    assert(!document.filterImage);
    assert(document.filterMediaNegated && document.filterFileType);
    assert(!document.filterArchive && document.filterTorrent);
}
