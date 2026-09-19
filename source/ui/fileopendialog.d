/** UI helpers for opening JSON files and repository directories. */
module ui.fileopendialog;

import gtk.FileChooserDialog;
import gtk.Window;
import gtk.c.types : FileChooserAction, ResponseType;

import ui.documenttab : DocumentTab;

/** Callbacks required by the open-file dialog. */
struct FileOpenDialogCallbacks
{
    bool delegate() isLoading;
    DocumentTab delegate() currentDocument;
    DocumentTab delegate(string, bool, bool) openDocumentFromPath;
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
            if (document.loadedRows.length == 0)
            {
                callbacks.loadDocument(document, true);
            }
        }
    }

    chooser.destroy();
}

/** Show a folder chooser and start loading the selected repository directory. */
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
            if (document.loadedRows.length == 0)
                callbacks.loadDocument(document, true);
        }
    }

    chooser.destroy();
}
