/** GTK filtered-model helpers for retaining directory TreeStore nodes.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.directorytreefilter;

import gobject.Value;
import gtk.TreeIter;
import gtk.TreeModelFilter;
import gtk.TreeStore;
import gtk.c.types : GType;
import std.algorithm : canFind;
import std.string : toLower;

import dosierarkivo.archive : archivePathMatchesText;
import model.treeprojection : FileFilter;

/// TreeStore column holding the stable node identifier used for filtering.
enum int treeNodeIdColumn = 16;
/// TreeStore boolean column read by the filtered model to decide row visibility.
enum int treeVisibleColumn = 17;

/** Wrap a canonical directory store without copying or replacing its rows.
 *
 * Params:
 *     store = Canonical directory TreeStore to wrap.
 * Returns: A filtered model that reads the visibility column from `store`.
 */
TreeModelFilter createDirectoryTreeFilter(TreeStore store)
{
    auto filtered = new TreeModelFilter(store, null);
    filtered.setVisibleColumn(treeVisibleColumn);
    return filtered;
}

/** Set one canonical row's visibility flag for the filtered view.
 *
 * Params:
 *     store = Canonical directory store containing the row.
 *     iter = Row whose visibility flag is updated.
 *     visible = Whether the row should be visible in the filtered view.
 */
void setDirectoryTreeNodeVisible(TreeStore store, TreeIter iter, bool visible)
{
    auto value = new Value();
    value.init(GType.BOOLEAN);
    value.setBoolean(visible);
    store.setValue(iter, treeVisibleColumn, value);
}

/** Decide visibility from precomputed IDs; this is safe for a GTK filter callback.
 *
 * Params:
 *     kind = Row kind such as `Directory`, `File`, or a placeholder kind.
 *     nodeId = Stable identifier of the row.
 *     parentId = Stable identifier of the row's parent.
 *     filtering = Whether a filter is active; when false every row is visible.
 *     visibleIds = Identifiers of rows retained by the active filter.
 * Returns: `true` when the row should remain visible.
 */
bool directoryTreeNodeVisible(string kind, string nodeId, string parentId,
    bool filtering, const(bool[string]) visibleIds)
{
    if (!filtering)
        return true;

    switch (kind)
    {
    case "Directory":
        return nodeId == "root" || (nodeId in visibleIds) !is null;
    case "File":
        return (nodeId in visibleIds) !is null;
    case "Placeholder", "Page", "Loading", "LoadingPage", "Error", "Filtering":
        return (parentId in visibleIds) !is null
            && (parentId != "root" || visibleIds.length > 1);
    default:
        return true;
    }
}

/** Visibility for JSON rows indexed by their canonical projection position.
 *
 * Params:
 *     kind = Row kind such as `Directory`, `File`, or a placeholder kind.
 *     sourceIndex = Canonical projection index of the row.
 *     filtering = Whether a filter is active; when false every row is visible.
 *     visibleFileIndexes = Visibility flags indexed by file projection index.
 *     visibleDirectoryIndexes = Visibility flags indexed by directory
 *         projection index.
 *     hasMatches = Whether any filter match exists at all.
 * Returns: `true` when the row should remain visible.
 */
bool directoryTreeNodeVisibleByIndex(string kind, size_t sourceIndex,
    bool filtering, const(bool)[] visibleFileIndexes,
    const(bool)[] visibleDirectoryIndexes, bool hasMatches)
{
    if (!filtering)
        return true;
    switch (kind)
    {
    case "Directory":
        return sourceIndex == 0 || (sourceIndex < visibleDirectoryIndexes.length
            && visibleDirectoryIndexes[sourceIndex]);
    case "File":
        return sourceIndex < visibleFileIndexes.length
            && visibleFileIndexes[sourceIndex];
    case "Placeholder", "Page", "Loading", "LoadingPage", "Error", "Filtering":
        return sourceIndex < visibleDirectoryIndexes.length
            && visibleDirectoryIndexes[sourceIndex]
            && (sourceIndex != 0 || hasMatches);
    default:
        return true;
    }
}

/** Match a materialized file row using the shared directory-filter semantics.
 *
 * Params:
 *     name = Display filename matched against the text filter.
 *     path = Archive-style path also matched against the text filter.
 *     video = Whether the file has a video stream.
 *     audio = Whether the file has an audio stream.
 *     image = Whether the file has an image stream.
 *     textStream = Whether the file has a text stream.
 *     fileType = Whether a file type is known.
 *     archive = Whether the file is an archive.
 *     torrent = Whether the file is a torrent.
 *     filter = Active filter criteria.
 * Returns: `true` when the row satisfies every active criterion.
 */
bool treeFileMatchesFilter(string name, string path, bool video, bool audio,
    bool image, bool textStream, bool fileType, bool archive, bool torrent,
    FileFilter filter)
{
    if (filter.text.length > 0)
    {
        const query = filter.caseSensitive ? filter.text : filter.text.toLower;
        const filteredName = filter.caseSensitive ? name : name.toLower;
        if (!filteredName.canFind(query)
            && !archivePathMatchesText(path, filter.text,
                filter.caseSensitive))
            return false;
    }
    auto hasMediaFilter = filter.video || filter.audio || filter.image || filter.textStream;
    auto matchesMedia = (filter.video && video) || (filter.audio && audio)
        || (filter.image && image) || (filter.textStream && textStream);
    if (hasMediaFilter && (filter.mediaNegated ? matchesMedia : !matchesMedia))
        return false;
    auto hasPresenceFilter = filter.fileType || filter.archive || filter.torrent;
    auto matchesPresence = (filter.fileType && fileType) || (filter.archive && archive)
        || (filter.torrent && torrent);
    return !hasPresenceFilter || matchesPresence;
}

@("directory filtered model toggles visibility while retaining canonical rows")
unittest
{
    import gtk.TreeModelIF;

    auto columnTypes = new GType[treeVisibleColumn + 1];
    columnTypes[] = GType.STRING;
    columnTypes[treeVisibleColumn] = GType.BOOLEAN;
    auto store = new TreeStore(columnTypes);
    auto filter = createDirectoryTreeFilter(store);
    TreeIter root;
    store.append(root, null);
    store.setValue(root, 0, "root");
    store.setValue(root, 1, "Directory");
    store.setValue(root, treeNodeIdColumn, "root");
    TreeIter directory;
    store.append(directory, root);
    store.setValue(directory, 0, "music");
    store.setValue(directory, 1, "Directory");
    store.setValue(directory, treeNodeIdColumn, "directory:music");
    TreeIter first;
    store.append(first, directory);
    store.setValue(first, 0, "one.mkv");
    store.setValue(first, 1, "File");
    store.setValue(first, treeNodeIdColumn, "file:json:1:0");
    TreeIter second;
    store.append(second, directory);
    store.setValue(second, 0, "two.mkv");
    store.setValue(second, 1, "File");
    store.setValue(second, treeNodeIdColumn, "file:json:2:0");
    setDirectoryTreeNodeVisible(store, first, true);
    setDirectoryTreeNodeVisible(store, second, false);
    setDirectoryTreeNodeVisible(store, directory, true);
    setDirectoryTreeNodeVisible(store, root, true);
    filter.refilter();

    assert(filter.iterNChildren(null) == 1);
    assert(store.iterNChildren(null) == 1);
    TreeIter filteredRoot;
    assert(filter.iterChildren(filteredRoot, null));
    TreeIter filteredDirectory;
    assert(filter.iterChildren(filteredDirectory, filteredRoot));
    assert(filter.iterNChildren(filteredDirectory) == 1);
    assert(store.iterNChildren(directory) == 2);

    setDirectoryTreeNodeVisible(store, second, true);
    filter.refilter();
    assert(filter.iterNChildren(null) == 1);
    assert(filter.iterChildren(filteredRoot, null));
    assert(filter.iterChildren(filteredDirectory, filteredRoot));
    assert(filter.iterNChildren(filteredDirectory) == 2);
    assert(store.iterNChildren(directory) == 2);
}

@("filtered directory rows retain matching ancestors and suppress empty placeholders")
unittest
{
    bool[string] visibleIds;
    visibleIds["root"] = true;
    visibleIds["directory:music"] = true;
    visibleIds["file:json:4:0"] = true;

    assert(directoryTreeNodeVisible("Directory", "root", "", true, visibleIds));
    assert(directoryTreeNodeVisible("Directory", "directory:music", "root", true,
        visibleIds));
    assert(directoryTreeNodeVisible("File", "file:json:4:0", "directory:music",
        true, visibleIds));
    assert(!directoryTreeNodeVisible("File", "file:json:8:0", "directory:music",
        true, visibleIds));
    assert(directoryTreeNodeVisible("Placeholder", "Placeholder:root", "root",
        true, visibleIds));
    assert(directoryTreeNodeVisible("File", "file:json:8:0", "directory:music",
        false, visibleIds));
    bool[] visibleFiles = [true, false];
    bool[] visibleDirectories = [true, true, false];
    assert(directoryTreeNodeVisibleByIndex("Directory", 0, true, visibleFiles,
        visibleDirectories, true));
    assert(directoryTreeNodeVisibleByIndex("Directory", 1, true, visibleFiles,
        visibleDirectories, true));
    assert(!directoryTreeNodeVisibleByIndex("Directory", 2, true, visibleFiles,
        visibleDirectories, true));
    assert(directoryTreeNodeVisibleByIndex("File", 0, true, visibleFiles,
        visibleDirectories, true));
    assert(!directoryTreeNodeVisibleByIndex("File", 1, true, visibleFiles,
        visibleDirectories, true));
    assert(!directoryTreeNodeVisibleByIndex("Placeholder", 0, true, visibleFiles,
        visibleDirectories, false));

    FileFilter filter;
    filter.text = "MUSIC/SONG";
    filter.caseSensitive = false;
    filter.video = true;
    assert(treeFileMatchesFilter("Song.mkv", "Music/Song.mkv", true, false,
        false, false, false, false, false, filter));
    assert(!treeFileMatchesFilter("Song.mkv", "Music/Song.mkv", false, false,
        false, false, false, false, false, filter));
    filter.mediaNegated = true;
    assert(!treeFileMatchesFilter("Song.mkv", "Music/Song.mkv", true, false,
        false, false, false, false, false, filter));

    FileFilter escapedFilter;
    escapedFilter.text = "d!e";
    escapedFilter.caseSensitive = false;
    assert(treeFileMatchesFilter("f.txt", "d!!e/f.txt", false, false, false,
        false, false, false, false, escapedFilter));
}
