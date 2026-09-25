/** UI helpers for toolbar and filter signal wiring. */
module ui.toolbarbindings;

import gtk.Button;
import gtk.Entry;
import gtk.ToggleButton;

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
