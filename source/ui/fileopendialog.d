/** UI helpers for opening JSON files and repository directories.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.fileopendialog;

import gtk.FileChooserDialog;
import gtk.Window;
import gtk.c.types : FileChooserAction, ResponseType;

import ui.documenttab : DocumentTab;

/** Callbacks required by the open-file dialog. */
struct FileOpenDialogCallbacks
{
    /// Return whether a document load is already in progress.
    bool delegate() isLoading;
    /// Return the document whose status should report a rejected request.
    DocumentTab delegate() currentDocument;
    /// Open the given path as a document, forwarding the two boolean options.
    DocumentTab delegate(string, bool, bool) openDocumentFromPath;
    /// Start loading the given document, optionally forcing a reload.
    void delegate(DocumentTab, bool) loadDocument;
}

/** Show an open-file dialog and start loading the selected JSON document.
 *
 * Params:
 *     window = Parent window for the native file chooser.
 *     callbacks = Accessors and actions used to open and load the selected
 *         document.
 * Returns: Nothing.
 * Throws: GTK dialog construction or runtime errors are propagated.
 */
void chooseAndLoadPath(Window window, FileOpenDialogCallbacks callbacks)
{
    if (callbacks.isLoading())
    {
        auto document = callbacks.currentDocument();
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

    auto response = chooser.run();
    if (response == cast(int) ResponseType.ACCEPT)
    {
        auto selectedPath = chooser.getFilename();
        if (selectedPath.length > 0)
        {
            auto document = callbacks.openDocumentFromPath(selectedPath, true, true);
            if (document !is null && !document.sourceLoaded)
            {
                callbacks.loadDocument(document, true);
            }
        }
    }

    chooser.destroy();
}

/** Show a folder chooser and start loading the selected repository directory.
 *
 * Params:
 *     window = Parent window for the native folder chooser.
 *     callbacks = Accessors and actions used to open and load the selected
 *         repository.
 */
void chooseAndLoadRepository(Window window, FileOpenDialogCallbacks callbacks)
{
    if (callbacks.isLoading())
    {
        auto document = callbacks.currentDocument();
        if (document !is null)
            document.status.setText("A load is already in progress.");
        return;
    }

    auto chooser = new FileChooserDialog(
        "Open DosierSkanilo Repository",
        window,
        FileChooserAction.SELECT_FOLDER,
        ["_Cancel", "_Open"],
        [ResponseType.CANCEL, ResponseType.ACCEPT]
    );

    auto response = chooser.run();
    if (response == cast(int) ResponseType.ACCEPT)
    {
        auto selectedPath = chooser.getFilename();
        if (selectedPath.length > 0)
        {
            auto document = callbacks.openDocumentFromPath(selectedPath, true, true);
            if (document !is null && !document.sourceLoaded)
                callbacks.loadDocument(document, true);
        }
    }

    chooser.destroy();
}
