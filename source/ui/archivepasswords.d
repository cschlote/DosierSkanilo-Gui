/** Dialogs for managing and requesting archive passwords. */
module ui.archivepasswords;

import gtk.Box;
import gtk.Dialog;
import gtk.Entry;
import gtk.Label;
import gtk.Window;
import gtk.c.types : DialogFlags, Orientation, ResponseType;

/** Callback used to persist a filename-to-blob password mapping. */
struct ArchivePasswordManagerCallbacks
{
    void delegate(string fileName, string password) savePassword;
}

/** Open the filename-based password manager for the current source. */
void showArchivePasswordManager(Window parent, string initialFileName,
    ArchivePasswordManagerCallbacks callbacks)
{
    auto dialog = new Dialog("Archive Passwords", parent, DialogFlags.MODAL,
        ["_Cancel", "_Save"], [ResponseType.CANCEL, ResponseType.OK]);
    auto content = dialog.getContentArea();
    auto explanation = new Label("Associate a password with an archive filename. "
        ~ "Leave the password blank to remove the mapping. Passwords are stored "
        ~ "in the source catalog or repository.");
    explanation.setLineWrap(true);
    explanation.setXalign(0.0f);
    auto fileLabel = new Label("Archive filename or path:");
    fileLabel.setXalign(0.0f);
    auto fileEntry = new Entry();
    fileEntry.setText(initialFileName);
    auto passwordLabel = new Label("Password:");
    passwordLabel.setXalign(0.0f);
    auto passwordEntry = new Entry();
    passwordEntry.setVisibility(false);

    auto fields = new Box(Orientation.VERTICAL, 6);
    fields.setBorderWidth(10);
    fields.packStart(explanation, false, false, 0);
    fields.packStart(fileLabel, false, false, 0);
    fields.packStart(fileEntry, false, false, 0);
    fields.packStart(passwordLabel, false, false, 0);
    fields.packStart(passwordEntry, false, false, 0);
    content.packStart(fields, true, true, 0);
    dialog.showAll();

    if (dialog.run() == cast(int) ResponseType.OK)
    {
        import std.string : strip;
        auto fileName = fileEntry.getText().strip;
        if (fileName.length > 0)
            callbacks.savePassword(fileName, passwordEntry.getText());
    }
    dialog.destroy();
}

/** Ask for a password after an archive tool reports an encrypted entry. */
bool requestArchivePassword(Window parent, string archivePath, string reason,
    out string password)
{
    auto dialog = new Dialog("Archive Password Required", parent,
        DialogFlags.MODAL, ["_Cancel", "_Unlock"],
        [ResponseType.CANCEL, ResponseType.OK]);
    auto content = dialog.getContentArea();
    auto message = new Label("A password is required to inspect:\n" ~ archivePath
        ~ (reason.length > 0 ? "\n\n" ~ reason : ""));
    message.setLineWrap(true);
    message.setXalign(0.0f);
    auto passwordEntry = new Entry();
    passwordEntry.setVisibility(false);
    auto fields = new Box(Orientation.VERTICAL, 8);
    fields.setBorderWidth(10);
    fields.packStart(message, false, false, 0);
    fields.packStart(passwordEntry, false, false, 0);
    content.packStart(fields, true, true, 0);
    dialog.showAll();
    auto accepted = dialog.run() == cast(int) ResponseType.OK;
    if (accepted)
        password = passwordEntry.getText();
    dialog.destroy();
    return accepted;
}
