/** UI loader for the shared filter bar embedded in the main window toolbar. */
module ui.filterbar;

import gtk.Box;
import gtk.Button;
import gtk.Builder;
import gtk.CheckButton;
import gtk.Entry;

import ui.builderutils : builderObject, loadUiBuilder;

/** Widgets from the shared filter bar layout. */
struct FilterBarUi
{
    Box filterBar;
    Entry filterEntry;
    CheckButton filterVideo;
    CheckButton filterAudio;
    CheckButton filterImage;
    CheckButton filterText;
    CheckButton filterMediaNot;
    CheckButton filterFileType;
    CheckButton filterArchive;
    CheckButton filterTorrent;
    Button btnApplyFilter;
    Button btnClearFilter;
}

/** Bind the shared filter bar layout into an existing toolbar container.
 *
 * Params:
 *     filterSlot = Toolbar slot that receives the loaded filter bar widget.
 * Returns: A struct with the filter bar widgets.
 * Throws: Any missing builder object or GtkBuilder parse failure is propagated.
 */
FilterBarUi loadFilterBarUi(Box filterSlot)
{
    auto filterBuilder = loadUiBuilder!"source/ui/filterbar.ui"("filter bar");

    FilterBarUi ui;
    ui.filterBar = builderObject!Box(filterBuilder, "filter", "filterBar");
    filterSlot.add(ui.filterBar);
    ui.filterEntry = builderObject!Entry(filterBuilder, "filter", "filterEntry");
    ui.filterVideo = builderObject!CheckButton(filterBuilder, "filter", "filterVideo");
    ui.filterAudio = builderObject!CheckButton(filterBuilder, "filter", "filterAudio");
    ui.filterImage = builderObject!CheckButton(filterBuilder, "filter", "filterImage");
    ui.filterText = builderObject!CheckButton(filterBuilder, "filter", "filterText");
    ui.filterMediaNot = builderObject!CheckButton(filterBuilder, "filter", "filterMediaNot");
    ui.filterFileType = builderObject!CheckButton(filterBuilder, "filter", "filterFileType");
    ui.filterArchive = builderObject!CheckButton(filterBuilder, "filter", "filterArchive");
    ui.filterTorrent = builderObject!CheckButton(filterBuilder, "filter", "filterTorrent");
    ui.btnApplyFilter = builderObject!Button(filterBuilder, "filter", "btnApplyFilter");
    ui.btnClearFilter = builderObject!Button(filterBuilder, "filter", "btnClearFilter");

    return ui;
}