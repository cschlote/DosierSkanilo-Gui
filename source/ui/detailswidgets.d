module ui.detailswidgets;

import gtk.Entry;
import gtk.Expander;
import gtk.DrawingArea;
import gtk.Image;
import gtk.Label;
import gtk.TextView;
import gtk.TreeIter;
import gtk.c.types : GtkWrapMode;
import gdkpixbuf.Pixbuf;
import gdkpixbuf.c.types : GdkInterpType;
import gdk.X11 : getXid;
import gobject.Value;
import gstreamer.Bus;
import gstreamer.Element;
import gstreamer.ElementFactory;
import gstreamer.GStreamer;
import gstreamer.Message;
import gstreamer.Structure;
import gstreamer.c.types : GstBusSyncReply, GstFormat, GstMessageType, GstSeekFlags, GstState;
import gstinterfaces.VideoOverlay;
import pango.PgFontDescription;

import std.file : exists;
import std.format : format;
import std.path : absolutePath, buildNormalizedPath, dirName, extension, isAbsolute;
import std.string : startsWith, toLower;
import std.uri : encode;

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

/** Decide whether the selected row should use the embedded video preview. */
private bool isVideoPreviewCandidate(const(BlobRow) row)
{
    if (row.hasVideo)
    {
        return true;
    }

    auto name = row.primaryFileName.toLower;
    if (name.length == 0)
    {
        return false;
    }

    auto ext = extension(name);
    return ext == ".mp4" || ext == ".m4v" || ext == ".mkv" || ext == ".mov"
        || ext == ".avi" || ext == ".webm" || ext == ".ogv" || ext == ".mpg"
        || ext == ".mpeg" || ext == ".ts" || ext == ".3gp" || ext == ".wmv"
        || ext == ".flv";
}

/** Convert a local filesystem path into a file URI. */
private string toFileUri(string path)
{
    if (path.length == 0)
    {
        return "";
    }

    if (path.startsWith("file://") || path.startsWith("http://") || path.startsWith("https://"))
    {
        return path;
    }

    return "file://" ~ encode(absolutePath(path));
}

/** Stop the embedded video player. */
void stopVideoPreview(DocumentTab document)
{
    if (document.previewVideoPlayer !is null)
    {
        document.previewVideoPlayer.setState(GstState.NULL);
    }
}

/** Attach the embedded video sink to the realized preview widget. */
bool syncVideoPreviewWindow(DocumentTab document, int renderWidth = -1, int renderHeight = -1)
{
    if (document is null || document.detailPreviewVideoArea is null || document.previewVideoSink is null)
    {
        return false;
    }

    auto window = document.detailPreviewVideoArea.getWindow();
    if (window is null || !window.ensureNative())
    {
        return false;
    }

    if (document.previewVideoOverlay is null)
    {
        document.previewVideoOverlay = new VideoOverlay(document.previewVideoSink);
        document.previewVideoOverlay.handleEvents(false);
    }

    document.previewVideoOverlay.setWindowHandle(getXid(window));
    if (renderWidth <= 1)
    {
        renderWidth = 640;
    }
    if (renderHeight <= 1)
    {
        renderHeight = 360;
    }

    document.previewVideoOverlay.setRenderRectangle(0, 0, renderWidth, renderHeight);
    document.previewVideoOverlay.expose();
    return true;
}

/** Create the playbin-backed preview player on demand. */
private bool ensureVideoPreviewPlayer(DocumentTab document)
{
    if (document.previewVideoPlayer !is null && document.previewVideoSink !is null)
    {
        return true;
    }

    auto player = ElementFactory.make("playbin", "preview-playbin");
    auto sink = ElementFactory.make("ximagesink", "preview-videosink");
    if (player is null || sink is null)
    {
        return false;
    }

    player.setProperty("video-sink", new Value(sink));
    auto bus = player.getBus();
    bus.setSyncHandler((Message msg) {
        if (msg.type() != GstMessageType.ELEMENT)
        {
            return GstBusSyncReply.PASS;
        }

        auto structure = msg.getStructure();
        if (structure is null || !structure.hasName("prepare-window-handle"))
        {
            return GstBusSyncReply.PASS;
        }

        if (syncVideoPreviewWindow(document))
        {
            return GstBusSyncReply.DROP;
        }

        return GstBusSyncReply.PASS;
    });

    document.previewVideoPlayer = player;
    document.previewVideoSink = sink;
    document.previewVideoOverlay = new VideoOverlay(sink);
    document.previewVideoOverlay.handleEvents(false);
    return true;
}

/** Clamp the stream volume to a sane range. */
private double clampVideoPreviewVolume(double volume)
{
    if (volume < 0.0)
    {
        return 0.0;
    }
    if (volume > 1.0)
    {
        return 1.0;
    }
    return volume;
}

/** Format a video position in a compact time string. */
private string formatVideoPreviewTime(long nanoseconds)
{
    if (nanoseconds < 0)
    {
        nanoseconds = 0;
    }

    auto totalSeconds = nanoseconds / 1_000_000_000L;
    auto seconds = totalSeconds % 60;
    auto minutes = (totalSeconds / 60) % 60;
    auto hours = totalSeconds / 3600;

    if (hours > 0)
    {
        return format("%02d:%02d:%02d", hours, minutes, seconds);
    }

    return format("%02d:%02d", minutes, seconds);
}

/** Apply the current UI volume to the underlying player. */
void setVideoPreviewVolume(DocumentTab document, double volume)
{
    document.previewVideoVolume = clampVideoPreviewVolume(volume);
    if (document.previewVideoPlayer !is null)
    {
        document.previewVideoPlayer.setProperty("volume", new Value(document.previewVideoVolume));
    }
}

/** Seek the preview to an absolute position in seconds. */
bool seekVideoPreview(DocumentTab document, double positionSeconds)
{
    if (document.previewVideoPlayer is null)
    {
        return false;
    }

    if (positionSeconds < 0.0)
    {
        positionSeconds = 0.0;
    }

    auto targetPosition = cast(long) (positionSeconds * 1_000_000_000.0);
    return document.previewVideoPlayer.seekSimple(GstFormat.TIME, GstSeekFlags.FLUSH | GstSeekFlags.KEY_UNIT, targetPosition);
}

/** Synchronize the playback slider and duration label with the player state. */
bool syncVideoPreviewPosition(DocumentTab document)
{
    if (document.detailPreviewPositionScale is null || document.previewVideoPlayer is null)
    {
        return false;
    }

    long currentPosition;
    if (!document.previewVideoPlayer.queryPosition(GstFormat.TIME, currentPosition))
    {
        return false;
    }

    long duration;
    auto hasDuration = document.previewVideoPlayer.queryDuration(GstFormat.TIME, duration) && duration > 0;
    auto currentSeconds = cast(double) currentPosition / 1_000_000_000.0;
    auto durationSeconds = hasDuration ? cast(double) duration / 1_000_000_000.0 : currentSeconds;
    if (durationSeconds < 1.0)
    {
        durationSeconds = 1.0;
    }

    document.previewVideoPositionSyncing = true;
    document.detailPreviewPositionScale.setRange(0.0, durationSeconds);
    document.detailPreviewPositionScale.setValue(currentSeconds > durationSeconds ? durationSeconds : currentSeconds);

    if (document.detailPreviewPositionLabel !is null)
    {
        auto durationText = hasDuration ? formatVideoPreviewTime(duration) : "--:--";
        document.detailPreviewPositionLabel.setText("Position " ~ formatVideoPreviewTime(currentPosition) ~ " / " ~ durationText);
    }

    document.previewVideoPositionSyncing = false;
    return true;
}

/** Update the play button label to reflect the current player state. */
void syncVideoPlaybackButton(DocumentTab document, bool playing)
{
    if (document.detailPreviewPlayButton is null)
    {
        return;
    }

    document.detailPreviewPlayButton.setLabel(playing ? "Pause" : "Play");
}

/** Start video playback for the active preview. */
void playVideoPreview(DocumentTab document)
{
    if (!ensureVideoPreviewPlayer(document))
    {
        return;
    }

    document.previewVideoPlayer.setState(GstState.PLAYING);
    syncVideoPlaybackButton(document, true);
}

/** Pause video playback for the active preview. */
void pauseVideoPreview(DocumentTab document)
{
    if (document.previewVideoPlayer is null)
    {
        return;
    }

    document.previewVideoPlayer.setState(GstState.PAUSED);
    syncVideoPlaybackButton(document, false);
}

/** Seek the current preview relative to its current play position. */
bool jumpVideoPreview(DocumentTab document, long deltaSeconds)
{
    if (document.previewVideoPlayer is null)
    {
        return false;
    }

    long currentPosition;
    if (!document.previewVideoPlayer.queryPosition(GstFormat.TIME, currentPosition))
    {
        return false;
    }

    long targetPosition = currentPosition + deltaSeconds * 1_000_000_000L;
    if (targetPosition < 0)
    {
        targetPosition = 0;
    }

    long duration;
    if (document.previewVideoPlayer.queryDuration(GstFormat.TIME, duration) && duration > 0 && targetPosition >= duration)
    {
        targetPosition = duration - 1;
    }

    return document.previewVideoPlayer.seekSimple(GstFormat.TIME, GstSeekFlags.FLUSH | GstSeekFlags.KEY_UNIT, targetPosition);
}

/** Start or restart the embedded video preview for the current selection. */
private void updatePreviewVideo(DocumentTab document)
{
    if (document.detailPreviewVideoFrame is null || document.detailPreviewVideoArea is null)
    {
        return;
    }

    if (document.selectedPreviewPath.length == 0 || !document.selectedPreviewIsVideo)
    {
        stopVideoPreview(document);
        document.detailPreviewVideoFrame.setVisible(false);
        return;
    }

    if (!ensureVideoPreviewPlayer(document))
    {
        document.detailPreviewSummary.setText(format("Video preview\n%s", document.selectedFileName.length > 0 ? document.selectedFileName : document.selectedPreviewPath));
        document.detailPreviewVideoFrame.setVisible(false);
        return;
    }

    auto uri = toFileUri(document.selectedPreviewPath);
    if (uri.length == 0)
    {
        stopVideoPreview(document);
        document.detailPreviewVideoFrame.setVisible(false);
        return;
    }

    document.detailPreviewVideoFrame.setVisible(true);
    document.previewVideoPlayer.setState(GstState.NULL);
    setVideoPreviewVolume(document, document.previewVideoVolume);
    document.previewVideoPlayer.setProperty("uri", new Value(uri));
    if (!syncVideoPreviewWindow(document))
    {
        document.previewVideoPlayer.setState(GstState.READY);
        return;
    }

    if (document.previewVideoAutostart)
    {
        document.previewVideoPlayer.setState(GstState.PLAYING);
        syncVideoPlaybackButton(document, true);
    }
    else
    {
        document.previewVideoPlayer.setState(GstState.PAUSED);
        syncVideoPlaybackButton(document, false);
    }

    cast(void) syncVideoPreviewPosition(document);
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
    if (document.selectedPreviewIsVideo)
    {
        if (document.detailPreviewScroll !is null)
        {
            document.detailPreviewScroll.setVisible(false);
        }
        if (document.detailPreviewVideoControls !is null)
        {
            document.detailPreviewVideoControls.setVisible(true);
        }
        updatePreviewVideo(document);
        document.detailPreviewImage.clear();
        return;
    }

    stopVideoPreview(document);
    if (document.detailPreviewVideoFrame !is null)
    {
        document.detailPreviewVideoFrame.setVisible(false);
    }
    if (document.detailPreviewVideoControls !is null)
    {
        document.detailPreviewVideoControls.setVisible(false);
    }

    if (document.selectedPreviewIsImage)
    {
        if (document.detailPreviewScroll !is null)
        {
            document.detailPreviewScroll.setVisible(true);
        }
        updatePreviewImage(document);
        return;
    }

    if (document.detailPreviewScroll !is null)
    {
        document.detailPreviewScroll.setVisible(false);
    }
    document.detailPreviewImage.clear();
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
    document.selectedPreviewIsVideo = !document.selectedPreviewIsImage && isVideoPreviewCandidate(row) && imagePreviewPath.length > 0;

    if (document.selectedPreviewIsImage)
    {
        document.detailPreviewSummary.setText(format("Image preview\n%s", fileName));
    }
    else if (document.selectedPreviewIsVideo)
    {
        document.detailPreviewSummary.setText(format("Video preview\n%s", mediaSummary));
    }
    else
    {
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

    refreshMediaPreview(document);
}
