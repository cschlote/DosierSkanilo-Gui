/** Shared helpers for rendering details, metadata, and media previews.
 *
 * This module contains the widget-level glue used by the document tab detail
 * pane, including metadata labels, known-file tables, and image/video preview
 * management.
 */
module ui.detailswidgets;

import gtk.Entry;
import gtk.Expander;
import gtk.Container;
import gtk.DrawingArea;
import gtk.Image;
import gtk.Label;
import gtk.ComboBoxText;
import gtk.Box;
import gtk.TextView;
import gtk.TreeIter;
import gtk.Widget;
import gtk.StyleContext;
import gtk.c.types : GtkWrapMode;
import gdkpixbuf.Pixbuf;
import gdkpixbuf.c.types : GdkInterpType;
import gdk.X11 : getXid;
import gobject.ObjectG;
import gobject.Value;
import gstreamer.Bus;
import gstreamer.Element;
import gstreamer.ElementFactory;
import gstreamer.GStreamer;
import gstreamer.Message;
import gstreamer.Stream;
import gstreamer.StreamCollection;
import gstreamer.Structure;
import gstreamer.TagList;
import gstreamer.c.types : GstBusSyncReply, GstFormat, GstMessageType, GstSeekFlags, GstState, GstStreamType;
import gstinterfaces.VideoOverlay;
import pango.c.types : PangoEllipsizeMode;

import std.file : exists;
import std.format : format;
import std.path : absolutePath, buildNormalizedPath, dirName, extension, isAbsolute;
import std.string : join, startsWith, toLower;
import std.exception : enforce;
import std.uri : encode;

import dosierskanilo.metadata.mediainfosig : MediaInfoAudio, MediaInfoSig, MediaInfoText, MediaInfoVideo;
import model.blobrow : BlobRow;
import ui.documenttab : DocumentTab, PreviewScaleMode;

/** Normalize empty field values in the details form.
 *
 * Params:
 *     entry = Text entry widget to update.
 *     value = Text value to show, or an empty string for the placeholder.
 * Returns: Nothing.
 * Throws: None.
 */
void setDetailEntry(Entry entry, string value)
{
    entry.setText(value.length > 0 ? value : "-");
}

/** Write compact status text with a bold title into one metadata label.
 *
 * Params:
 *     label = Target label to update.
 *     title = Short heading to emphasize in the label.
 *     summary = Summary text to display next to the heading.
 * Returns: Nothing.
 * Throws: None.
 */
void setMetadataStatusLabel(Label label, string title, string summary)
{
    label.setEllipsize(PangoEllipsizeMode.MIDDLE);
    label.setSingleLineMode(true);
    label.setMarkup(format("<b>%s</b>  %s", title, summary));
}

/** Populate one expander-backed metadata details section.
 *
 * Params:
 *     expander = Expander that gates the details block.
 *     view = Text view that renders the long-form details.
 *     title = Human-readable section title used by the caller.
 *     detailsText = Raw details text to display, or an empty string to show
 *         the placeholder message.
 * Returns: Nothing.
 * Throws: None.
 */
void setMetadataDetails(Expander expander, TextView view, string title, string detailsText)
{
    auto hasDetails = detailsText.length > 0;
    expander.setSensitive(hasDetails);
    expander.setExpanded(false);
    expander.setVisible(true);
    view.getBuffer().setText(hasDetails ? detailsText : "No details available.");
}

/** Populate the known-files table from the current row, preferring original file specs.
 *
 * Params:
 *   document = active document tab whose known-file table should be updated
 *   row = current row whose source file specs should be rendered
 * Returns:
 *   nothing
 * Throws:
 *   EnforceError when the known-file label has not been initialized yet.
 */
void setKnownFilesTable(DocumentTab document, const(BlobRow) row)
{
    document.detailFileNamesStore.clear();
    enforce(document.detailFileNamesLabel !is null,
        "detailFileNamesLabel must be initialized before setting known files table");
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

/** Explain why a selected file cannot be shown in the preview pane. */
private string unavailablePreviewSummary(const(BlobRow) row, string fileName,
    string previewPath)
{
    auto type = row.fileType.length > 0 ? row.fileType : "unknown";
    string reason;
    if (previewPath.length > 0 && !exists(previewPath))
    {
        reason = "The referenced file is not available at the recorded path.";
    }
    else if (isImagePreviewCandidate(row) || isVideoPreviewCandidate(row))
    {
        reason = "The file type is recognized, but no compatible preview could be opened.";
    }
    else if (row.hasAudio || row.hasText)
    {
        reason = "The GUI preview currently supports images and video, not this media stream.";
    }
    else
    {
        reason = "No supported image or video preview handler was found for this file type.";
    }

    return format("Preview unavailable\nFile: %s\nSize: %s bytes\nType: %s\nReason: %s",
        fileName, row.fileSize, type, reason);
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

/** Load or reuse the source pixbuf for the current image preview. */
private bool ensureImagePreviewSource(DocumentTab document)
{
    if (document.selectedPreviewPath.length == 0 || !document.selectedPreviewIsImage)
    {
        return false;
    }

    if (document.selectedPreviewSourcePixbuf !is null
        && document.selectedPreviewSourcePath == document.selectedPreviewPath)
    {
        return true;
    }

    try
    {
        document.selectedPreviewSourcePixbuf = new Pixbuf(document.selectedPreviewPath);
        document.selectedPreviewSourcePath = document.selectedPreviewPath;
        return true;
    }
    catch (Exception)
    {
        document.selectedPreviewSourcePixbuf = null;
        document.selectedPreviewSourcePath = "";
        return false;
    }
}

/** Stop the embedded video player.
 *
 * Params:
 *     document = Active document tab whose preview player should stop.
 * Returns: Nothing.
 * Throws: None.
 */
void stopVideoPreview(DocumentTab document)
{
    if (document.previewVideoPlayer !is null)
    {
        document.previewVideoPlayer.setState(GstState.NULL);
    }

    document.previewVideoPlayer = null;
    document.previewVideoSink = null;
    document.previewVideoOverlay = null;
    document.detailPreviewVideoSinkWidget = null;
}

/** Resolve the GtkWidget exposed by gtksink. */
private Widget resolveGtkVideoSinkWidget(Element sink)
{
    if (sink is null)
    {
        return null;
    }

    auto value = new Value();
    sink.getProperty("widget", value);
    auto object = value.getObject();
    if (object is null)
    {
        return null;
    }

    return ObjectG.getDObject!(Widget)(cast(GtkWidget*) object.getObjectGStruct());
}

/** Replace the overlay drawing area with the widget provided by gtksink. */
private bool attachGtkVideoSinkWidget(DocumentTab document, Element sink)
{
    if (document is null || document.detailPreviewVideoFrame is null)
    {
        return false;
    }

    auto widget = resolveGtkVideoSinkWidget(sink);
    if (widget is null)
    {
        return false;
    }

    auto currentChild = document.detailPreviewVideoFrame.getChild();
    if (currentChild !is null && currentChild !is widget)
    {
        document.detailPreviewVideoFrame.remove(currentChild);
    }

    auto parent = widget.getParent();
    if (parent !is null && parent !is document.detailPreviewVideoFrame)
    {
        auto parentContainer = cast(Container) parent;
        if (parentContainer !is null)
        {
            parentContainer.remove(widget);
        }
    }

    if (widget.getParent() is null)
    {
        document.detailPreviewVideoFrame.add(widget);
    }

    widget.setHexpand(true);
    widget.setVexpand(true);
    widget.showAll();
    document.detailPreviewVideoSinkWidget = widget;
    document.previewVideoOverlay = null;
    return true;
}

/** Restore the original drawing area used by overlay-based sinks. */
private void restoreOverlayVideoArea(DocumentTab document)
{
    if (document is null || document.detailPreviewVideoFrame is null || document.detailPreviewVideoArea is null)
    {
        return;
    }

    auto currentChild = document.detailPreviewVideoFrame.getChild();
    if (currentChild !is null && currentChild !is document.detailPreviewVideoArea)
    {
        document.detailPreviewVideoFrame.remove(currentChild);
    }

    if (document.detailPreviewVideoArea.getParent() is null)
    {
        document.detailPreviewVideoFrame.add(document.detailPreviewVideoArea);
    }

    document.detailPreviewVideoArea.show();
    document.detailPreviewVideoSinkWidget = null;
}

/** Attach the embedded video sink to the realized preview widget.
 *
 * Params:
 *     document = Active document tab that owns the preview widget.
 *     renderWidth = Current render width, or a fallback when unavailable.
 *     renderHeight = Current render height, or a fallback when unavailable.
 * Returns: True when the video overlay could be attached, false otherwise.
 * Throws: None.
 */
bool syncVideoPreviewWindow(DocumentTab document, int renderWidth = -1, int renderHeight = -1)
{
    if (document is null || document.detailPreviewVideoArea is null || document.previewVideoSink is null)
    {
        return false;
    }

    if (document.previewVideoOverlay is null)
    {
        return document.detailPreviewVideoSinkWidget !is null;
    }

    auto window = document.detailPreviewVideoArea.getWindow();
    if (window is null || !window.ensureNative())
    {
        return false;
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
    if (player is null)
    {
        return false;
    }

    auto sink = ElementFactory.make("gtksink", "preview-videosink");
    auto usesOverlay = false;
    if (sink is null || !attachGtkVideoSinkWidget(document, sink))
    {
        sink = ElementFactory.make("ximagesink", "preview-videosink");
        if (sink is null)
        {
            return false;
        }

        restoreOverlayVideoArea(document);
        document.previewVideoOverlay = new VideoOverlay(sink);
        document.previewVideoOverlay.handleEvents(false);
        usesOverlay = true;
    }

    player.setProperty("video-sink", new Value(sink));
    if (usesOverlay)
    {
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
    }

    auto bus = player.getBus();
    bus.addSignalWatch();
    bus.addOnMessage((Message msg, Bus _) {
        if (msg.type() != GstMessageType.STREAM_COLLECTION)
        {
            return;
        }

        StreamCollection collection;
        msg.parseStreamCollection(collection);
        updateTrackLabelsFromStreamCollection(document, collection);
        syncVideoTrackSelectors(document);
    });

    document.previewVideoPlayer = player;
    document.previewVideoSink = sink;
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

/** Apply the current UI volume to the underlying player.
 *
 * Params:
 *     document = Active document tab whose player should receive the volume.
 *     volume = Requested volume in the inclusive range 0.0 to 1.0.
 * Returns: Nothing.
 * Throws: None.
 */
void setVideoPreviewVolume(DocumentTab document, double volume)
{
    document.previewVideoVolume = clampVideoPreviewVolume(volume);
    if (document.previewVideoPlayer !is null)
    {
        document.previewVideoPlayer.setProperty("volume", new Value(document.previewVideoVolume));
    }
}

/** Seek the preview to an absolute position in seconds.
 *
 * Params:
 *     document = Active document tab whose preview should seek.
 *     positionSeconds = Target playback position in seconds.
 * Returns: True when the seek request was accepted, false if no player exists.
 * Throws: None.
 */
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

/** Synchronize the playback slider and duration label with the player state.
 *
 * Params:
 *     document = Active document tab whose preview controls should be updated.
 * Returns: True when the player position could be queried, false otherwise.
 * Throws: None.
 */
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

/** Update the play button label to reflect the current player state.
 *
 * Params:
 *     document = Active document tab whose play button should be updated.
 *     playing = True when the player is currently in play mode.
 * Returns: Nothing.
 * Throws: None.
 */
void syncVideoPlaybackButton(DocumentTab document, bool playing)
{
    if (document.detailPreviewPlayButton is null)
    {
        return;
    }

    auto icon = new Image();
    icon.setFromIconName(playing ? "media-playback-pause" : "media-playback-start", GtkIconSize.BUTTON);
    icon.show();
    document.detailPreviewPlayButton.setImage(icon);
    document.detailPreviewPlayButton.setLabel("");
    document.detailPreviewPlayButton.setTooltipText(playing ? "Video pausieren" : "Video starten");
}

private int getElementIntProperty(Element element, string propertyName, int fallback = -1)
{
    if (element is null)
    {
        return fallback;
    }

    auto value = new Value(0);
    element.getProperty(propertyName, value);
    return value.getInt();
}

/** Set an integer property on a GStreamer element.
 *
 * Params:
 *     element = Target GStreamer element.
 *     propertyName = Name of the integer property to write.
 *     propertyValue = Value to store in the property.
 * Returns: Nothing.
 * Throws: None.
 */
void setElementIntProperty(Element element, string propertyName, int propertyValue)
{
    if (element is null)
    {
        return;
    }

    element.setProperty(propertyName, new Value(propertyValue));
}

private void clearTrackSelector(ComboBoxText combo, Box row)
{
    if (combo !is null)
    {
        combo.removeAll();
        combo.setActive(-1);
    }
    if (row !is null)
    {
        row.setVisible(false);
    }
}

private bool tryGetTrackTagString(TagList tags, string tagName, out string value)
{
    value = "";
    if (tags is null)
    {
        return false;
    }

    return tags.getString(tagName, value) && value.length > 0;
}

private string buildStreamDisplayLabel(string prefix, size_t index, Stream stream)
{
    auto fallback = format("%s %s", prefix, index + 1);
    if (stream is null)
    {
        return fallback;
    }

    auto tags = stream.getTags();
    string title;
    string language;
    string subtitleLanguage;
    string description;
    string codec;
    string[] fragments;

    if (tryGetTrackTagString(tags, "title", title))
    {
        fragments ~= title;
    }
    if (tryGetTrackTagString(tags, "language", language)
        || tryGetTrackTagString(tags, "language-code", language))
    {
        fragments ~= language;
    }
    if (tryGetTrackTagString(tags, "subtitle-language", subtitleLanguage))
    {
        fragments ~= subtitleLanguage;
    }
    if (tryGetTrackTagString(tags, "description", description))
    {
        fragments ~= description;
    }
    if (tryGetTrackTagString(tags, "codec", codec)
        || tryGetTrackTagString(tags, "audio-codec", codec)
        || tryGetTrackTagString(tags, "video-codec", codec))
    {
        fragments ~= codec;
    }

    if (fragments.length == 0)
    {
        auto streamId = stream.getStreamId();
        if (streamId.length > 0)
        {
            return fallback ~ " [" ~ streamId ~ "]";
        }
        return fallback;
    }

    return fallback ~ ": " ~ fragments.join(" | ");
}

private string buildTrackDisplayLabel(string prefix, size_t index, string[] fragments)
{
    auto fallback = format("%s %s", prefix, index + 1);
    string[] visibleFragments;
    foreach (fragment; fragments)
    {
        if (fragment.length > 0)
        {
            visibleFragments ~= fragment;
        }
    }

    if (visibleFragments.length == 0)
    {
        return fallback;
    }

    return fallback ~ ": " ~ visibleFragments.join(" | ");
}

private string buildVideoTrackLabel(const(MediaInfoVideo) stream)
{
    if (stream is null)
    {
        return "";
    }

    string[] fragments;
    fragments ~= stream.language;
    fragments ~= stream.format;
    if (stream.width > 0 && stream.height > 0)
    {
        fragments ~= format("%ux%u", stream.width, stream.height);
    }
    if (stream.frameRate > 0.0)
    {
        fragments ~= format("%.2ffps", stream.frameRate);
    }
    return buildTrackDisplayLabel("Video", cast(size_t) stream.index, fragments);
}

private string buildAudioTrackLabel(const(MediaInfoAudio) stream)
{
    if (stream is null)
    {
        return "";
    }

    string[] fragments;
    fragments ~= stream.language;
    fragments ~= stream.format;
    if (stream.channels > 0)
    {
        fragments ~= format("%u ch.", stream.channels);
    }
    return buildTrackDisplayLabel("Audio", cast(size_t) stream.index, fragments);
}

private string buildTextTrackLabel(const(MediaInfoText) stream)
{
    if (stream is null)
    {
        return "";
    }

    string[] fragments;
    fragments ~= stream.language;
    fragments ~= stream.format;
    if (stream.frameRate > 0.0)
    {
        fragments ~= format("%.2ffps", stream.frameRate);
    }
    return buildTrackDisplayLabel("Subtitle", cast(size_t) stream.index, fragments);
}

private void updateTrackLabelsFromMediaInfo(DocumentTab document, const(BlobRow) row)
{
    if (document is null)
    {
        return;
    }

    document.previewVideoTrackLabels = null;
    document.previewAudioTrackLabels = null;
    document.previewSubtitleTrackLabels = null;

    if (row.sourceBlob is null || row.sourceBlob.mediaInfoSig is null || row.sourceBlob.mediaInfoSig.empty)
    {
        document.previewVideoTrackSignature = "";
        document.previewAudioTrackSignature = "";
        document.previewSubtitleTrackSignature = "";
        return;
    }

    foreach (stream; row.sourceBlob.mediaInfoSig.videoStreams)
    {
        document.previewVideoTrackLabels ~= buildVideoTrackLabel(stream);
    }
    foreach (stream; row.sourceBlob.mediaInfoSig.audioStreams)
    {
        document.previewAudioTrackLabels ~= buildAudioTrackLabel(stream);
    }
    foreach (stream; row.sourceBlob.mediaInfoSig.textStreams)
    {
        document.previewSubtitleTrackLabels ~= buildTextTrackLabel(stream);
    }

    document.previewVideoTrackSignature = document.previewVideoTrackLabels.join("\n");
    document.previewAudioTrackSignature = document.previewAudioTrackLabels.join("\n");
    document.previewSubtitleTrackSignature = document.previewSubtitleTrackLabels.join("\n");
}

private void updateTrackLabelsFromStreamCollection(DocumentTab document, StreamCollection collection)
{
    if (document is null)
    {
        return;
    }

    if (collection is null)
    {
        return;
    }

    size_t videoIndex = 0;
    size_t audioIndex = 0;
    size_t subtitleIndex = 0;
    foreach (collectionIndex; 0 .. collection.getSize())
    {
        auto stream = collection.getStream(collectionIndex);
        if (stream is null)
        {
            continue;
        }

        auto streamType = stream.getStreamType();
        if ((streamType & GstStreamType.VIDEO) == GstStreamType.VIDEO)
        {
            document.previewVideoTrackLabels ~= buildStreamDisplayLabel("Video", videoIndex, stream);
            ++videoIndex;
        }
        else if ((streamType & GstStreamType.AUDIO) == GstStreamType.AUDIO)
        {
            document.previewAudioTrackLabels ~= buildStreamDisplayLabel("Audio", audioIndex, stream);
            ++audioIndex;
        }
        else if ((streamType & GstStreamType.TEXT) == GstStreamType.TEXT)
        {
            document.previewSubtitleTrackLabels ~= buildStreamDisplayLabel("Subtitle", subtitleIndex, stream);
            ++subtitleIndex;
        }
    }

    if (document.previewVideoTrackLabels.length == 0)
    {
        document.previewVideoTrackLabels = null;
    }
    if (document.previewAudioTrackLabels.length == 0)
    {
        document.previewAudioTrackLabels = null;
    }
    if (document.previewSubtitleTrackLabels.length == 0)
    {
        document.previewSubtitleTrackLabels = null;
    }
}

private void showTrackSelectorPlaceholder(ComboBoxText combo, Box row, string text)
{
    if (combo is null || row is null)
    {
        return;
    }

    row.setVisible(true);
    combo.removeAll();
    combo.appendText(text);
    combo.setActive(0);
    combo.setSensitive(false);
}

private void syncIndexedTrackSelector(
    ComboBoxText combo,
    Box row,
    string prefix,
    int trackCount,
    int currentIndex,
    string[] labels,
    ref int cachedCount,
    ref string cachedSignature)
{
    if (combo is null || row is null)
    {
        return;
    }

    if (trackCount <= 0)
    {
        showTrackSelectorPlaceholder(combo, row, prefix ~ " lädt...");
        cachedCount = trackCount;
        cachedSignature = prefix ~ " lädt...";
        return;
    }

    row.setVisible(true);
    string[] displayLabels;
    if (labels.length == trackCount)
    {
        displayLabels = labels.dup;
    }
    else
    {
        foreach (index; 0 .. trackCount)
        {
            displayLabels ~= format("%s %s", prefix, index + 1);
        }
    }

    auto signature = displayLabels.join("\n");
    if (cachedCount != trackCount || cachedSignature != signature)
    {
        combo.removeAll();
        foreach (label; displayLabels)
        {
            combo.appendText(label);
        }
        cachedCount = trackCount;
        cachedSignature = signature;
    }

    combo.setSensitive(trackCount > 1);

    if (currentIndex >= 0 && combo.getActive() != currentIndex)
    {
        combo.setActive(currentIndex);
    }
}

private void syncSubtitleTrackSelector(DocumentTab document, int trackCount, int currentIndex)
{
    auto combo = document.detailPreviewSubtitleTrackCombo;
    auto row = document.detailPreviewSubtitleTrackBox;
    if (combo is null || row is null)
    {
        return;
    }

    if (trackCount <= 0)
    {
        showTrackSelectorPlaceholder(combo, row, "Keine Untertitel");
        document.previewSubtitleTrackCount = trackCount;
        document.previewSubtitleTrackSignature = "Keine Untertitel";
        return;
    }

    row.setVisible(true);
    string[] displayLabels = ["Off"];
    if (document.previewSubtitleTrackLabels.length == trackCount)
    {
        displayLabels ~= document.previewSubtitleTrackLabels;
    }
    else
    {
        foreach (index; 0 .. trackCount)
        {
            displayLabels ~= format("Subtitle %s", index + 1);
        }
    }

    auto signature = displayLabels.join("\n");
    if (document.previewSubtitleTrackCount != trackCount || document.previewSubtitleTrackSignature != signature)
    {
        combo.removeAll();
        foreach (label; displayLabels)
        {
            combo.appendText(label);
        }
        document.previewSubtitleTrackCount = trackCount;
        document.previewSubtitleTrackSignature = signature;
    }

    combo.setSensitive(trackCount > 0);

    auto activeIndex = currentIndex >= 0 ? currentIndex + 1 : 0;
    if (combo.getActive() != activeIndex)
    {
        combo.setActive(activeIndex);
    }
}

/** Synchronize the preview track dropdowns with the current player state.
 *
 * Params:
 *     document = Active document tab whose track selectors should be updated.
 * Returns: Nothing.
 * Throws: None.
 */
void syncVideoTrackSelectors(DocumentTab document)
{
    if (document is null)
    {
        return;
    }

    if (!document.selectedPreviewIsVideo || document.previewVideoPlayer is null)
    {
        clearTrackSelector(document.detailPreviewVideoTrackCombo, document.detailPreviewVideoTrackBox);
        clearTrackSelector(document.detailPreviewAudioTrackCombo, document.detailPreviewAudioTrackBox);
        clearTrackSelector(document.detailPreviewSubtitleTrackCombo, document.detailPreviewSubtitleTrackBox);
        document.previewVideoTrackCount = -1;
        document.previewAudioTrackCount = -1;
        document.previewSubtitleTrackCount = -1;
        document.previewVideoTrackLabels = null;
        document.previewAudioTrackLabels = null;
        document.previewSubtitleTrackLabels = null;
        document.previewVideoTrackSignature = "";
        document.previewAudioTrackSignature = "";
        document.previewSubtitleTrackSignature = "";
        return;
    }

    document.previewVideoTrackSyncing = true;
    scope(exit) document.previewVideoTrackSyncing = false;

    syncIndexedTrackSelector(
        document.detailPreviewVideoTrackCombo,
        document.detailPreviewVideoTrackBox,
        "Video",
        getElementIntProperty(document.previewVideoPlayer, "n-video", 0),
        getElementIntProperty(document.previewVideoPlayer, "current-video", 0),
        document.previewVideoTrackLabels,
        document.previewVideoTrackCount,
        document.previewVideoTrackSignature);

    syncIndexedTrackSelector(
        document.detailPreviewAudioTrackCombo,
        document.detailPreviewAudioTrackBox,
        "Audio",
        getElementIntProperty(document.previewVideoPlayer, "n-audio", 0),
        getElementIntProperty(document.previewVideoPlayer, "current-audio", 0),
        document.previewAudioTrackLabels,
        document.previewAudioTrackCount,
        document.previewAudioTrackSignature);

    syncSubtitleTrackSelector(
        document,
        getElementIntProperty(document.previewVideoPlayer, "n-text", 0),
        getElementIntProperty(document.previewVideoPlayer, "current-text", -1));
}
/** Start video playback for the active preview.
 *
 * Params:
 *     document = Active document tab whose preview should start.
 * Returns: Nothing.
 * Throws: None.
 */
void playVideoPreview(DocumentTab document)
{
    if (!ensureVideoPreviewPlayer(document))
    {
        return;
    }

    document.previewVideoPlayer.setState(GstState.PLAYING);
    syncVideoPlaybackButton(document, true);
}

/** Pause video playback for the active preview.
 *
 * Params:
 *     document = Active document tab whose preview should pause.
 * Returns: Nothing.
 * Throws: None.
 */
void pauseVideoPreview(DocumentTab document)
{
    if (document.previewVideoPlayer is null)
    {
        return;
    }

    document.previewVideoPlayer.setState(GstState.PAUSED);
    syncVideoPlaybackButton(document, false);
}

/** Seek the current preview relative to its current play position.
 *
 * Params:
 *     document = Active document tab whose preview should jump.
 *     deltaSeconds = Signed offset in seconds, positive or negative.
 * Returns: True when the seek request was accepted, false if no player exists.
 * Throws: None.
 */
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
    document.detailPreviewVideoFrame.queueResize();
    document.detailPreviewVideoArea.queueResize();
    document.previewVideoPlayer.setState(GstState.NULL);
    setVideoPreviewVolume(document, document.previewVideoVolume);
    document.previewVideoPlayer.setProperty("uri", new Value(uri));
    if (!syncVideoPreviewWindow(document))
    {
        document.previewVideoPlayer.setState(GstState.READY);
        syncVideoTrackSelectors(document);
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

    syncVideoTrackSelectors(document);
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
        if (!ensureImagePreviewSource(document))
        {
            document.detailPreviewImage.clear();
            return;
        }

        auto source = document.selectedPreviewSourcePixbuf;
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
        {
            auto sourceWidth = source.getWidth();
            auto sourceHeight = source.getHeight();
            auto scale = cast(double) previewWidth / sourceWidth;
            auto destHeight = cast(int) (sourceHeight * scale);
            if (destHeight < 1)
            {
                destHeight = 1;
            }
            pixbuf = previewWidth == sourceWidth
                ? source
                : source.scaleSimple(previewWidth, destHeight, GdkInterpType.BILINEAR);
            break;
        }
        case PreviewScaleMode.fitHeight:
        {
            auto sourceWidth = source.getWidth();
            auto sourceHeight = source.getHeight();
            auto scale = cast(double) previewHeight / sourceHeight;
            auto destWidth = cast(int) (sourceWidth * scale);
            if (destWidth < 1)
            {
                destWidth = 1;
            }
            pixbuf = previewHeight == sourceHeight
                ? source
                : source.scaleSimple(destWidth, previewHeight, GdkInterpType.BILINEAR);
            break;
        }
        case PreviewScaleMode.center:
            pixbuf = source;
            break;
        case PreviewScaleMode.cover:
        {
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

/** Refresh the current preview image after a resize or layout change.
 *
 * Params:
 *     document = Active document tab whose preview should be refreshed.
 * Returns: Nothing.
 * Throws: None.
 */
void refreshMediaPreview(DocumentTab document)
{
    if (document.selectedPreviewIsVideo)
    {
        if (document.detailPreviewImageControls !is null)
        {
            document.detailPreviewImageControls.setVisible(false);
        }
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
    syncVideoTrackSelectors(document);

    if (document.selectedPreviewIsImage)
    {
        if (document.detailPreviewImageControls !is null)
        {
            document.detailPreviewImageControls.setVisible(true);
        }
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
    if (document.detailPreviewImageControls !is null)
    {
        document.detailPreviewImageControls.setVisible(false);
    }
    document.detailPreviewImage.clear();
}

/** Populate the preview pane from the selected row.
 *
 * Params:
 *     document = Active document tab that owns the preview pane.
 *     row = Selected row whose media and preview metadata should be shown.
 * Returns: Nothing.
 * Throws: None.
 */
void setMediaPreview(DocumentTab document, const(BlobRow) row)
{
    document.detailPreviewTitle.setText("Preview");

    auto fileName = row.primaryFileName.length > 0 ? row.primaryFileName : "-";
    auto mediaSummary = row.mediaInfoDetails.length > 0 ? row.mediaInfoDetails : "No media metadata available.";
    auto previewPath = resolvePreviewPath(document, row);
    auto imagePreviewPath = "";
    if (previewPath.length > 0)
    {
        if (previewPath != document.selectedPreviewCandidatePath)
        {
            document.selectedPreviewCandidatePath = previewPath;
            document.selectedPreviewCandidateExists = exists(previewPath);
        }

        if (document.selectedPreviewCandidateExists)
        {
            imagePreviewPath = previewPath;
        }
    }

    document.selectedPreviewPath = imagePreviewPath;
    document.selectedPreviewSourcePath = "";
    document.selectedPreviewSourcePixbuf = null;
    document.selectedPreviewIsImage = isImagePreviewCandidate(row) && imagePreviewPath.length > 0;
    document.selectedPreviewIsVideo = !document.selectedPreviewIsImage && isVideoPreviewCandidate(row);

    if (document.selectedPreviewIsVideo)
    {
        updateTrackLabelsFromMediaInfo(document, row);
    }
    else
    {
        document.previewVideoTrackLabels = null;
        document.previewAudioTrackLabels = null;
        document.previewSubtitleTrackLabels = null;
        document.previewVideoTrackSignature = "";
        document.previewAudioTrackSignature = "";
        document.previewSubtitleTrackSignature = "";
    }

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

        document.detailPreviewTitle.setText("Preview unavailable");
        document.detailPreviewSummary.setText(unavailablePreviewSummary(row, fileName,
            previewPath));
    }

    refreshMediaPreview(document);
}
