/** UI helpers for the shortcuts and About dialogs. */
module ui.helpdialogs;

import gtk.AboutDialog;
import gtk.MessageDialog;
import gtk.Window;
import gtk.c.types : ButtonsType, DialogFlags, MessageType;

/** Show the keyboard shortcut overview dialog.
 *
 * Params:
 *     window = Parent window used to center and modalize the dialog.
 * Returns: Nothing.
 * Throws: GTK dialog construction or runtime errors are propagated.
 */
void showShortcutsHelp(Window window)
{
    auto dialog = new MessageDialog(
        window,
        DialogFlags.MODAL,
        MessageType.INFO,
        ButtonsType.CLOSE,
        "Keyboard Shortcuts\n\n" ~
            "Ctrl+O  Open JSON file\n" ~
            "Ctrl+Shift+O  Open repository directory\n" ~
            "Ctrl+W  Close Current Tab\n" ~
            "Ctrl+R  Reload\n" ~
            "Ctrl+K  Cancel Current Operation\n" ~
            "Ctrl+F  Apply Filter\n" ~
            "Ctrl+L  Clear Filter\n" ~
            "Ctrl+,  Preferences\n" ~
            "Ctrl+Q  Quit"
    );
    dialog.run();
    dialog.destroy();
}

/** Show the About dialog for the desktop frontend.
 *
 * Params:
 *     window = Parent window used to center and modalize the dialog.
 * Returns: Nothing.
 * Throws: GTK dialog construction or runtime errors are propagated.
 */
void showAbout(Window window)
{
    auto dialog = new AboutDialog();
    dialog.setTransientFor(window);
    dialog.setModal(true);
    dialog.setLogoIconName("help-about");
    dialog.setProgramName("DosierSkanilo GUI");
    dialog.setVersion("0.8.0");
    dialog.setComments("GTK frontend for the DosierSkanilo library backend. " ~
        "The CLI and GUI share the same repository and JSON operations.");
    dialog.setAuthors(["Carsten Schlote"]);
    dialog.run();
    dialog.destroy();
}
