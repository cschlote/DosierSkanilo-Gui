/** UI helpers for the shortcuts and About dialogs. */
module ui.helpdialogs;

import gtk.AboutDialog;
import gtk.MessageDialog;
import gtk.Window;
import gtk.c.types : ButtonsType, DialogFlags, MessageType;

/** Show the keyboard shortcut overview dialog. */
void showShortcutsHelp(Window window)
{
    auto dialog = new MessageDialog(
        window,
        DialogFlags.MODAL,
        MessageType.INFO,
        ButtonsType.CLOSE,
        "Keyboard Shortcuts\n\n" ~
            "Ctrl+O  Open JSON\n" ~
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

/** Show the About dialog for the desktop frontend. */
void showAbout(Window window)
{
    auto dialog = new AboutDialog();
    dialog.setTransientFor(window);
    dialog.setModal(true);
    dialog.setLogoIconName("help-about");
    dialog.setProgramName("DosierSkanilo GUI");
    dialog.setVersion("0.6.0");
    dialog.setComments("Desktop frontend for DosierSkanilo.");
    dialog.setAuthors(["Carsten Schlote"]);
    dialog.run();
    dialog.destroy();
}