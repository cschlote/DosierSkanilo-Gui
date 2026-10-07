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
import gtk.TreeStore;
import gtk.TreeView;
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

import dosierskanilo.repository.repository : Repository;
import va_toolbox.hexdumps : toPrettyHexDump;
import std.algorithm.searching : canFind;
import std.conv : to;
import std.format : format;
import std.path : absolutePath, extension;
import std.string : join, replace, split, startsWith, strip, toLower;
import std.exception : enforce;
import std.uri : encode;
import std.utf : validate;

enum size_t PREVIEW_HEX_DUMP_BYTES = 512;
enum size_t PREVIEW_TEXT_BYTES = 8192;

private enum PreviewContentKind
{
    image,
    video,
    audio,
    text,
    torrent,
    archive,
    binary
}

private void setPreviewSummaryMonospace(Label label, bool enabled)
{
    auto context = label.getStyleContext();
    if (enabled)
        context.addClass("preview-summary-monospace");
    else
        context.removeClass("preview-summary-monospace");
    label.setXalign(0);
    label.setYalign(0);
}

private bool isTextPreviewCandidate(const(BlobRow) row)
{
    if (row.hasText)
        return true;
    auto type = row.fileType.toLower;
    if (type.canFind("text") || type.canFind("ascii") || type.canFind("unicode"))
        return true;
    switch (extension(row.primaryFileName.toLower))
    {
    case ".txt", ".text", ".md", ".csv", ".json", ".xml", ".html", ".htm",
            ".css", ".js", ".d", ".c", ".h", ".cpp", ".hpp", ".log",
            ".ini", ".cfg", ".conf", ".yaml", ".yml", ".toml", ".sh",
            ".srt", ".vtt", ".sub":
        return true;
    default:
        return false;
    }
}

private bool isTorrentPreviewCandidate(const(BlobRow) row)
{
    auto type = row.sourceBlob is null ? "" : row.sourceBlob.fileType.toLower;
    return row.hasTorrent || type.canFind("torrent")
        || extension(row.primaryFileName.toLower) == ".torrent";
}

private bool isArchivePreviewCandidate(const(BlobRow) row)
{
    if (row.hasArchive)
        return true;

    auto type = row.sourceBlob is null ? "" : row.sourceBlob.fileType.toLower;
    if (type.canFind("archive") || type.canFind("compressed data"))
        return true;

    auto ext = extension(row.primaryFileName.toLower);
    switch (ext)
    {
    case ".zip", ".rar", ".7z", ".tar", ".gz", ".bz2", ".xz", ".tgz",
            ".tbz", ".tbz2", ".txz", ".lz", ".lzma", ".zst", ".cab",
            ".cpio", ".jar", ".war", ".ear", ".apk":
        return true;
    default:
        return false;
    }
}

private PreviewContentKind previewContentKind(const(BlobRow) row)
{
    if (isVideoPreviewCandidate(row))
        return PreviewContentKind.video;
    if (isAudioPreviewCandidate(row))
        return PreviewContentKind.audio;
    if (isImagePreviewCandidate(row))
        return PreviewContentKind.image;
    if (isTorrentPreviewCandidate(row))
        return PreviewContentKind.torrent;
    if (isArchivePreviewCandidate(row))
        return PreviewContentKind.archive;
    if (isTextPreviewCandidate(row))
        return PreviewContentKind.text;
    return PreviewContentKind.binary;
}

private string containerPreviewSummary(const(BlobRow) row, PreviewContentKind kind)
{
    auto fileName = row.primaryFileName.length > 0 ? row.primaryFileName : "-";
    auto sourceType = row.sourceBlob is null ? "" : row.sourceBlob.fileType;
    auto type = sourceType.length > 0 ? sourceType : "No file type signature available.";
    string[] lines = [
        kind == PreviewContentKind.torrent ? "Torrent metadata" : "Archive overview",
        "File: " ~ fileName,
        "Size: " ~ row.fileSize.to!string ~ " bytes",
        "File type: " ~ type
    ];

    if (kind == PreviewContentKind.torrent)
    {
        auto torrent = row.sourceBlob is null ? null : row.sourceBlob.torrentInfo;
        if (torrent is null || torrent.empty)
        {
            lines ~= "Torrent metadata has not been indexed.";
        }
        else
        {
            if (torrent.name.length > 0)
                lines ~= "Name: " ~ torrent.name;
            if (torrent.totalSize > 0)
                lines ~= "Content size: " ~ torrent.totalSize.to!string ~ " bytes";
            if (torrent.infoHashHex.length > 0)
                lines ~= "Info hash: " ~ torrent.infoHashHex;
            if (torrent.magnetURI.length > 0)
                lines ~= "Magnet URI: " ~ torrent.magnetURI;
            if (torrent.files.length > 0)
                lines ~= "Files: " ~ torrent.files.length.to!string;
            else
                lines ~= "File list: see the Torrent Previewer.";
        }
    }
    else if (row.hasArchive)
    {
        if (row.sourceBlob !is null && row.sourceBlob.archiveSpecs.length > 0)
            lines ~= "Entries: " ~ row.sourceBlob.archiveSpecs.length.to!string;
        else
            lines ~= "Entry list: see the Archive Previewer.";
    }
    else
    {
        lines ~= "Archive contents have not been indexed.";
    }

    return lines.join("\n");
}

/** Compact archive metadata for the details expander; full paths live in the preview tree. */
string archiveMetadataSummary(const(BlobRow) row)
{
    if (row.sourceBlob is null)
        return row.hasArchive
            ? "Archive entries are indexed; the full listing is in the Archive Previewer."
            : "";

    size_t entryCount;
    size_t entriesWithChecksums;
    ulong totalSize;
    ulong largestSize;
    string largestName;
    foreach (entry; row.sourceBlob.archiveSpecs)
    {
        if (entry is null)
            continue;
        ++entryCount;
        totalSize += entry.fileSize;
        if (entry.fileSize > largestSize)
        {
            largestSize = entry.fileSize;
            largestName = entry.fileName;
        }
        if (entry.checkSums.hasDigests)
            ++entriesWithChecksums;
    }
    if (entryCount == 0)
        return "";

    string[] lines = [
        format("Total expanded size: %s bytes", totalSize),
        format("Entries with all checksums: %s", entriesWithChecksums)
    ];
    if (largestName.length > 0)
        lines ~= format("Largest entry: %s (%s bytes)", largestName, largestSize);
    lines ~= "Full entry paths are shown in the Archive Previewer.";
    return lines.join("\n");
}

/** Compact torrent metadata for the details expander; the previewer owns the file tree. */
string torrentMetadataSummary(const(BlobRow) row)
{
    auto torrent = row.sourceBlob is null ? null : row.sourceBlob.torrentInfo;
    if (torrent is null)
        return row.hasTorrent
            ? "Torrent metadata is indexed; full metadata is loading or unavailable."
            : "";
    auto hasTorrentDetails = torrent.name.length > 0 || torrent.magnetURI.length > 0
        || torrent.infoHashHex.length > 0 || torrent.announce.length > 0
        || torrent.totalSize > 0 || torrent.pieceLength > 0 || torrent.piecesCount > 0
        || torrent.files.length > 0;
    if (!hasTorrentDetails)
        return "";

    string[] lines = [format("Mode: %s", torrent.isMultiFile
        ? "multi-file" : "single-file")];
    if (torrent.announce.length > 0)
        lines ~= "Announce: " ~ torrent.announce;
    if (torrent.pieceLength > 0)
        lines ~= format("Piece length: %s bytes", torrent.pieceLength);
    if (torrent.piecesCount > 0)
        lines ~= format("Pieces: %s", torrent.piecesCount);
    return lines.length > 0 ? lines.join("\n") : "No torrent details are available.";
}

import dosierskanilo.metadata.mediainfosig : MediaInfoAudio, MediaInfoSig, MediaInfoText, MediaInfoVideo;
import model.blobrow : BlobRow;
import ui.documenttab : DocumentTab, PreviewScaleMode;
import ui.contextpaths : resolveDocumentSourcePath;
import ui.fallbackrenderer : fallbackDetailRows;
import ui.mediainforenderer : mediaInfoStreamRows;

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
    view.setWrapMode(GtkWrapMode.WORD_CHAR);
    view.setCursorVisible(false);
    view.setVisible(hasDetails);
}

/** Present the `file` utility signature as a wrapped, selectable description. */
string fileTypeDisplayText(string signature)
{
    auto normalized = signature.strip;
    return normalized.length > 0 ? normalized : "No file type signature available.";
}

void setFileTypeDetails(Expander expander, Label label, string signature)
{
    auto hasDetails = signature.strip.length > 0;
    label.setText(fileTypeDisplayText(signature));
    label.setLineWrap(true);
    label.setSelectable(true);
    label.setXalign(0);
    label.setYalign(0);
    expander.setSensitive(hasDetails);
    expander.setExpanded(false);
    expander.setVisible(true);
}

/** Render structured MediaInfo stream rows instead of its generic text dump. */
void setMediaInfoStreamDetails(DocumentTab document, const(BlobRow) row)
{
    document.detailMediaInfoStore.clear();
    auto signature = row.sourceBlob is null ? null : row.sourceBlob.mediaInfoSig;
    auto rows = mediaInfoStreamRows(signature);
    foreach (stream; rows)
    {
        auto iter = document.detailMediaInfoStore.createIter(null);
        document.detailMediaInfoStore.setValue(iter, 0, stream.stream);
        document.detailMediaInfoStore.setValue(iter, 1, stream.format);
        document.detailMediaInfoStore.setValue(iter, 2, stream.properties);
    }
    document.detailMediaInfoExpander.setSensitive(rows.length > 0);
    document.detailMediaInfoExpander.setExpanded(false);
    document.detailMediaInfoExpander.setVisible(true);
    document.detailMediaInfoTreeView.setVisible(true);
}

/** Clear the structured MediaInfo stream view when no row is selected. */
void clearMediaInfoStreamDetails(DocumentTab document)
{
    document.detailMediaInfoStore.clear();
    document.detailMediaInfoExpander.setSensitive(false);
    document.detailMediaInfoExpander.setExpanded(false);
    document.detailMediaInfoExpander.setVisible(true);
    document.detailMediaInfoTreeView.setVisible(true);
}

/** Render the file-identity fallback when no specialized metadata is available. */
void setFallbackDetails(DocumentTab document, const(BlobRow) row)
{
    document.detailFallbackStore.clear();
    auto rows = fallbackDetailRows(row);
    foreach (detail; rows)
    {
        auto iter = document.detailFallbackStore.createIter(null);
        document.detailFallbackStore.setValue(iter, 0, detail.property);
        document.detailFallbackStore.setValue(iter, 1, detail.value);
    }
    document.detailFallbackStatus.setText(rows.length > 0
        ? "File overview · fallback" : "File overview");
    document.detailFallbackExpander.setSensitive(rows.length > 0);
    document.detailFallbackExpander.setExpanded(false);
    document.detailFallbackExpander.setVisible(true);
    document.detailFallbackTreeView.setVisible(true);
}

void clearFallbackDetails(DocumentTab document)
{
    document.detailFallbackStore.clear();
    document.detailFallbackStatus.setText("File overview");
    document.detailFallbackExpander.setSensitive(false);
    document.detailFallbackExpander.setExpanded(false);
    document.detailFallbackExpander.setVisible(true);
    document.detailFallbackTreeView.setVisible(true);
}

@("file type renderer trims signatures and shows an explicit empty state")
unittest
{
    assert(fileTypeDisplayText("  Matroska video data  ") == "Matroska video data");
    assert(fileTypeDisplayText(" \n ") == "No file type signature available.");
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
    ++document.nestedEntryRequestId;
    populateArchiveEntryTree(document, row);
    populateTorrentFileTree(document, row);
    document.selectedFilePath = "";
    document.detailPreviousFileButton.setSensitive(false);
    document.detailNextFileButton.setSensitive(false);
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

private void appendNestedPath(TreeStore store, string path, string sizeText,
    ref TreeIter[string] directories)
{
    import std.string : replace;
    auto normalized = path.replace('\\', '/');
    auto parts = normalized.split("/");
    if (parts.length == 0)
        return;

    TreeIter parent;
    string directoryPath;
    foreach (part; parts[0 .. $ - 1])
    {
        if (part.length == 0)
            continue;
        directoryPath = directoryPath.length == 0 ? part : directoryPath ~ "/" ~ part;
        if (auto existing = directoryPath in directories)
        {
            parent = *existing;
            continue;
        }
        auto directoryIter = store.createIter(parent);
        store.setValue(directoryIter, 0, part);
        store.setValue(directoryIter, 1, "");
        store.setValue(directoryIter, 2, directoryPath);
        store.setValue(directoryIter, 3, "Directory");
        directories[directoryPath] = directoryIter;
        parent = directoryIter;
    }

    auto fileName = parts[$ - 1];
    if (fileName.length == 0)
        return;
    auto fileIter = store.createIter(parent);
    store.setValue(fileIter, 0, fileName);
    store.setValue(fileIter, 1, sizeText);
    store.setValue(fileIter, 2, normalized);
    store.setValue(fileIter, 3, "File");
}

private void populateArchiveEntryTree(DocumentTab document, const(BlobRow) row)
{
    document.detailArchiveTreeStore.clear();
    if (document.directorySourceRemote && row.sourceId >= 0 && row.hasArchive)
    {
        auto root = document.detailArchiveTreeStore.createIter(null);
        document.detailArchiveTreeStore.setValue(root, 0, "Archive entries");
        document.detailArchiveTreeStore.setValue(root, 1, "");
        document.detailArchiveTreeStore.setValue(root, 2, "");
        document.detailArchiveTreeStore.setValue(root, 3, "ArchiveRoot");
        document.detailArchiveTreeStore.setValue(root, 4, row.sourceId.to!string);
        document.detailArchiveTreeStore.setValue(root, 6, document.nestedEntryRequestId.to!string);
        auto loading = document.detailArchiveTreeStore.createIter(root);
        document.detailArchiveTreeStore.setValue(loading, 0, "Loading...");
        document.detailArchiveTreeStore.setValue(loading, 3, "Loading");
        document.detailArchiveTreeView.setVisible(true);
        return;
    }
    TreeIter[string] directories;
    if (row.sourceBlob !is null)
    {
        foreach (entry; row.sourceBlob.archiveSpecs)
        {
            if (entry !is null && entry.fileName.length > 0)
            {
                appendNestedPath(document.detailArchiveTreeStore, entry.fileName,
                    format("%s bytes", entry.fileSize), directories);
            }
        }
    }
    document.detailArchiveTreeView.setVisible(document.detailArchiveTreeStore.iterNChildren(null) > 0);
}

private void populateTorrentFileTree(DocumentTab document, const(BlobRow) row)
{
    document.detailTorrentTreeStore.clear();
    if (document.directorySourceRemote && row.sourceId >= 0 && row.hasTorrent)
    {
        auto root = document.detailTorrentTreeStore.createIter(null);
        document.detailTorrentTreeStore.setValue(root, 0, "Torrent files");
        document.detailTorrentTreeStore.setValue(root, 1, "");
        document.detailTorrentTreeStore.setValue(root, 2, "");
        document.detailTorrentTreeStore.setValue(root, 3, "TorrentRoot");
        document.detailTorrentTreeStore.setValue(root, 4, row.sourceId.to!string);
        document.detailTorrentTreeStore.setValue(root, 6, document.nestedEntryRequestId.to!string);
        auto loading = document.detailTorrentTreeStore.createIter(root);
        document.detailTorrentTreeStore.setValue(loading, 0, "Loading...");
        document.detailTorrentTreeStore.setValue(loading, 3, "Loading");
        document.detailTorrentTreeView.setVisible(true);
        return;
    }
    TreeIter[string] directories;
    if (row.sourceBlob !is null && row.sourceBlob.torrentInfo !is null)
    {
        foreach (entry; row.sourceBlob.torrentInfo.files)
        {
            if (entry !is null && entry.path.length > 0)
            {
                auto relativePath = entry.path.join("/");
                appendNestedPath(document.detailTorrentTreeStore, entry.path.join("/"),
                    format("%s bytes", entry.length), directories);
            }
        }
    }
    document.detailTorrentTreeView.setVisible(document.detailTorrentTreeStore.iterNChildren(null) > 0);
}

/** Return the most likely filesystem path for preview loading. */
private string resolvePreviewPath(DocumentTab document, const(BlobRow) row)
{
    if (row.sourceBlob is null)
    {
        return "";
    }

    auto repositoryRoot = document.directorySourceRemote
        ? Repository.findRoot(document.filePath) : "";
    auto selectedTreePath = document.selectedTreeCursor.relativePath;
    if (selectedTreePath.length > 0)
    {
        auto resolvedSelection = resolveDocumentSourcePath(document.filePath,
            selectedTreePath, repositoryRoot);
        foreach (spec; row.sourceBlob.fileSpecs)
        {
            if (spec is null || spec.fileName.length == 0)
                continue;
            if (resolveDocumentSourcePath(document.filePath, spec.fileName,
                    repositoryRoot) == resolvedSelection)
                return resolvedSelection;
        }
    }

    foreach (spec; row.sourceBlob.fileSpecs)
    {
        if (spec is null || spec.fileName.length == 0)
        {
            continue;
        }

        auto candidatePath = resolveDocumentSourcePath(document.filePath,
            spec.fileName, repositoryRoot);
        return candidatePath;
    }

    return resolveDocumentSourcePath(document.filePath, row.primaryFileName,
        repositoryRoot);
}

/** Decide whether the selected row is likely to represent an image file. */
private bool isImagePreviewCandidate(const(BlobRow) row)
{
    // Embedded cover art in an audio container must not steal the audio preview.
    if (row.hasAudio || row.hasVideo)
    {
        return false;
    }
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

/** Decide whether the selected row should use the audio player. */
private bool isAudioPreviewCandidate(const(BlobRow) row)
{
    if (row.hasVideo)
    {
        return false;
    }
    if (row.hasAudio)
    {
        return true;
    }

    auto type = row.fileType.toLower;
    if (type.canFind("audio") || type.canFind("mpeg layer") || type.canFind("flac")
        || type.canFind("wave audio") || type.canFind("opus") || type.canFind("vorbis"))
    {
        return true;
    }

    auto ext = extension(row.primaryFileName.toLower);
    return ext == ".mp3" || ext == ".m4a" || ext == ".m4b" || ext == ".aac"
        || ext == ".flac" || ext == ".wav" || ext == ".wave" || ext == ".ogg"
        || ext == ".oga" || ext == ".opus" || ext == ".wma" || ext == ".aiff"
        || ext == ".aif" || ext == ".ape" || ext == ".ac3" || ext == ".alac";
}

@("Audio preview takes priority over embedded cover art")
unittest
{
    BlobRow row;
    row.primaryFileName = "album-track.mp3";
    row.hasSummaryFlags = true;
    row.summaryHasAudio = true;
    row.summaryHasImage = true;

    assert(isAudioPreviewCandidate(row));
    assert(!isImagePreviewCandidate(row));

    row.summaryHasVideo = true;
    assert(isVideoPreviewCandidate(row));
    assert(!isAudioPreviewCandidate(row));
}

@("archive and torrent type hints select structured previews instead of hex")
unittest
{
    import dosierskanilo.metadata.torrentinfo : TorrentInfo;
    import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob;

    auto torrentBlob = new NamedBinaryBlob();
    torrentBlob.fileType = "BitTorrent file";
    torrentBlob.torrentInfo = new TorrentInfo();
    torrentBlob.torrentInfo.name = "Example bundle";
    torrentBlob.torrentInfo.totalSize = 4096;
    torrentBlob.torrentInfo.magnetURI = "magnet:?xt=urn:btih:example";
    BlobRow torrentRow;
    torrentRow.sourceBlob = torrentBlob;
    torrentRow.primaryFileName = "download.data";
    torrentRow.fileSize = 512;
    assert(previewContentKind(torrentRow) == PreviewContentKind.torrent);
    auto torrentSummary = containerPreviewSummary(torrentRow,
        PreviewContentKind.torrent);
    assert(torrentSummary.canFind("BitTorrent file"));
    assert(torrentSummary.canFind("Example bundle"));
    assert(torrentSummary.canFind("magnet:?xt=urn:btih:example"));

    auto archiveBlob = new NamedBinaryBlob();
    archiveBlob.fileType = "RAR archive data";
    BlobRow archiveRow;
    archiveRow.sourceBlob = archiveBlob;
    archiveRow.primaryFileName = "download.data";
    archiveRow.fileSize = 1024;
    assert(previewContentKind(archiveRow) == PreviewContentKind.archive);
    auto archiveSummary = containerPreviewSummary(archiveRow,
        PreviewContentKind.archive);
    assert(archiveSummary.canFind("RAR archive data"));
    assert(archiveSummary.canFind("not been indexed"));

    archiveRow.primaryFileName = "download.zip";
    archiveBlob.fileType = "application/octet-stream";
    assert(previewContentKind(archiveRow) == PreviewContentKind.archive,
        "archive extensions remain a fallback hint when `file` is inconclusive");
}

@("archive and torrent details summarize metadata without repeating entry lists")
unittest
{
    import dosierskanilo.metadata.torrentinfo : TorrentFileEntry, TorrentInfo;
    import dosierskanilo.model.archivespec : ArchiveSpec, CheckSums;
    import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob;
    import std.datetime.systime : SysTime;

    auto archiveBlob = new NamedBinaryBlob("bundle.zip", 1_500, SysTime(1_000));
    archiveBlob.archiveSpecs = [
        new ArchiveSpec("small.txt", 500, "", CheckSums("md5", "sha1", "xxh64")),
        new ArchiveSpec("large.bin", 1_000, "", CheckSums())
    ];
    BlobRow archiveRow;
    archiveRow.sourceBlob = archiveBlob;
    archiveRow.primaryFileName = "bundle.zip";
    archiveRow.fileSize = 1_500;
    auto archiveSummary = archiveMetadataSummary(archiveRow);
    assert(archiveSummary.canFind("Total expanded size: 1500 bytes"));
    assert(archiveSummary.canFind("Largest entry: large.bin (1000 bytes)"));
    assert(archiveSummary.canFind("Entries with all checksums: 1"));
    assert(!archiveSummary.canFind("small.txt"));

    auto torrentBlob = new NamedBinaryBlob("bundle.torrent", 100, SysTime(2_000));
    torrentBlob.torrentInfo = new TorrentInfo();
    torrentBlob.torrentInfo.name = "Example bundle";
    torrentBlob.torrentInfo.isMultiFile = true;
    torrentBlob.torrentInfo.totalSize = 4096;
    torrentBlob.torrentInfo.infoHashHex = "deadbeef";
    torrentBlob.torrentInfo.announce = "https://tracker.example/announce";
    torrentBlob.torrentInfo.pieceLength = 16384;
    torrentBlob.torrentInfo.piecesCount = 1;
    torrentBlob.torrentInfo.files = [new TorrentFileEntry()];
    torrentBlob.torrentInfo.files[0].path = ["folder", "payload.bin"];
    torrentBlob.torrentInfo.files[0].length = 4096;
    BlobRow torrentRow;
    torrentRow.sourceBlob = torrentBlob;
    torrentRow.primaryFileName = "bundle.torrent";
    auto torrentSummary = torrentMetadataSummary(torrentRow);
    assert(torrentSummary.canFind("Mode: multi-file"));
    assert(torrentSummary.canFind("Announce: https://tracker.example/announce"));
    assert(torrentSummary.canFind("Piece length: 16384 bytes"));
    assert(!torrentSummary.canFind("payload.bin"));
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
    if (isImagePreviewCandidate(row) || isVideoPreviewCandidate(row)
        || isAudioPreviewCandidate(row))
    {
        reason = previewPath.length == 0
            ? "No source file path is recorded for this item."
            : "The preview decoder could not open the referenced file or format.";
    }
    else if (row.hasText)
    {
        reason = "The GUI preview currently supports images, audio, and video, not this media stream.";
    }
    else
    {
        reason = "No supported image, audio, or video preview handler was found for this file type.";
    }

    return format("Preview unavailable\nFile: %s\nPath: %s\nSize: %s bytes\nType: %s\nReason: %s",
        fileName, previewPath.length > 0 ? previewPath : "-", row.fileSize, type, reason);
}

private string previewFileCheckFailure(string path, string error)
{
    return error.length > 0
        ? format("Could not check referenced file:\n%s\n%s", path, error)
        : format("Referenced file is missing:\n%s", path);
}

private string previewHexDump(const(ubyte)[] bytes, bool truncated)
{
    if (bytes.length == 0)
        return "The file is empty.";
    auto shownBytes = bytes.length > PREVIEW_HEX_DUMP_BYTES
        ? bytes[0 .. PREVIEW_HEX_DUMP_BYTES] : bytes;
    auto output = toPrettyHexDump(shownBytes);
    if (truncated || bytes.length > PREVIEW_HEX_DUMP_BYTES)
        output ~= format("\nHex dump limited to the first %s bytes.", PREVIEW_HEX_DUMP_BYTES);
    return output;
}

private string previewText(const(ubyte)[] bytes, bool truncated)
{
    if (bytes.length == 0)
        return "The text file is empty.";
    auto text = cast(string) bytes.idup;
    try
        validate(text);
    catch (Exception)
        return previewHexDump(bytes, truncated);
    text = text.replace("\0", "�");
    if (truncated)
        text ~= format("\n\nText preview limited to the first %s bytes.",
            PREVIEW_TEXT_BYTES);
    return text;
}

private string textFilePermissions(uint attributes)
{
    version (Posix)
    {
        auto mode = attributes & 0x1FF;
        char[9] permissions = "---------";
        if (mode & 0x100) permissions[0] = 'r';
        if (mode & 0x080) permissions[1] = 'w';
        if (mode & 0x040) permissions[2] = 'x';
        if (mode & 0x020) permissions[3] = 'r';
        if (mode & 0x010) permissions[4] = 'w';
        if (mode & 0x008) permissions[5] = 'x';
        if (mode & 0x004) permissions[6] = 'r';
        if (mode & 0x002) permissions[7] = 'w';
        if (mode & 0x001) permissions[8] = 'x';
        return format("%03o (%s)", mode, permissions[]);
    }
    else
        return format("platform attributes 0x%08X", attributes);
}

/** Compact lower-pane attributes for a text preview. */
string textFileMetadataSummary(string path, ulong size, string permissions,
    string accessedAt, string modifiedAt, string indexedModifiedAt,
    string fileType, string checksumSummary)
{
    string[] lines = ["File: " ~ path, format("Size: %s bytes", size)];
    if (permissions.length > 0)
        lines ~= "Access rights: " ~ permissions;
    if (accessedAt.length > 0)
        lines ~= "Accessed: " ~ accessedAt;
    if (modifiedAt.length > 0)
        lines ~= "Modified: " ~ modifiedAt;
    if (indexedModifiedAt.length > 0 && indexedModifiedAt != modifiedAt)
        lines ~= "Indexed modified: " ~ indexedModifiedAt;
    if (fileType.length > 0)
        lines ~= "File type: " ~ fileType;
    if (checksumSummary.length > 0)
        lines ~= "Checksums: " ~ checksumSummary;
    return lines.join("\n");
}

@("text previews preserve multiline UTF-8 and fall back to hex for invalid data")
unittest
{
    auto textBytes = cast(const(ubyte)[]) "line one\nline two";
    assert(previewText(textBytes, false) == "line one\nline two");

    ubyte[] invalid = [0xFF, 0x00, 0x41];
    assert(previewText(invalid, false).canFind("ff 00 41"));
}

@("text preview metadata is compact and includes filesystem attributes")
unittest
{
    auto summary = textFileMetadataSummary("docs/readme.txt", 1234,
        "0640 (rw-r-----)", "2026-10-07T12:00:00", "2026-10-07T12:30:00",
        "2026-10-07T12:29:00", "UTF-8 text", "full");
    assert(summary.canFind("File: docs/readme.txt"));
    assert(summary.canFind("Access rights: 0640 (rw-r-----)"));
    assert(summary.canFind("Accessed: 2026-10-07T12:00:00"));
    assert(summary.canFind("Modified: 2026-10-07T12:30:00"));
    assert(summary.canFind("Indexed modified: 2026-10-07T12:29:00"));
    assert(summary.canFind("File type: UTF-8 text"));
    assert(summary.canFind("Checksums: full"));
}

@("text preview accepts file signatures and uses a bounded UTF-8 text prefix")
unittest
{
    import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob;

    auto blob = new NamedBinaryBlob();
    blob.fileType = "ASCII text, with line terminators";
    BlobRow row;
    row.sourceBlob = blob;
    row.primaryFileName = "unknown.data";
    assert(isTextPreviewCandidate(row));
    assert(previewText(cast(const(ubyte)[])"line one\nline two", false)
        == "line one\nline two");
    assert(previewText(cast(const(ubyte)[])"text", true)
        .canFind("limited to the first"));
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
    document.previewVideoPlayerAudioOnly = false;
    document.previewVideoPendingWindowSync = false;
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
    auto audioOnly = document.selectedPreviewIsAudio;
    if (document.previewVideoPlayer !is null && document.previewVideoSink !is null
        && document.previewVideoPlayerAudioOnly == audioOnly)
    {
        return true;
    }

    if (document.previewVideoPlayer !is null)
    {
        stopVideoPreview(document);
    }

    auto player = ElementFactory.make("playbin", "preview-playbin");
    if (player is null)
    {
        return false;
    }

    Element sink;
    auto usesOverlay = false;
    if (audioOnly)
    {
        sink = ElementFactory.make("fakesink", "preview-audio-video-sink");
        if (sink is null)
        {
            return false;
        }
    }
    else
    {
        sink = ElementFactory.make("gtksink", "preview-videosink");
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
    document.previewVideoPlayerAudioOnly = audioOnly;
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
    document.detailPreviewPlayButton.setTooltipText(playing ? "Wiedergabe pausieren" : "Wiedergabe starten");
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
/** Start playback for the active preview.
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

/** Pause playback for the active preview.
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

/** Start or restart the embedded audio/video preview for the current selection. */
private void updatePreviewVideo(DocumentTab document)
{
    if (document.selectedPreviewIsAudio)
    {
        if (document.selectedPreviewPath.length == 0 || !ensureVideoPreviewPlayer(document))
        {
            stopVideoPreview(document);
            return;
        }

        auto uri = toFileUri(document.selectedPreviewPath);
        if (uri.length == 0)
        {
            stopVideoPreview(document);
            return;
        }

        document.previewVideoPlayer.setState(GstState.NULL);
        setVideoPreviewVolume(document, document.previewVideoVolume);
        document.previewVideoPlayer.setProperty("uri", new Value(uri));
        document.previewVideoPlayer.setState(GstState.PAUSED);
        syncVideoPlaybackButton(document, false);
        syncVideoTrackSelectors(document);
        cast(void) syncVideoPreviewPosition(document);
        if (document.previewVideoAutostart)
        {
            document.previewVideoPlayer.setState(GstState.PLAYING);
            syncVideoPlaybackButton(document, true);
        }
        return;
    }

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
    auto frameWidth = document.detailPreviewVideoFrame.getAllocatedWidth();
    auto frameHeight = document.detailPreviewVideoFrame.getAllocatedHeight();
    if (frameWidth <= 1 || frameHeight <= 1
        || !syncVideoPreviewWindow(document, frameWidth, frameHeight))
    {
        document.previewVideoPlayer.setState(GstState.READY);
        document.previewVideoPendingWindowSync = true;
        syncVideoTrackSelectors(document);
        return;
    }
    document.previewVideoPendingWindowSync = false;

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

/** Start a video that had to wait for the preview frame to be realized and sized. */
void resumePendingVideoPreview(DocumentTab document)
{
    if (document is null || !document.previewVideoPendingWindowSync
        || !document.selectedPreviewIsVideo || document.previewVideoPlayer is null
        || document.detailPreviewVideoFrame is null)
        return;

    auto width = document.detailPreviewVideoFrame.getAllocatedWidth();
    auto height = document.detailPreviewVideoFrame.getAllocatedHeight();
    if (width <= 1 || height <= 1 || !syncVideoPreviewWindow(document, width, height))
        return;

    document.previewVideoPendingWindowSync = false;
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
            document.detailPreviewTitle.setText("Preview unavailable");
            document.detailPreviewSummary.setText(format(
                "Image decoder could not open the referenced file:\n%s",
                document.selectedPreviewPath));
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
    if (document.previewPathCheckPending)
        return;

    if (document.selectedPreviewIsArchive || document.selectedPreviewIsTorrent)
    {
        stopVideoPreview(document);
        syncVideoTrackSelectors(document);
        if (document.detailPreviewImageControls !is null)
            document.detailPreviewImageControls.setVisible(false);
        if (document.detailPreviewScroll !is null)
            document.detailPreviewScroll.setVisible(false);
        if (document.detailPreviewVideoFrame !is null)
            document.detailPreviewVideoFrame.setVisible(false);
        if (document.detailPreviewVideoControls !is null)
            document.detailPreviewVideoControls.setVisible(false);
        if (document.detailPreviewArchiveScroll !is null)
            document.detailPreviewArchiveScroll.setVisible(
                document.selectedPreviewIsArchive);
        if (document.detailPreviewTorrentScroll !is null)
            document.detailPreviewTorrentScroll.setVisible(
                document.selectedPreviewIsTorrent);
        document.detailPreviewImage.clear();
        return;
    }

    if (document.selectedPreviewIsText)
    {
        stopVideoPreview(document);
        if (document.detailPreviewImageControls !is null)
            document.detailPreviewImageControls.setVisible(false);
        if (document.detailPreviewScroll !is null)
            document.detailPreviewScroll.setVisible(false);
        if (document.detailPreviewVideoFrame !is null)
            document.detailPreviewVideoFrame.setVisible(false);
        if (document.detailPreviewVideoControls !is null)
            document.detailPreviewVideoControls.setVisible(false);
        if (document.detailPreviewTextScroll !is null)
            document.detailPreviewTextScroll.setVisible(true);
        document.detailPreviewImage.clear();
        return;
    }

    if (document.selectedPreviewIsVideo || document.selectedPreviewIsAudio)
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
        if (document.selectedPreviewIsVideo)
        {
            updatePreviewVideo(document);
        }
        else
        {
            updatePreviewVideo(document);
            if (document.detailPreviewVideoFrame !is null)
            {
                document.detailPreviewVideoFrame.setVisible(false);
            }
        }
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
    import core.thread : Thread;
    import glib.Idle;
    import std.datetime.systime : SysTime;
    import std.file : exists, getAttributes, getSize, getTimes, read;

    document.detailPreviewTitle.setText("Preview");
    setPreviewSummaryMonospace(document.detailPreviewSummary, false);
    auto requestId = ++document.previewPathRequestId;
    document.previewPathCheckPending = false;
    if (document.detailPreviewTextView !is null)
        document.detailPreviewTextView.getBuffer().setText("");

    auto fileName = row.primaryFileName.length > 0 ? row.primaryFileName : "-";
    auto mediaSummary = row.mediaInfoDetails.length > 0 ? row.mediaInfoDetails : "No media metadata available.";
    auto previewPath = resolvePreviewPath(document, row);
    auto previewKind = previewContentKind(row);

    document.selectedPreviewSourcePath = "";
    document.selectedPreviewSourcePixbuf = null;
    document.selectedPreviewIsText = false;
    document.selectedPreviewIsArchive = previewKind == PreviewContentKind.archive;
    document.selectedPreviewIsTorrent = previewKind == PreviewContentKind.torrent;
    if (document.detailPreviewTextScroll !is null)
        document.detailPreviewTextScroll.setVisible(false);
    if (document.detailPreviewArchiveScroll !is null)
        document.detailPreviewArchiveScroll.setVisible(false);
    if (document.detailPreviewTorrentScroll !is null)
        document.detailPreviewTorrentScroll.setVisible(false);
    document.selectedPreviewIsVideo = previewPath.length > 0
        && previewKind == PreviewContentKind.video;
    document.selectedPreviewIsAudio = !document.selectedPreviewIsVideo
        && previewPath.length > 0 && previewKind == PreviewContentKind.audio;
    document.selectedPreviewIsImage = !document.selectedPreviewIsVideo
        && !document.selectedPreviewIsAudio
        && previewPath.length > 0 && previewKind == PreviewContentKind.image;
    document.selectedPreviewPath = previewPath;

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

    if (previewKind == PreviewContentKind.torrent
        || previewKind == PreviewContentKind.archive)
    {
        document.previewPathCheckPending = false;
        refreshMediaPreview(document);
        document.detailPreviewTitle.setText(previewKind == PreviewContentKind.torrent
            ? "Torrent overview" : "Archive overview");
        setPreviewSummaryMonospace(document.detailPreviewSummary, false);
        document.detailPreviewSummary.setText(containerPreviewSummary(row, previewKind));
        if (document.detailPreviewArchiveScroll !is null)
            document.detailPreviewArchiveScroll.setVisible(
                previewKind == PreviewContentKind.archive);
        if (document.detailPreviewTorrentScroll !is null)
            document.detailPreviewTorrentScroll.setVisible(
                previewKind == PreviewContentKind.torrent);
        return;
    }

    if (document.selectedPreviewIsImage)
    {
        document.detailPreviewSummary.setText(format("Image preview\n%s", fileName));
    }
    else if (document.selectedPreviewIsVideo)
    {
        document.detailPreviewSummary.setText(format("Video preview\n%s", mediaSummary));
    }
    else if (document.selectedPreviewIsAudio)
    {
        document.detailPreviewSummary.setText(format("Audio preview\n%s", mediaSummary));
    }
    else if (previewPath.length == 0)
    {
        document.detailPreviewImage.clear();

        document.detailPreviewTitle.setText("Preview unavailable");
        document.detailPreviewSummary.setText(unavailablePreviewSummary(row, fileName,
            previewPath));
        refreshMediaPreview(document);
        return;
    }

    document.previewPathCheckPending = true;
    stopVideoPreview(document);
    document.detailPreviewImage.clear();
    if (document.detailPreviewImageControls !is null)
        document.detailPreviewImageControls.setVisible(false);
    if (document.detailPreviewScroll !is null)
        document.detailPreviewScroll.setVisible(false);
    if (document.detailPreviewVideoFrame !is null)
        document.detailPreviewVideoFrame.setVisible(false);
    if (document.detailPreviewVideoControls !is null)
        document.detailPreviewVideoControls.setVisible(false);
    document.detailPreviewTitle.setText("Checking file...");
    document.detailPreviewSummary.setText(format("Checking referenced file:\n%s",
        previewPath));

    auto isVideo = document.selectedPreviewIsVideo;
    auto isAudio = document.selectedPreviewIsAudio;
    auto isImage = document.selectedPreviewIsImage;
    auto isText = previewKind == PreviewContentKind.text;
    auto metadataPath = document.selectedFilePath.length > 0
        ? document.selectedFilePath : fileName;
    string indexedModifiedAt = row.sourceBlob is null
        ? "" : row.sourceBlob.timeLastModified;
    if (row.sourceBlob !is null)
    {
        foreach (spec; row.sourceBlob.fileSpecs)
        {
            if (spec !is null && spec.fileName.length > 0
                && spec.fileName == metadataPath && spec.timeLastModified.length > 0)
            {
                indexedModifiedAt = spec.timeLastModified;
                break;
            }
        }
    }
    auto fileTypeMetadata = row.sourceBlob is null ? "" : row.fileTypeDetails;
    auto checksumCount = (row.md5.length > 0 ? 1 : 0)
        + (row.sha1.length > 0 ? 1 : 0) + (row.xxh64.length > 0 ? 1 : 0);
    auto checksumMetadata = checksumCount == 0 ? "none"
        : checksumCount == 3 ? "full"
        : checksumCount == 1 ? "partial (1/3)" : "partial (2/3)";
    new Thread({
        bool fileExists;
        string error;
        string previewContent;
        string textMetadata;
        try
        {
            fileExists = exists(previewPath);
            if (fileExists && !isVideo && !isAudio && !isImage)
            {
                auto byteLimit = isText ? PREVIEW_TEXT_BYTES : PREVIEW_HEX_DUMP_BYTES;
                auto data = cast(const(ubyte)[]) read(previewPath, byteLimit + 1);
                auto truncated = data.length > byteLimit;
                if (truncated)
                    data = data[0 .. byteLimit];
                previewContent = isText ? previewText(data, truncated)
                    : previewHexDump(data, truncated);
            }
            if (fileExists && isText)
            {
                try
                {
                    SysTime accessedAt;
                    SysTime modifiedAt;
                    auto attributes = getAttributes(previewPath);
                    getTimes(previewPath, accessedAt, modifiedAt);
                    textMetadata = textFileMetadataSummary(metadataPath,
                        getSize(previewPath), textFilePermissions(attributes),
                        accessedAt.toISOExtString(), modifiedAt.toISOExtString(),
                        indexedModifiedAt, fileTypeMetadata, checksumMetadata);
                }
                catch (Exception metadataError)
                {
                    textMetadata = textFileMetadataSummary(metadataPath,
                        row.fileSize, "", "", "", indexedModifiedAt,
                        fileTypeMetadata, checksumMetadata)
                        ~ "\nFilesystem attributes unavailable: " ~ metadataError.msg;
                }
            }
        }
        catch (Exception ex)
            error = ex.msg;

        new Idle({
            if (requestId != document.previewPathRequestId
                || previewPath != document.selectedPreviewPath)
                return false;
            document.previewPathCheckPending = false;
            if (error.length > 0 || !fileExists)
            {
                stopVideoPreview(document);
                document.selectedPreviewIsVideo = false;
                document.selectedPreviewIsAudio = false;
                document.selectedPreviewIsImage = false;
                document.selectedPreviewIsText = false;
                if (document.detailPreviewTextScroll !is null)
                    document.detailPreviewTextScroll.setVisible(false);
                document.detailPreviewTitle.setText(error.length > 0
                    ? "Preview file unavailable" : "File missing");
                document.detailPreviewSummary.setText(previewFileCheckFailure(
                    previewPath, error));
                return false;
            }

            if (!isVideo && !isAudio && !isImage)
            {
                if (isText)
                {
                    document.selectedPreviewIsText = true;
                    document.detailPreviewTextView.getBuffer().setText(previewContent);
                    document.detailPreviewTextScroll.setVisible(true);
                    setPreviewSummaryMonospace(document.detailPreviewSummary, false);
                    document.detailPreviewSummary.setText(textMetadata);
                    document.detailPreviewTitle.setText("Text preview");
                }
                else
                {
                    setPreviewSummaryMonospace(document.detailPreviewSummary, true);
                    document.detailPreviewTitle.setText("Hex dump preview");
                    document.detailPreviewSummary.setText(previewContent);
                }
                return false;
            }

            document.selectedPreviewIsVideo = isVideo;
            document.selectedPreviewIsAudio = isAudio;
            document.selectedPreviewIsImage = isImage;
            document.detailPreviewTitle.setText("Preview");
            document.detailPreviewSummary.setText(isVideo
                ? format("Video preview\n%s", mediaSummary)
                : isAudio ? format("Audio preview\n%s", mediaSummary)
                : format("Image preview\n%s", fileName));
            refreshMediaPreview(document);
            return false;
        });
    }).start();
}

@("preview path resolution honors the selected file alias relative to the JSON source")
unittest
{
    import dosierskanilo.model.filespec : FileSpec;
    import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob;

    auto document = new DocumentTab();
    document.filePath = "/nas/library/catalog.json";

    auto blob = new NamedBinaryBlob();
    blob.fileSpecs = [new FileSpec("archive/old-clip.mp4", ""),
        new FileSpec("media/clip.mp4", "")];
    BlobRow row;
    row.sourceBlob = blob;
    row.primaryFileName = "archive/old-clip.mp4";
    document.selectedTreeCursor.relativePath = "media/clip.mp4";

    assert(resolvePreviewPath(document, row) == "/nas/library/media/clip.mp4");
    assert(previewFileCheckFailure("/nas/missing.mp4", "").canFind("Referenced file is missing"));
    assert(previewFileCheckFailure("/nas/unavailable.mp4", "permission denied")
        .canFind("permission denied"));
}

@("unknown-file hex previews show only a bounded prefix")
unittest
{
    auto bytes = new ubyte[PREVIEW_HEX_DUMP_BYTES + 32];
    bytes[0] = 0x41;
    auto output = previewHexDump(bytes, true);
    assert(output.canFind("41"));
    assert(output.canFind("limited to the first 512 bytes"));
    assert(previewHexDump([], false) == "The file is empty.");
}
