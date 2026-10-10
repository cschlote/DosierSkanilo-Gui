/** Target-aware option dialogs for shared backend operations. */
module ui.operationdialogs;

import gtk.Box;
import gtk.CheckButton;
import gtk.Dialog;
import gtk.Label;
import gtk.Window;
import gtk.c.types : DialogFlags, Orientation, ResponseType;

import dosierskanilo.repository.types : MetadataScanOptions,
    RepositoryAnalysisOptions, RepositoryScanOptions;

enum OperationDialogKind
{
    scan,
    metadata,
    analyze
}

/** User-selected backend options for one operation. */
struct OperationDialogOptions
{
    bool accepted;
    RepositoryScanOptions scanOptions;
    MetadataScanOptions metadataOptions;
    RepositoryAnalysisOptions analysisOptions;
}

/** Show only options supported by the active source and operation. */
OperationDialogOptions showOperationOptions(Window parent, string title,
    string sourceDescription, bool repositorySource, OperationDialogKind kind)
{
    OperationDialogOptions result;
    auto dialog = new Dialog(title, parent, DialogFlags.MODAL,
        ["_Cancel", "_Start"], [ResponseType.CANCEL, ResponseType.OK]);
    auto content = dialog.getContentArea();
    auto fields = new Box(Orientation.VERTICAL, 6);
    fields.setBorderWidth(10);
    auto description = new Label("Operation target: " ~ sourceDescription);
    description.setXalign(0.0f);
    fields.packStart(description, false, false, 0);

    CheckButton recursive;
    CheckButton pickHidden;
    CheckButton dropMissing;
    CheckButton checksums;
    CheckButton fileTypes;
    CheckButton mediaInfo;
    CheckButton archives;
    CheckButton torrents;

    if (kind == OperationDialogKind.scan)
    {
        recursive = new CheckButton("Scan subdirectories");
        recursive.setActive(true);
        pickHidden = new CheckButton("Include hidden files and directories");
        fields.packStart(recursive, false, false, 0);
        fields.packStart(pickHidden, false, false, 0);
        if (repositorySource)
        {
            dropMissing = new CheckButton("Remove missing file references");
            fields.packStart(dropMissing, false, false, 0);
        }
    }
    else if (kind == OperationDialogKind.analyze && repositorySource)
    {
        dropMissing = new CheckButton("Remove missing file references");
        fields.packStart(dropMissing, false, false, 0);
    }

    auto needsMetadata = kind == OperationDialogKind.metadata
        || (kind == OperationDialogKind.scan)
        || (kind == OperationDialogKind.analyze && !repositorySource);
    if (needsMetadata)
    {
        auto label = new Label("Metadata to extract:");
        label.setXalign(0.0f);
        fields.packStart(label, false, false, 4);
        checksums = new CheckButton("Checksums");
        fileTypes = new CheckButton("File types");
        mediaInfo = new CheckButton("MediaInfo");
        archives = new CheckButton("Archive contents");
        torrents = new CheckButton("Torrent metadata");
        fields.packStart(checksums, false, false, 0);
        fields.packStart(fileTypes, false, false, 0);
        fields.packStart(mediaInfo, false, false, 0);
        fields.packStart(archives, false, false, 0);
        fields.packStart(torrents, false, false, 0);
    }

    content.packStart(fields, true, true, 0);
    dialog.showAll();
    result.accepted = dialog.run() == cast(int) ResponseType.OK;
    if (result.accepted)
    {
        if (kind == OperationDialogKind.scan)
        {
            result.scanOptions.recursive = recursive.getActive();
            result.scanOptions.pickHidden = pickHidden.getActive();
            if (dropMissing !is null)
                result.scanOptions.dropMissing = dropMissing.getActive();
        }
        if (kind == OperationDialogKind.analyze && repositorySource
            && dropMissing !is null)
            result.analysisOptions.dropMissing = dropMissing.getActive();
        result.analysisOptions.mergeDuplicates = true;
        if (checksums !is null)
            result.metadataOptions.calculateChecksums = checksums.getActive();
        if (fileTypes !is null)
            result.metadataOptions.detectFileTypes = fileTypes.getActive();
        if (mediaInfo !is null)
            result.metadataOptions.extractMediaInfo = mediaInfo.getActive();
        if (archives !is null)
            result.metadataOptions.scanArchives = archives.getActive();
        if (torrents !is null)
            result.metadataOptions.scanTorrents = torrents.getActive();
        result.metadataOptions.deepArchiveScan = false;
        result.metadataOptions.threads = 1;
    }
    dialog.destroy();
    return result;
}
