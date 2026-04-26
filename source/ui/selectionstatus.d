/** Shared status and selection helpers for document tabs. */
module ui.selectionstatus;

import std.format : format;
import std.conv : to;

import model.blobrow : BlobRow;
import ui.detailswidgets : setDetailEntry, setKnownFilesTable, setMetadataDetails,
    setMetadataStatusLabel, stopVideoPreview;
import ui.documenttab : DocumentTab;

/** Render a compact status icon for boolean table cells. */
string boolStatusIcon(bool value)
{
    return value ? "✓" : "○";
}

/** Summarize checksum availability for the row details section. */
string checksumStatusSummary(const(BlobRow) row)
{
    auto present = 0;
    if (row.md5.length > 0)
    {
        ++present;
    }
    if (row.sha1.length > 0)
    {
        ++present;
    }
    if (row.xxh64.length > 0)
    {
        ++present;
    }

    if (present == 0)
    {
        return "none";
    }
    if (present == 3)
    {
        return "full";
    }
    return format("partial (%s/3)", present);
}

/** Summarize media availability for the row details section. */
string mediaInfoStatusSummary(const(BlobRow) row)
{
    if (!row.hasMedia)
    {
        return format("%s none", boolStatusIcon(false));
    }

    return format(
        "%s present | V %s  A %s  I %s  T %s",
        boolStatusIcon(true),
        boolStatusIcon(row.hasVideo),
        boolStatusIcon(row.hasAudio),
        boolStatusIcon(row.hasImage),
        boolStatusIcon(row.hasText)
    );
}

/** Summarize a simple boolean metadata block for the row details section. */
string metadataPresenceSummary(bool value)
{
    return value ? format("%s present", boolStatusIcon(true)) : format("%s none", boolStatusIcon(false));
}

/** Refresh the performance summary label for a document tab. */
void updatePerfStatus(DocumentTab document)
{
    document.perfStatus.setText(format(
            "Timings: load=%s ms | filter=%s ms | render=%s ms",
            document.lastLoadElapsedMs >= 0 ? to!string(document.lastLoadElapsedMs) : "-",
            document.lastFilterElapsedMs >= 0 ? to!string(document.lastFilterElapsedMs) : "-",
            document.lastRenderElapsedMs >= 0 ? to!string(document.lastRenderElapsedMs) : "-"
    ));
}

/** Refresh the metadata status label for a document tab. */
void updateFileMetaStatus(DocumentTab document)
{
    auto dataVersionText = document.loadedDataVersion >= 0 ? to!string(document.loadedDataVersion) : "-";
    document.fileMetaStatus.setText(format(
            "File metadata: version=%s | root=%s | keys=%s",
            dataVersionText,
            document.loadedRootShape,
            document.loadedRootKeysSummary
    ));
}

/** Clear all active filter flags and the filter query for a document tab. */
void resetFilterState(DocumentTab document)
{
    document.filterQuery = "";
    document.filterVideo = false;
    document.filterAudio = false;
    document.filterImage = false;
    document.filterText = false;
    document.filterMediaNegated = false;
    document.filterFileType = false;
    document.filterArchive = false;
    document.filterTorrent = false;
}

/** Clear the timing counters shown in the performance status for a document tab. */
void resetPerfMetrics(DocumentTab document)
{
    document.lastLoadElapsedMs = -1;
    document.lastFilterElapsedMs = -1;
    document.lastRenderElapsedMs = -1;
    updatePerfStatus(document);
    document.status.setText("Performance metrics reset.");
}

/** Reset selection-dependent detail widgets to their placeholder state. */
void clearSelectionDetails(DocumentTab document)
{
    document.selectedSha1 = "";
    document.selectedFileName = "";
    document.selectedDetailsText = "";
    document.selectedPreviewPath = "";
    document.selectedPreviewIsImage = false;
    document.selectedPreviewIsVideo = false;
    document.selectedPreviewCandidatePath = "";
    document.selectedPreviewCandidateExists = false;
    document.selectedPreviewSourcePath = "";
    document.selectedPreviewSourcePixbuf = null;
    setDetailEntry(document.detailSha1HexEntry, "");
    setDetailEntry(document.detailMd5HexEntry, "");
    setDetailEntry(document.detailXxh64HexEntry, "");
    setDetailEntry(document.detailIndexEntry, "");
    setDetailEntry(document.detailSizeEntry, "");
    setMetadataStatusLabel(document.detailChecksumStatus, "Checksums", checksumStatusSummary(
            BlobRow.init));
    document.detailChecksumExpander.setSensitive(false);
    document.detailChecksumExpander.setExpanded(false);
    setMetadataStatusLabel(document.detailMediaInfoStatus, "MediaInfo", format("%s unavailable", boolStatusIcon(
            false)));
    setMetadataStatusLabel(document.detailFileTypeStatus, "File Type", format("%s unavailable", boolStatusIcon(
            false)));
    setMetadataStatusLabel(document.detailArchiveStatus, "Archive", format("%s unavailable", boolStatusIcon(
            false)));
    setMetadataStatusLabel(document.detailTorrentStatus, "Torrent", format("%s unavailable", boolStatusIcon(
            false)));
    setMetadataDetails(document.detailMediaInfoExpander, document.detailMediaInfoView, "MediaInfo", "");
    setMetadataDetails(document.detailFileTypeExpander, document.detailFileTypeView, "File Type", "");
    setMetadataDetails(document.detailArchiveExpander, document.detailArchiveView, "Archive", "");
    setMetadataDetails(document.detailTorrentExpander, document.detailTorrentView, "Torrent", "");
    setKnownFilesTable(document, BlobRow.init);
    if (document.detailPreviewImage !is null)
    {
        document.detailPreviewImage.clear();
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
    if (document.detailPreviewSummary !is null)
    {
        document.detailPreviewSummary.setText("No preview available.");
    }
    document.btnCopySha1.setSensitive(false);
    document.btnCopyFile.setSensitive(false);
    document.btnCopyDetails.setSensitive(false);
    document.rowDetails.setText("Selection: none");
}