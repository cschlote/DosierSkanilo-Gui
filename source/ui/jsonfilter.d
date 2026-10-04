/** Pure JSON-row filtering and directory projection, safe for worker threads. */
module ui.jsonfilter;

import std.array : appender;

import model.blobrow : BlobRow;
import model.treeprojection : DirectoryTree, FileInput, buildDirectoryTree;
import view.textreport : filterRowsByText;

/** Filter options for a loaded JSON catalog. */
struct JsonFilterOptions
{
    string text;
    bool caseSensitive;
    bool video;
    bool audio;
    bool image;
    bool textStream;
    bool mediaNegated;
    bool fileType;
    bool archive;
    bool torrent;
}

/** A filtered row subset and its matching directory projection. */
struct JsonFilterResult
{
    BlobRow[] rows;
    DirectoryTree tree;
}

/** Filter rows and construct their tree without touching GTK state. */
JsonFilterResult filterJsonRows(const(BlobRow)[] sourceRows,
    JsonFilterOptions options)
{
    JsonFilterResult result;
    result.rows = filterRowsByText(sourceRows, options.text, options.caseSensitive);

    auto hasMediaRequirements = options.video || options.audio || options.image
        || options.textStream;
    auto hasOtherRequirements = options.fileType || options.archive || options.torrent;
    if (hasMediaRequirements || hasOtherRequirements)
    {
        auto filtered = appender!(BlobRow[])();
        foreach (row; result.rows)
        {
            auto matchesMedia = (options.video && row.hasVideo)
                || (options.audio && row.hasAudio)
                || (options.image && row.hasImage)
                || (options.textStream && row.hasText);
            if (options.mediaNegated)
                matchesMedia = !matchesMedia;

            auto matchesOther = (options.fileType && row.hasFileType)
                || (options.archive && row.hasArchive)
                || (options.torrent && row.hasTorrent);
            if ((!hasMediaRequirements || matchesMedia)
                && (!hasOtherRequirements || matchesOther))
                filtered.put(row);
        }
        result.rows = filtered.data;
    }

    result.tree = projectRowsToDirectoryTree(result.rows);
    return result;
}

/** Build a tree from the source file references represented by blob rows. */
DirectoryTree projectRowsToDirectoryTree(const(BlobRow)[] rows)
{
    FileInput[] inputs;
    foreach (row; rows)
    {
        if (row.sourceBlob is null)
            continue;
        foreach (spec; row.sourceBlob.fileSpecs)
        {
            if (spec !is null && spec.fileName.length > 0)
                inputs ~= FileInput(spec.fileName, cast(ulong) row.fileSize,
                    row.hasFileType, row.hasMedia, row.hasVideo, row.hasAudio,
                    row.hasImage, row.hasText, row.hasArchive, row.hasTorrent);
        }
        if (row.sourceBlob.fileSpecs.length == 0 && row.primaryFileName.length > 0)
            inputs ~= FileInput(row.primaryFileName, row.fileSize,
                row.hasFileType, row.hasMedia, row.hasVideo, row.hasAudio,
                row.hasImage, row.hasText, row.hasArchive, row.hasTorrent);
    }
    return buildDirectoryTree(inputs);
}

@("JSON filtering combines text, media negation, presence flags, and tree projection")
unittest
{
    import std.datetime.systime : SysTime;
    import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob;

    auto videoBlob = new NamedBinaryBlob("Folder/Alpha.mkv", 100, SysTime(1_000));
    auto archiveBlob = new NamedBinaryBlob("Folder/Beta.zip", 200, SysTime(2_000));
    auto plainBlob = new NamedBinaryBlob("Other/Gamma.txt", 50, SysTime(3_000));
    BlobRow videoRow;
    videoRow.sourceBlob = videoBlob;
    videoRow.primaryFileName = "Folder/Alpha.mkv";
    videoRow.fileSize = 100;
    videoRow.sha1 = "ABC123";
    videoRow.fileCount = 1;
    videoRow.hasSummaryFlags = true;
    videoRow.summaryHasFileType = true;
    videoRow.summaryHasMedia = true;
    videoRow.summaryHasVideo = true;

    BlobRow archiveRow;
    archiveRow.sourceBlob = archiveBlob;
    archiveRow.primaryFileName = "Folder/Beta.zip";
    archiveRow.fileSize = 200;
    archiveRow.sha1 = "DEF456";
    archiveRow.fileCount = 1;
    archiveRow.hasSummaryFlags = true;
    archiveRow.summaryHasFileType = true;
    archiveRow.summaryHasArchive = true;

    BlobRow plainRow;
    plainRow.sourceBlob = plainBlob;
    plainRow.primaryFileName = "Other/Gamma.txt";
    plainRow.fileSize = 50;
    plainRow.sha1 = "GHI789";
    plainRow.fileCount = 1;
    plainRow.hasSummaryFlags = true;

    BlobRow[] rows = [videoRow, archiveRow, plainRow];

    JsonFilterOptions caseSensitive;
    caseSensitive.text = "ALPHA";
    caseSensitive.caseSensitive = true;
    assert(filterJsonRows(rows, caseSensitive).rows.length == 0);
    caseSensitive.caseSensitive = false;
    auto textResult = filterJsonRows(rows, caseSensitive);
    assert(textResult.rows.length == 1);
    assert(textResult.rows[0].primaryFileName == "Folder/Alpha.mkv");
    assert(textResult.tree.files.length == 1);

    JsonFilterOptions videoOnly;
    videoOnly.video = true;
    auto videoResult = filterJsonRows(rows, videoOnly);
    assert(videoResult.rows.length == 1);
    assert(videoResult.tree.files.length == 1);
    assert(videoResult.tree.files[0].hasVideo);

    videoOnly.mediaNegated = true;
    auto notVideoResult = filterJsonRows(rows, videoOnly);
    assert(notVideoResult.rows.length == 2);
    assert(notVideoResult.tree.files.length == 2);

    JsonFilterOptions videoAndArchive;
    videoAndArchive.video = true;
    videoAndArchive.archive = true;
    assert(filterJsonRows(rows, videoAndArchive).rows.length == 0,
        "media requirements combine with presence requirements using AND");

    JsonFilterOptions archiveOrFileType;
    archiveOrFileType.archive = true;
    archiveOrFileType.fileType = true;
    auto presenceResult = filterJsonRows(rows, archiveOrFileType);
    assert(presenceResult.rows.length == 2,
        "presence toggles within their group combine using OR");
}
