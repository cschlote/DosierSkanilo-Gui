module ui.detailswidgets;

import gtk.Entry;
import gtk.Expander;
import gtk.Image;
import gtk.Label;
import gtk.TextView;
import gtk.TreeIter;
import gtk.c.types : GtkWrapMode;
import gdkpixbuf.Pixbuf;
import gdkpixbuf.c.types : GdkInterpType;
import pango.PgFontDescription;

import std.file : exists;
import std.format : format;
import std.path : buildNormalizedPath, dirName, extension, isAbsolute;
import std.string : toLower;

import model.blobrow : BlobRow;
import ui.documenttab : DocumentTab, PreviewScaleMode;

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

/** Return the most likely filesystem path for preview loading. */
private string resolvePreviewPath(DocumentTab document, const(BlobRow) row)
{
    if (row.sourceBlob is null)
    {
        return "";
    }

    string candidatePath;
    foreach (spec; row.sourceBlob.fileSpecs)
    {
        if (spec is null || spec.fileName.length == 0)
        {
            continue;
        }

        candidatePath = spec.fileName;
        break;
    }

    if (candidatePath.length == 0)
    {
        candidatePath = row.primaryFileName;
    }

    if (candidatePath.length == 0)
    {
        return "";
    }

    if (isAbsolute(candidatePath))
    {
        return candidatePath;
    }

    auto baseDirectory = dirName(document.filePath);
    if (baseDirectory.length == 0)
    {
        return candidatePath;
    }

    return buildNormalizedPath(baseDirectory, candidatePath);
}

/** Decide whether the selected row is likely to represent an image file. */
private bool isImagePreviewCandidate(const(BlobRow) row)
{
    if (row.hasImage)
    {
        return true;
    }

    auto name = row.primaryFileName.toLower;
    if (name.length == 0)
    {
        return false;
    }

    auto ext = extension(name);
    return ext == ".png" || ext == ".jpg" || ext == ".jpeg" || ext == ".gif"
        || ext == ".webp" || ext == ".bmp" || ext == ".tif" || ext == ".tiff"
        || ext == ".svg";
}

private void updatePreviewImage(DocumentTab document)
{
    if (document.detailPreviewImage is null)
    {
        return;
    }

    if (document.selectedPreviewPath.length == 0 || !document.selectedPreviewIsImage)
    {
        document.detailPreviewImage.clear();
        return;
    }

    try
    {
        Pixbuf pixbuf;
        auto previewWidth = document.detailPreviewScroll !is null
            ? document.detailPreviewScroll.getAllocatedWidth() : 0;
        auto previewHeight = document.detailPreviewScroll !is null
            ? document.detailPreviewScroll.getAllocatedHeight() : 0;

        if (previewWidth <= 1)
        {
            previewWidth = 240;
        }
        if (previewHeight <= 1)
        {
            previewHeight = 180;
        }

        final switch (document.previewScaleMode)
        {
        case PreviewScaleMode.contain:
        {
            auto source = new Pixbuf(document.selectedPreviewPath);
            auto sourceWidth = source.getWidth();
            auto sourceHeight = source.getHeight();
            auto widthScale = cast(double) previewWidth / sourceWidth;
            auto heightScale = cast(double) previewHeight / sourceHeight;
            auto scale = widthScale < heightScale ? widthScale : heightScale;
            auto destWidth = cast(int) (sourceWidth * scale);
            auto destHeight = cast(int) (sourceHeight * scale);
            if (destWidth < 1)
            {
                destWidth = 1;
            }
            if (destHeight < 1)
            {
                destHeight = 1;
            }
            pixbuf = destWidth == sourceWidth && destHeight == sourceHeight
                ? source
                : source.scaleSimple(destWidth, destHeight, GdkInterpType.BILINEAR);
            break;
        }
        case PreviewScaleMode.fitWidth:
            pixbuf = new Pixbuf(document.selectedPreviewPath, previewWidth, -1, true);
            break;
        case PreviewScaleMode.fitHeight:
            pixbuf = new Pixbuf(document.selectedPreviewPath, -1, previewHeight, true);
            break;
        case PreviewScaleMode.center:
            pixbuf = new Pixbuf(document.selectedPreviewPath);
            break;
        case PreviewScaleMode.cover:
        {
            auto source = new Pixbuf(document.selectedPreviewPath);
            auto sourceWidth = source.getWidth();
            auto sourceHeight = source.getHeight();
            auto widthScale = cast(double) previewWidth / sourceWidth;
            auto heightScale = cast(double) previewHeight / sourceHeight;
            auto scale = widthScale > heightScale ? widthScale : heightScale;
            auto destWidth = cast(int) (sourceWidth * scale);
            auto destHeight = cast(int) (sourceHeight * scale);
            if (destWidth < 1)
            {
                destWidth = 1;
            }
            if (destHeight < 1)
            {
                destHeight = 1;
            }
            pixbuf = destWidth == sourceWidth && destHeight == sourceHeight
                ? source
                : source.scaleSimple(destWidth, destHeight, GdkInterpType.BILINEAR);
            break;
        }
        }

        document.detailPreviewImage.setFromPixbuf(pixbuf);
    }
    catch (Exception)
    {
        document.detailPreviewImage.clear();
    }
}

/** Refresh the current preview image after a resize or layout change. */
void refreshMediaPreview(DocumentTab document)
{
    updatePreviewImage(document);
}

void setMediaPreview(DocumentTab document, const(BlobRow) row)
{
    document.detailPreviewTitle.setText("Preview");

    auto fileName = row.primaryFileName.length > 0 ? row.primaryFileName : "-";
    auto mediaSummary = row.mediaInfoDetails.length > 0 ? row.mediaInfoDetails : "No media metadata available.";
    auto previewPath = resolvePreviewPath(document, row);
    auto imagePreviewPath = previewPath.length > 0 && exists(previewPath) ? previewPath : "";

    document.selectedPreviewPath = imagePreviewPath;
    document.selectedPreviewIsImage = isImagePreviewCandidate(row) && imagePreviewPath.length > 0;

    if (document.selectedPreviewIsImage)
    {
        document.detailPreviewSummary.setText(format("Image preview\n%s", fileName));
        updatePreviewImage(document);
        return;
    }

    document.detailPreviewImage.clear();

    if (row.hasVideo)
    {
        document.detailPreviewSummary.setText(format("Video preview\n%s", mediaSummary));
    }
    else if (row.hasAudio)
    {
        document.detailPreviewSummary.setText(format("Audio preview\n%s", mediaSummary));
    }
    else if (row.hasImage)
    {
        document.detailPreviewSummary.setText(format("Image preview\n%s", mediaSummary));
    }
    else if (row.hasText)
    {
        document.detailPreviewSummary.setText(format("Text preview\n%s", mediaSummary));
    }
    else if (fileName != "-")
    {
        document.detailPreviewSummary.setText(format("No direct preview\n%s", fileName));
    }
    else
    {
        document.detailPreviewSummary.setText("No preview available.");
    }
}
