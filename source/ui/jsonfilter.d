/** Pure JSON-row filtering and directory projection, safe for worker threads.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.jsonfilter;

import std.array : appender;
import std.algorithm : canFind;
import std.string : strip, toLower;

import dosierarkivo.archive : parseArchiveVirtualPath;
import model.blobrow : BlobRow;
import model.treeprojection : DirectoryNode, DirectoryTree, FileInput,
    FileFilter, buildDirectoryTree, isArchivePathCandidate, jsonFileNodeId;
import ui.directorytreefilter : treeFileMatchesFilter;

/** Filter options for a loaded JSON catalog. */
struct JsonFilterOptions
{
    /// Free-text query matched against primary file names and SHA-1 hashes.
    string text;
    /// Whether the text query is matched case-sensitively.
    bool caseSensitive;
    /// Require the video media flag when a media requirement is active.
    bool video;
    /// Require the audio media flag when a media requirement is active.
    bool audio;
    /// Require the image media flag when a media requirement is active.
    bool image;
    /// Require the text media flag when a media requirement is active.
    bool textStream;
    /// Invert the combined media requirement, hiding rows that match it.
    bool mediaNegated;
    /// Require the file-type summary flag.
    bool fileType;
    /// Require the archive summary flag.
    bool archive;
    /// Require the torrent summary flag.
    bool torrent;
}

/** Filtered rows and compact stable-ID visibility state for the directory tree. */
struct JsonFilterResult
{
    /// Rows that passed the filter, preserving source order.
    BlobRow[] rows;
    /// One flag per tree file, indexed by the file's `sourceIndex`.
    bool[] visibleTreeFileIndexes;
    /// One flag per tree directory, indexed by the directory's `sourceIndex`.
    bool[] visibleTreeDirectoryIndexes;
    /// Number of directly matching files per directory.
    size_t[] visibleDirectoryFileCounts;
    /// Total size in bytes of matching files per directory subtree.
    ulong[] visibleDirectoryAggregateSizes;
    /// Number of visible immediate child directories per directory.
    size_t[] visibleDirectoryChildCounts;
    /// Whether at least one tree file matched the filter.
    bool hasVisibleTreeMatches;
}

/** Filter rows and calculate tree visibility without touching GTK state.
 *
 * Text, media, and other presence requirements are combined with AND between
 * groups; toggles inside the media group and the other presence group are
 * combined with OR. Tree visibility is computed independently of the returned
 * row order.
 *
 * Params:
 *     sourceRows = Rows to filter, usually the fully loaded catalog rows.
 *     sourceTree = Canonical directory tree whose visibility is calculated.
 *     options = Text, media, and presence filters to apply.
 * Returns: The matching rows in source order plus compact file and directory
 *     visibility arrays for `sourceTree`.
 */
JsonFilterResult filterJsonRows(const(BlobRow)[] sourceRows,
    const(DirectoryTree) sourceTree,
    JsonFilterOptions options)
{
    JsonFilterResult result;
    auto query = options.text.strip;
    auto hasTextFilter = query.length > 0;
    if (hasTextFilter && !options.caseSensitive)
        query = query.toLower;
    auto hasMediaRequirements = options.video || options.audio || options.image
        || options.textStream;
    auto hasOtherRequirements = options.fileType || options.archive || options.torrent;
    auto filteredRows = appender!(BlobRow[])();
    foreach (row; sourceRows)
    {
        if (hasTextFilter)
        {
            auto fileName = options.caseSensitive
                ? row.primaryFileName : row.primaryFileName.toLower;
            auto sha1 = options.caseSensitive ? row.sha1 : row.sha1.toLower;
            if (!fileName.canFind(query) && !sha1.canFind(query))
                continue;
        }

        auto matchesMedia = (options.video && row.hasVideo)
            || (options.audio && row.hasAudio)
            || (options.image && row.hasImage)
            || (options.textStream && row.hasText);
        if (hasMediaRequirements
            && (options.mediaNegated ? matchesMedia : !matchesMedia))
            continue;

        auto matchesOther = (options.fileType && row.hasFileType)
            || (options.archive && row.hasArchive)
            || (options.torrent && row.hasTorrent);
        if (hasOtherRequirements && !matchesOther)
            continue;
        filteredRows.put(row);
    }
    result.rows = filteredRows.data;

    auto treeIndex = treeFilterIndex(sourceTree, options);
    result.visibleTreeFileIndexes = treeIndex.visibleFiles;
    result.visibleTreeDirectoryIndexes = treeIndex.visibleDirectories;
    result.visibleDirectoryFileCounts = treeIndex.directoryFileCounts;
    result.visibleDirectoryAggregateSizes = treeIndex.directoryAggregateSizes;
    result.visibleDirectoryChildCounts = treeIndex.directoryChildCounts;
    result.hasVisibleTreeMatches = treeIndex.hasMatches;
    return result;
}

/// Compact per-element visibility and summary data computed for the tree.
private struct JsonTreeFilterIndex
{
    /// One flag per tree file, indexed by the file's `sourceIndex`.
    bool[] visibleFiles;
    /// One flag per tree directory, indexed by the directory's `sourceIndex`.
    bool[] visibleDirectories;
    /// Number of directly matching files per directory.
    size_t[] directoryFileCounts;
    /// Total size in bytes of matching files per directory subtree.
    ulong[] directoryAggregateSizes;
    /// Number of visible immediate child directories per directory.
    size_t[] directoryChildCounts;
    /// Whether at least one file matched the filter.
    bool hasMatches;
}

/** Compute compact filter bitmaps and summaries in place over the canonical tree.
 *
 * Params:
 *     tree = Canonical directory tree to evaluate.
 *     options = Filters applied to each file in the tree.
 * Returns: Visibility arrays sized to the tree, with the root directory marked
 *     visible. When the tree has no directories, all arrays are empty or zero.
 */
private JsonTreeFilterIndex treeFilterIndex(const(DirectoryTree) tree,
    JsonFilterOptions options)
{
    JsonTreeFilterIndex result;
    result.visibleFiles = new bool[tree.files.length];
    result.visibleDirectories = new bool[tree.directories.length];
    result.directoryFileCounts = new size_t[tree.directories.length];
    result.directoryAggregateSizes = new ulong[tree.directories.length];
    result.directoryChildCounts = new size_t[tree.directories.length];
    if (tree.directories.length == 0)
        return result;
    result.visibleDirectories[0] = true;
    FileFilter filter;
    filter.text = options.text;
    filter.caseSensitive = options.caseSensitive;
    filter.video = options.video;
    filter.audio = options.audio;
    filter.image = options.image;
    filter.textStream = options.textStream;
    filter.mediaNegated = options.mediaNegated;
    filter.fileType = options.fileType;
    filter.archive = options.archive;
    filter.torrent = options.torrent;
    foreach (file; tree.files)
    {
        if (!treeFileMatchesFilter(file.name, file.relativePath, file.hasVideo,
                file.hasAudio, file.hasImage, file.hasText, file.hasFileType,
                file.hasArchive, file.hasTorrent, filter))
            continue;
        result.hasMatches = true;
        result.visibleFiles[file.sourceIndex] = true;
        ++result.directoryFileCounts[file.parentIndex];
        size_t directoryIndex = file.parentIndex;
        while (true)
        {
            result.visibleDirectories[directoryIndex] = true;
            result.directoryAggregateSizes[directoryIndex] += file.size;
            if (directoryIndex == 0)
                break;
            directoryIndex = tree.directories[directoryIndex].parentIndex;
        }
    }
    foreach (directoryIndex; 1 .. tree.directories.length)
        if (result.visibleDirectories[directoryIndex])
            ++result.directoryChildCounts[tree.directories[directoryIndex].parentIndex];
    return result;
}

/** Build a tree from the source file references represented by blob rows.
 *
 * Rows without a source blob are skipped. Virtual archive member paths are
 * omitted, while physical archive file paths are kept and marked as archives.
 *
 * Params:
 *     rows = Blob rows whose source file references form the tree.
 * Returns: A directory tree built from the retained physical file references;
 *     an empty row list yields an empty tree.
 */
DirectoryTree projectRowsToDirectoryTree(const(BlobRow)[] rows)
{
    FileInput[] inputs;
    foreach (rowIndex, row; rows)
    {
        if (row.sourceBlob is null)
            continue;
        auto sourceOrdinal = row.sourceOrdinal == size_t.max
            ? rowIndex : row.sourceOrdinal;
        foreach (referenceIndex, spec; row.sourceBlob.fileSpecs)
        {
            if (spec !is null && spec.fileName.length > 0)
            {
                string path = spec.fileName;
                if (row.sourceBlob.fileSpecsUseArchiveVirtualGrammar)
                {
                    try
                    {
                        auto parsed = parseArchiveVirtualPath(path);
                        if (parsed.isVirtual)
                            continue;
                        path = parsed.physicalPath;
                    }
                    catch (Exception)
                        continue;
                }
                inputs ~= FileInput(path, cast(ulong) row.fileSize,
                    row.hasFileType, row.hasMedia, row.hasVideo, row.hasAudio,
                    row.hasImage, row.hasText,
                    row.hasArchive || isArchivePathCandidate(path), row.hasTorrent,
                    jsonFileNodeId(sourceOrdinal, referenceIndex));
            }
        }
        if (row.sourceBlob.fileSpecs.length == 0 && row.primaryFileName.length > 0)
            inputs ~= FileInput(row.primaryFileName, row.fileSize,
                row.hasFileType, row.hasMedia, row.hasVideo, row.hasAudio,
                row.hasImage, row.hasText, row.hasArchive, row.hasTorrent,
                jsonFileNodeId(sourceOrdinal, 0));
    }
    return buildDirectoryTree(inputs);
}

@("JSON filtering combines row predicates and compact tree visibility bitmaps")
unittest
{
    import std.datetime.systime : SysTime;
    import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob;

    auto videoBlob = new NamedBinaryBlob("Folder/Alpha.mkv", 100, SysTime(1_000));
    auto archiveBlob = new NamedBinaryBlob("Folder/Beta.zip", 200, SysTime(2_000));
    auto plainBlob = new NamedBinaryBlob("Other/Gamma.txt", 50, SysTime(3_000));
    BlobRow videoRow;
    videoRow.sourceOrdinal = 0;
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
    archiveRow.sourceOrdinal = 1;
    archiveRow.sourceBlob = archiveBlob;
    archiveRow.primaryFileName = "Folder/Beta.zip";
    archiveRow.fileSize = 200;
    archiveRow.sha1 = "DEF456";
    archiveRow.fileCount = 1;
    archiveRow.hasSummaryFlags = true;
    archiveRow.summaryHasFileType = true;
    archiveRow.summaryHasArchive = true;

    BlobRow plainRow;
    plainRow.sourceOrdinal = 2;
    plainRow.sourceBlob = plainBlob;
    plainRow.primaryFileName = "Other/Gamma.txt";
    plainRow.fileSize = 50;
    plainRow.sha1 = "GHI789";
    plainRow.fileCount = 1;
    plainRow.hasSummaryFlags = true;

    BlobRow[] rows = [videoRow, archiveRow, plainRow];
    auto canonicalTree = projectRowsToDirectoryTree(rows);
    assert(canonicalTree.files[0].id == jsonFileNodeId(0, 0));
    auto reorderedRows = [plainRow, videoRow];
    auto reorderedTree = projectRowsToDirectoryTree(reorderedRows);
    assert(reorderedTree.files[0].id == jsonFileNodeId(2, 0));
    assert(reorderedTree.files[1].id == jsonFileNodeId(0, 0));

    JsonFilterOptions caseSensitive;
    caseSensitive.text = "ALPHA";
    caseSensitive.caseSensitive = true;
    assert(filterJsonRows(rows, canonicalTree, caseSensitive).rows.length == 0);
    caseSensitive.caseSensitive = false;
    auto textResult = filterJsonRows(rows, canonicalTree, caseSensitive);
    assert(textResult.rows.length == 1);
    assert(textResult.rows[0].primaryFileName == "Folder/Alpha.mkv");
    assert(textResult.visibleTreeFileIndexes.length == canonicalTree.files.length);
    assert(textResult.visibleTreeFileIndexes[canonicalTree.files[0].sourceIndex]);
    assert(!textResult.visibleTreeFileIndexes[canonicalTree.files[1].sourceIndex]);
    assert(textResult.visibleTreeDirectoryIndexes[
        canonicalTree.directories[1].sourceIndex]);
    assert(!textResult.visibleTreeDirectoryIndexes[
        canonicalTree.directories[2].sourceIndex]);
    assert(textResult.visibleDirectoryFileCounts[1] == 1);
    assert(textResult.visibleDirectoryAggregateSizes[1] == 100);
    assert(textResult.hasVisibleTreeMatches);

    JsonFilterOptions videoOnly;
    videoOnly.video = true;
    auto videoResult = filterJsonRows(rows, canonicalTree, videoOnly);
    assert(videoResult.rows.length == 1);
    assert(videoResult.visibleTreeFileIndexes[canonicalTree.files[0].sourceIndex]);

    videoOnly.mediaNegated = true;
    auto notVideoResult = filterJsonRows(rows, canonicalTree, videoOnly);
    assert(notVideoResult.rows.length == 2);
    assert(!notVideoResult.visibleTreeFileIndexes[canonicalTree.files[0].sourceIndex]);
    assert(notVideoResult.visibleTreeFileIndexes[canonicalTree.files[1].sourceIndex]);
    assert(notVideoResult.visibleTreeFileIndexes[canonicalTree.files[2].sourceIndex]);
    assert(notVideoResult.visibleDirectoryAggregateSizes[0] == 250);
    assert(notVideoResult.visibleDirectoryChildCounts[0] == 2);

    JsonFilterOptions videoAndArchive;
    videoAndArchive.video = true;
    videoAndArchive.archive = true;
    auto noMatches = filterJsonRows(rows, canonicalTree, videoAndArchive);
    assert(noMatches.rows.length == 0,
        "media requirements combine with presence requirements using AND");
    assert(!noMatches.hasVisibleTreeMatches);
    assert(!noMatches.visibleTreeFileIndexes[0]);

    JsonFilterOptions archiveOrFileType;
    archiveOrFileType.archive = true;
    archiveOrFileType.fileType = true;
    auto presenceResult = filterJsonRows(rows, canonicalTree, archiveOrFileType);
    assert(presenceResult.rows.length == 2,
        "presence toggles within their group combine using OR");
}

@("JSON directory projection keeps virtual archive members off the physical tree")
unittest
{
    import dosierarkivo.archive : appendArchiveVirtualPath;
    import dosierskanilo.model.filespec : FileSpec;
    import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob;

    auto archiveBlob = new NamedBinaryBlob();
    archiveBlob.fileSpecsUseArchiveVirtualGrammar = true;
    archiveBlob.fileSpecs = [new FileSpec("archives/bundle!!.zip", "")];
    BlobRow archiveRow;
    archiveRow.sourceBlob = archiveBlob;
    archiveRow.fileSize = 100;

    auto memberBlob = new NamedBinaryBlob();
    memberBlob.fileSpecsUseArchiveVirtualGrammar = true;
    memberBlob.fileSpecs = [new FileSpec(appendArchiveVirtualPath(
        "archives/bundle!!.zip", "docs/readme.txt", 0), "")];
    BlobRow memberRow;
    memberRow.sourceBlob = memberBlob;
    memberRow.fileSize = 17;

    auto tree = projectRowsToDirectoryTree([archiveRow, memberRow]);
    assert(tree.files.length == 1);
    assert(tree.files[0].relativePath == "archives/bundle!.zip");
    assert(tree.files[0].hasArchive);
}
