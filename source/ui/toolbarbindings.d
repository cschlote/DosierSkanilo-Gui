/** UI helpers for toolbar and filter signal wiring.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.toolbarbindings;

import gtk.Button;
import gtk.Entry;
import gtk.ToggleButton;

import ui.documenttab : DocumentTab;

/** Callbacks required by the toolbar controls. */
struct ToolbarBindingsCallbacks
{
    /// Reloads the currently selected document.
    void delegate() reloadCurrentDocument;
    /// Recomputes the layout of the currently selected document.
    void delegate() relayoutCurrentDocument;
    /// Cancels a pending document load.
    void delegate() cancelPendingLoad;
    /// Applies the filter values currently entered in the filter bar.
    void delegate() applyFilterFromEntry;
    /// Clears the active filter.
    void delegate() clearCurrentFilter;
}

/** Connect the full toolbar button set to its action callbacks.
 *
 * Params:
 *     btnReload = Button that triggers a reload of the current document.
 *     btnRelayout = Button that triggers a relayout of the current document.
 *     btnCancelLoad = Button that cancels a pending load.
 *     btnApplyFilter = Button that applies the filter from the entry.
 *     btnClearFilter = Button that clears the current filter.
 *     callbacks = Action callbacks invoked by the buttons.
 * Returns: Nothing.
 * Throws: GTK runtime errors may propagate while connecting signals.
 */
void bindToolbarButtons(Button btnReload, Button btnRelayout, Button btnCancelLoad,
    Button btnApplyFilter, Button btnClearFilter, ToolbarBindingsCallbacks callbacks)
{
    btnReload.addOnClicked((Button _) { callbacks.reloadCurrentDocument(); });
    btnRelayout.addOnClicked((Button _) { callbacks.relayoutCurrentDocument(); });
    btnCancelLoad.addOnClicked((Button _) { callbacks.cancelPendingLoad(); });
    btnApplyFilter.addOnClicked((Button _) { callbacks.applyFilterFromEntry(); });
    btnClearFilter.addOnClicked((Button _) { callbacks.clearCurrentFilter(); });
}

/** Connect the reload, relayout, and cancel-load buttons to their action callbacks.
 *
 * Params:
 *     btnReload = Button that triggers a reload of the current document.
 *     btnRelayout = Button that triggers a relayout of the current document.
 *     btnCancelLoad = Button that cancels a pending load.
 *     callbacks = Action callbacks invoked by the buttons.
 * Returns: Nothing.
 * Throws: GTK runtime errors may propagate while connecting signals.
 */
void bindToolbarButtons(Button btnReload, Button btnRelayout, Button btnCancelLoad,
    ToolbarBindingsCallbacks callbacks)
{
    btnReload.addOnClicked((Button _) { callbacks.reloadCurrentDocument(); });
    btnRelayout.addOnClicked((Button _) { callbacks.relayoutCurrentDocument(); });
    btnCancelLoad.addOnClicked((Button _) { callbacks.cancelPendingLoad(); });
}

/** Connect the filter controls so any change re-applies the filter.
 *
 * The entry applies the filter when the user activates it, while every toggle
 * applies it on each state change.
 *
 * Params:
 *     filterEntry = Text entry used for free-form filtering.
 *     filterVideo = Video filter toggle.
 *     filterAudio = Audio filter toggle.
 *     filterImage = Image filter toggle.
 *     filterText = Text filter toggle.
 *     filterMediaNot = Negated media filter toggle.
 *     filterFileType = File-type filter toggle.
 *     filterArchive = Archive filter toggle.
 *     filterTorrent = Torrent filter toggle.
 *     filterCaseSensitive = Case-sensitive text matching toggle.
 *     applyFilter = Callback that reads and applies the current filter state.
 * Returns: Nothing.
 * Throws: GTK runtime errors may propagate while connecting signals.
 */
void bindFilterSignals(Entry filterEntry, ToggleButton filterVideo, ToggleButton filterAudio,
    ToggleButton filterImage, ToggleButton filterText, ToggleButton filterMediaNot,
    ToggleButton filterFileType, ToggleButton filterArchive, ToggleButton filterTorrent,
    ToggleButton filterCaseSensitive, void delegate() applyFilter)
{
    filterEntry.addOnActivate((Entry _) { applyFilter(); });
    filterCaseSensitive.addOnToggled((ToggleButton _) { applyFilter(); });
    filterVideo.addOnToggled((ToggleButton _) { applyFilter(); });
    filterAudio.addOnToggled((ToggleButton _) { applyFilter(); });
    filterImage.addOnToggled((ToggleButton _) { applyFilter(); });
    filterText.addOnToggled((ToggleButton _) { applyFilter(); });
    filterMediaNot.addOnToggled((ToggleButton _) { applyFilter(); });
    filterFileType.addOnToggled((ToggleButton _) { applyFilter(); });
    filterArchive.addOnToggled((ToggleButton _) { applyFilter(); });
    filterTorrent.addOnToggled((ToggleButton _) { applyFilter(); });
}

/** Copy the active tab's filter widgets into the query state used by data sources.
 *
 * Params:
 *     document = Document tab whose filter widgets are read and whose filter
 *         query fields are overwritten.
 * Returns: Nothing.
 * Throws: None.
 */
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
 *     filterCaseSensitive = Case-sensitive text matching toggle.
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
    ToggleButton filterCaseSensitive,
    ToolbarBindingsCallbacks callbacks
)
{
    bindToolbarButtons(btnReload, btnRelayout, btnCancelLoad, btnApplyFilter, btnClearFilter, callbacks);
    bindFilterSignals(filterEntry, filterVideo, filterAudio, filterImage, filterText,
        filterMediaNot, filterFileType, filterArchive, filterTorrent, filterCaseSensitive,
        callbacks.applyFilterFromEntry);
}

@("per-tab filter toggles apply case-sensitive text and presence filters")
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
    document.filterCaseSensitiveWidget = new CheckButton();
    document.filterFileTypeWidget = new CheckButton();
    document.filterArchiveWidget = new CheckButton();
    document.filterTorrentWidget = new CheckButton();

    size_t applyCount;
    bindFilterSignals(document.filterEntry, document.filterVideoWidget,
        document.filterAudioWidget, document.filterImageWidget,
        document.filterTextWidget, document.filterMediaNotWidget,
        document.filterFileTypeWidget, document.filterArchiveWidget,
        document.filterTorrentWidget, document.filterCaseSensitiveWidget, () {
            captureDocumentFilterState(document);
            ++applyCount;
        });
    document.filterVideoWidget.setActive(true);
    document.filterCaseSensitiveWidget.setActive(true);
    document.filterAudioWidget.setActive(true);
    document.filterTextWidget.setActive(true);
    document.filterMediaNotWidget.setActive(true);
    document.filterFileTypeWidget.setActive(true);
    document.filterTorrentWidget.setActive(true);

    assert(applyCount == 7);
    auto applyCountBeforeCaseToggle = applyCount;
    document.filterCaseSensitiveWidget.setActive(false);
    assert(applyCount == applyCountBeforeCaseToggle + 1);
    assert(document.filterQuery == "sample-query");
    assert(document.filterVideo && document.filterAudio && document.filterText);
    assert(!document.filterImage);
    assert(document.filterMediaNegated && document.filterFileType);
    assert(!document.filterArchive && document.filterTorrent);
}
