module ui.detailswidgets;

import gtk.Entry;
import gtk.Expander;
import gtk.Label;
import gtk.TextView;
import gtk.TreeIter;
import gtk.c.types : GtkWrapMode;
import pango.PgFontDescription;

import std.format : format;

import model.blobrow : BlobRow;
import ui.documenttab : DocumentTab;

/** Build a read-only single-line field for the details form. */
Entry createDetailEntry(int widthChars = 18)
{
    auto entry = new Entry();
    entry.setEditable(false);
    entry.setWidthChars(widthChars);
    entry.setHexpand(true);
    return entry;
}

/** Build a read-only multiline viewer for expanded metadata details. */
TextView createDetailTextView(bool monospace = false)
{
    auto view = new TextView();
    view.setEditable(false);
    view.setWrapMode(GtkWrapMode.WORD_CHAR);
    view.setMonospace(monospace);
    return view;
}

/** Build a left-aligned caption label for the details form. */
Label createDetailCaption(string text)
{
    auto label = new Label(text);
    label.setXalign(0.0f);
    return label;
}

/** Normalize empty field values in the details form. */
void setDetailEntry(Entry entry, string value)
{
    entry.setText(value.length > 0 ? value : "-");
}

/** Apply a monospace font to one entry widget. */
void setEntryMonospace(Entry entry)
{
    entry.overrideFont(PgFontDescription.fromString("Monospace 10"));
}

/** Write compact status text with a bold title into one metadata label. */
void setMetadataStatusLabel(Label label, string title, string summary)
{
    label.setMarkup(format("<b>%s</b>  %s", title, summary));
}

/** Populate one expander-backed metadata details section. */
void setMetadataDetails(Expander expander, TextView view, string title, string detailsText)
{
    auto hasDetails = detailsText.length > 0;
    expander.setSensitive(hasDetails);
    expander.setExpanded(false);
    expander.setVisible(true);
    view.getBuffer().setText(hasDetails ? detailsText : "No details available.");
}

/** Populate the known-files table from the current row, preferring original file specs. */
void setKnownFilesTable(DocumentTab document, const(BlobRow) row)
{
    document.detailFileNamesStore.clear();
    document.detailFileNamesLabel.setText(format("Known file names (%s)", row.fileCount));

    if (row.sourceBlob is null || row.sourceBlob.fileSpecs.length == 0)
    {
        return;
    }

    foreach (spec; row.sourceBlob.fileSpecs)
    {
        if (spec is null || spec.fileName.length == 0)
        {
            continue;
        }

        auto lastModified = spec.timeLastModified.length > 0 ? spec.timeLastModified : "-";

        TreeIter iter;
        document.detailFileNamesStore.append(iter);
        document.detailFileNamesStore.set(iter, [0, 1], [
            spec.fileName, lastModified
        ]);
    }
}
