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

/** Bind toolbar buttons and filter controls to their handlers. */
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
    btnReload.addOnClicked((Button _) { callbacks.reloadCurrentDocument(); });
    btnRelayout.addOnClicked((Button _) { callbacks.relayoutCurrentDocument(); });
    btnCancelLoad.addOnClicked((Button _) { callbacks.cancelPendingLoad(); });
    btnApplyFilter.addOnClicked((Button _) { callbacks.applyFilterFromEntry(); });
    btnClearFilter.addOnClicked((Button _) { callbacks.clearCurrentFilter(); });

    filterEntry.addOnActivate((Entry _) { callbacks.applyFilterFromEntry(); });
    filterVideo.addOnToggled((ToggleButton _) { callbacks.applyFilterFromEntry(); });
    filterAudio.addOnToggled((ToggleButton _) { callbacks.applyFilterFromEntry(); });
    filterImage.addOnToggled((ToggleButton _) { callbacks.applyFilterFromEntry(); });
    filterText.addOnToggled((ToggleButton _) { callbacks.applyFilterFromEntry(); });
    filterMediaNot.addOnToggled((ToggleButton _) { callbacks.applyFilterFromEntry(); });
    filterFileType.addOnToggled((ToggleButton _) { callbacks.applyFilterFromEntry(); });
    filterArchive.addOnToggled((ToggleButton _) { callbacks.applyFilterFromEntry(); });
    filterTorrent.addOnToggled((ToggleButton _) { callbacks.applyFilterFromEntry(); });
}