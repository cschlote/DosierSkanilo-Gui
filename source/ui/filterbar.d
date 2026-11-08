/** UI loader for the shared filter bar embedded in the main window toolbar.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
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
    /// Root container holding the loaded filter bar widgets.
    Box filterBar;
    /// Free-form text entry used as the query filter.
    Entry filterEntry;
    /// Toggle that enables case-sensitive text matching.
    CheckButton filterCaseSensitive;
    /// Toggle that includes video entries.
    CheckButton filterVideo;
    /// Toggle that includes audio entries.
    CheckButton filterAudio;
    /// Toggle that includes image entries.
    CheckButton filterImage;
    /// Toggle that includes text/document entries.
    CheckButton filterText;
    /// Toggle that negates the media-type selection.
    CheckButton filterMediaNot;
    /// Toggle that filters on the presence of a file type.
    CheckButton filterFileType;
    /// Toggle that includes archive entries.
    CheckButton filterArchive;
    /// Toggle that includes torrent entries.
    CheckButton filterTorrent;
    /// Button that applies the current filter values.
    Button btnApplyFilter;
    /// Button that resets all filter values.
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
    ui.filterCaseSensitive = builderObject!CheckButton(filterBuilder, "filter", "filterCaseSensitive");
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
