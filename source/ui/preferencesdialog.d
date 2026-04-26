/** UI loader for the preferences dialog layout. */
module ui.preferencesdialog;

import gtk.Dialog;
import gtk.Box;
import gtk.Builder;
import gtk.CheckButton;
import gtk.Entry;
import gtk.Label;
import gtk.Window;
import gtk.c.types : DialogFlags, ResponseType;

import ui.builderutils : builderObject, loadUiBuilder;
import ui.documenttab : DocumentTab;

/** Callbacks and state hooks required to apply preferences from the dialog. */
struct PreferencesDialogCallbacks
{
    void delegate() applyDetailsPanePreferenceToAll;
    void delegate(bool) persistCurrentState;
    DocumentTab delegate() currentDocument;
}

/** Widgets from the preferences dialog layout. */
struct PreferencesDialogUi
{
    Box prefsBox;
    CheckButton optAutoApply;
    CheckButton optCaseSensitive;
    CheckButton optDetailsBelow;
    CheckButton optRestoreOpenFiles;
    Label lblExternalOpenProgram;
    Entry entryExternalOpenProgram;
    CheckButton optClearWindowGeometry;
}

/** Bind the preferences dialog layout.
 *
 * Returns: A struct with the widgets required to present the preferences
 *     dialog.
 * Throws: Any missing builder object or GtkBuilder parse failure is propagated.
 */
PreferencesDialogUi loadPreferencesDialogUi()
{
    auto prefsBuilder = loadUiBuilder!"source/ui/preferencesdialog.ui"("preferences");

    PreferencesDialogUi ui;
    ui.prefsBox = builderObject!Box(prefsBuilder, "prefs", "prefsBox");
    ui.optAutoApply = builderObject!CheckButton(prefsBuilder, "prefs", "optAutoApply");
    ui.optCaseSensitive = builderObject!CheckButton(prefsBuilder, "prefs", "optCaseSensitive");
    ui.optDetailsBelow = builderObject!CheckButton(prefsBuilder, "prefs", "optDetailsBelow");
    ui.optRestoreOpenFiles = builderObject!CheckButton(prefsBuilder, "prefs", "optRestoreOpenFiles");
    ui.lblExternalOpenProgram = builderObject!Label(prefsBuilder, "prefs", "lblExternalOpenProgram");
    ui.entryExternalOpenProgram = builderObject!Entry(prefsBuilder, "prefs", "entryExternalOpenProgram");
    ui.optClearWindowGeometry = builderObject!CheckButton(prefsBuilder, "prefs", "optClearWindowGeometry");
    return ui;
}

/** Show the preferences dialog and apply any accepted changes to the caller's state.
 *
 * Params:
 *     window = Parent window for the modal preferences dialog.
 *     prefAutoApplyFilter = In/out flag for automatic filter application.
 *     prefCaseSensitiveFilter = In/out flag for case-sensitive filtering.
 *     prefDetailsBelow = In/out flag that controls the details pane placement.
 *     prefRestoreOpenFiles = In/out flag for restoring previously open files.
 *     externalOpenProgram = In/out external program used for opening files.
 *     clearSavedWindowGeometryOnExit = In/out flag that controls whether the
 *         saved window geometry should be cleared on exit.
 *     callbacks = Persistence and layout callbacks used when the user saves.
 * Returns: Nothing.
 * Throws: GTK dialog construction or runtime errors are propagated.
 */
void showPreferencesDialog(
    Window window,
    ref bool prefAutoApplyFilter,
    ref bool prefCaseSensitiveFilter,
    ref bool prefDetailsBelow,
    ref bool prefRestoreOpenFiles,
    ref string externalOpenProgram,
    ref bool clearSavedWindowGeometryOnExit,
    PreferencesDialogCallbacks callbacks
)
{
    auto dialog = new Dialog(
        "Preferences",
        window,
        DialogFlags.MODAL,
        ["_Cancel", "_Save"],
        [ResponseType.CANCEL, ResponseType.OK]
    );

    auto contentArea = dialog.getContentArea();
    auto prefsUi = loadPreferencesDialogUi();
    auto prefsBox = prefsUi.prefsBox;
    auto optAutoApply = prefsUi.optAutoApply;
    auto optCaseSensitive = prefsUi.optCaseSensitive;
    auto optDetailsBelow = prefsUi.optDetailsBelow;
    auto optRestoreOpenFiles = prefsUi.optRestoreOpenFiles;
    auto entryExternalOpenProgram = prefsUi.entryExternalOpenProgram;
    auto optClearWindowGeometry = prefsUi.optClearWindowGeometry;

    prefsBox.setBorderWidth(8);
    optAutoApply.setActive(prefAutoApplyFilter);
    optCaseSensitive.setActive(prefCaseSensitiveFilter);
    optDetailsBelow.setActive(prefDetailsBelow);
    optRestoreOpenFiles.setActive(prefRestoreOpenFiles);
    entryExternalOpenProgram.setText(externalOpenProgram);

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
            callbacks.applyDetailsPanePreferenceToAll();
        }

        auto newExternalOpenProgram = entryExternalOpenProgram.getText();
        externalOpenProgram = newExternalOpenProgram.length > 0 ? newExternalOpenProgram : "xdg-open";
        auto clearGeometry = optClearWindowGeometry.getActive();
        clearSavedWindowGeometryOnExit = clearGeometry;
        callbacks.persistCurrentState(clearGeometry);
        auto document = callbacks.currentDocument();
        if (document !is null)
        {
            document.status.setText(clearGeometry ? "Preferences saved. Stored window positions were deleted."
                    : "Preferences saved.");
        }
    }

    dialog.destroy();
}