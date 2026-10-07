/** Main GTK application shell for DosierSkanilo GUI.
 *
 * This module wires together command-line startup options, JSON loading,
 * row-table rendering, and classic desktop menu actions.
 *
 * Authors: DosierSkanilo contributors
 * License: GPL-3.0-only
 */
module ui.mainwindow;

import gdk.c.types : GdkEventConfigure;
import gdk.Display;
import glib.Idle;
import glib.Timeout;
import gobject.Value;
import gobject.Type : GType;
import gobject.ObjectG : ObjectG;
import gobject.ParamSpec : ParamSpec;
import gtk.Builder;
import gtk.AccelGroup;
import gtk.Box;
import gtk.Button;
import gtk.AspectFrame;
import gtk.c.types : Orientation;
import gtk.c.types : GtkAccelFlags;
import gtk.CheckButton;
import gtk.Clipboard;
import gtk.ComboBoxText;
import gtk.DrawingArea;
import gtk.Entry;
import gtk.Expander;
import gtk.Image;
import gtk.FileChooserDialog;
import gtk.Grid;
import gtk.Label;
import gtk.ListStore;
import gtk.Main;
import gtk.Menu;
import gtk.MenuBar;
import gtk.MenuItem;
import gtk.Notebook;
import gtk.Paned;
import gtk.ProgressBar;
import gtk.Range;
import gtk.Scale;
import gtk.ScrolledWindow;
import gtk.Separator;
import gtk.Spinner;
import gtk.TextView;
import gtk.ToggleButton;
import gtk.TreeIter;
import gtk.TreeModelIF;
import gtk.TreeModelFilter;
import gtk.TreeSelection;
import gtk.TreeSortableIF;
import gtk.TreeStore;
import gtk.TreePath;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.CellRendererText;
import gtk.Widget;
import gtk.Window;
import gtk.c.types : GtkAlign, GtkIconSize, GtkReliefStyle, GtkShadowType,
    GtkSortType, GtkTreeViewColumnSizing;
import gtk.c.types : FileChooserAction, ResponseType;
import gdk.c.types : GdkModifierType;
import gdk.Event;

import core.thread : Thread;
import core.time : MonoTime;
import std.algorithm : canFind, sort;
import std.array : appender;
import std.base64 : Base64;
import std.conv : to;
import std.file : exists, isDir;
import std.format : format;
import std.path : absolutePath, baseName, buildNormalizedPath, dirName;
import std.process : Config, ProcessException, spawnProcess;
import std.stdio : writeln;
import std.string : join, replace, split;
import gstreamer.GStreamer : GStreamer;
import gstreamer.c.types : GstState, GstStateChangeReturn;

import cli.commandline : CliOptions, cliUsageText, parseCliOptions;
import model.blobrow : BlobRow, extractRowsFromBlobs;
import model.datasource : SourceQuery, isRepositorySource, loadDocumentDetails,
    loadDocumentCursorPage, loadDocumentPage, loadDocumentSource, loadRepositoryArchiveEntries,
    loadRepositoryTorrentFiles, openRepositoryDirectorySource;
import model.treeprojection : DirectoryNode, DirectorySource, DirectoryTree, FileCursor,
    FileFilter, FileNode, FilePage, FileSortOrder, NestedFileNode,
    ProjectedDirectorySource, jsonFileNodeId;
import ui.appstate : AppState, DocumentFilterState, TableSortState, TreeCursorState, loadAppState,
    saveAppState;
import ui.builderutils : builderObject;
import ui.detailpane : DetailPaneCallbacks, bindDetailPaneSignals, loadDetailPaneUi;
import ui.detailpreview : DetailPreviewCallbacks, bindDetailPreviewSignals, loadDetailPreviewUi;
import ui.documenttab : COL_CHECKSUM_SET, COL_FILE_SIZE, COL_FILE_SIZE_SORT, COL_FILE_TYPE, COL_HAS_ARCHIVE, COL_HAS_TORRENT, COL_HAS_FILE_TYPE_FLAG, COL_HAS_MEDIA_FLAG, COL_HAS_VIDEO_FLAG, COL_HAS_AUDIO_FLAG, COL_HAS_IMAGE_FLAG, COL_HAS_TEXT_FLAG, COL_HAS_ARCHIVE_FLAG, COL_HAS_TORRENT_FLAG, COL_INDEX, COL_INDEX_SORT, COL_MEDIA_INFO, COL_SOURCE_ID, DocumentTab, PreviewScaleMode, TreeSortOrder, clampPreviewScaleMode;
import ui.contextpaths : resolveDocumentSourcePath;
import ui.dataexport : loadFilteredExportRows, writeRowsCsv, writeRowsJson;
import ui.nestedentrylogic : prepareNestedEntryPage;
import ui.nestedentrysignals : NestedPageActivation, bindNestedPageActivation,
    nestedEntryReplyMatches;
import ui.directoryactions : toggleDirectoryExpansion, toggleDirectorySubtree;
import ui.directoryloading : loadExpandedDirectoryPlaceholders;
import ui.documentpage : loadDocumentPageUi;
import ui.detailswidgets : setDetailEntry,
    setMetadataStatusLabel, setMetadataDetails, archiveMetadataSummary,
    torrentMetadataSummary, setFileTypeDetails, setKnownFilesTable,
    setMediaPreview, setMediaInfoStreamDetails, setFallbackDetails,
    refreshMediaPreview, syncVideoPreviewWindow, setVideoPreviewVolume, playVideoPreview,
    pauseVideoPreview, jumpVideoPreview, stopVideoPreview, syncVideoPreviewPosition,
    seekVideoPreview, syncVideoPlaybackButton, syncVideoTrackSelectors;
import ui.documentactions : DocumentActionCallbacks, closeCurrentDocument, reloadCurrentDocument;
import ui.documentfilterstate : documentFilterHasCriteria,
    shouldApplyDocumentFilter;
import ui.directorytreefilter : createDirectoryTreeFilter,
    directoryTreeNodeVisible, directoryTreeNodeVisibleByIndex,
    setDirectoryTreeNodeVisible, treeFileMatchesFilter, treeNodeIdColumn,
    treeVisibleColumn;
import ui.fileopendialog : FileOpenDialogCallbacks, chooseAndLoadPath,
    chooseAndLoadRepository;
import ui.helpdialogs : showAbout, showShortcutsHelp;
import ui.loadingstatus;
import ui.jsonfilter : JsonFilterOptions, filterJsonRows, projectRowsToDirectoryTree;
import ui.preferencesdialog : PreferencesDialogCallbacks, showPreferencesDialog;
import ui.selectionstatus : boolStatusIcon, checksumStatusSummary, clearSelectionDetails,
    mediaInfoStatusSummary, metadataPresenceSummary, resetFilterState, resetPerfMetrics, updateFileMetaStatus, updatePerfStatus;
import ui.styles : installApplicationCss;
import ui.toolbarbindings : ToolbarBindingsCallbacks, bindFilterSignals,
    bindToolbarButtons, captureDocumentFilterState;
import ui.windowlifecycle : WindowLifecycleCallbacks, bindWindowLifecycleSignals;
import ui.startupworkflow : scheduleSelfTestQuit, startStartupWorkflow;
import ui.treeselectionlogic : TreeSelectionFollowup, tableIndexMatchesVisibleRow,
    jsonFilterNeedsRebuild, treeSelectionFollowup;
import ui.previewprogress : PreviewProgressCallbacks, startPreviewProgressTimer;
import ui.virtualblobtable : VirtualBlobTableModel;
import ui.tablecolumns : MAIN_TABLE_FIXED_COLUMN_WIDTH, setTableColumnsResizable, configureTableColumns, configureKnownFilesColumns;
import view.textreport : filterRowsByText;
import dosierskanilo.model.namedbinaryblob : DATA_CLASS_VERSION2, NamedBinaryBlob;
import dosierskanilo.repository.types : RepositoryBlobFlags;
import dosierskanilo.repository.repository : Repository;
import cli.logging;

enum int TREE_COL_NODE_ID = treeNodeIdColumn;
enum int TREE_COL_VISIBLE = treeVisibleColumn;
enum int TREE_COL_SORT_SIZE = 18;
enum int TREE_COL_BASE_SUMMARY = 19;
enum int TREE_COL_BASE_SORT_SIZE = 20;
enum int TREE_COL_PROJECTION_INDEX = 21;

private void setTreeNodeVisible(TreeStore store, TreeIter iter, bool visible,
    Value reusableValue = null)
{
    if (reusableValue is null)
        setDirectoryTreeNodeVisible(store, iter, visible);
    else
    {
        reusableValue.setBoolean(visible);
        store.setValue(iter, TREE_COL_VISIBLE, reusableValue);
    }
}

private bool findTreeChildById(TreeStore store, TreeIter parent, string nodeId,
    out TreeIter result)
{
    TreeIter child;
    if (!store.iterChildren(child, parent))
        return false;
    do
    {
        if (store.getValueString(child, TREE_COL_NODE_ID) == nodeId)
        {
            result = child;
            return true;
        }
    }
    while (store.iterNext(child));
    return false;
}

private void removeTreeChildById(TreeStore store, TreeIter parent, string nodeId)
{
    TreeIter child;
    if (!store.iterChildren(child, parent))
        return;
    do
    {
        if (store.getValueString(child, TREE_COL_NODE_ID) == nodeId)
        {
            if (!store.remove(child))
                return;
        }
        else if (!store.iterNext(child))
            return;
    }
    while (true);
}

private void reorderTreeChildren(TreeStore store, TreeIter parent, TreeSortOrder order)
{
    struct SortRow
    {
        int oldIndex;
        int rank;
        string name;
        string size;
        string id;
    }
    auto childCount = store.iterNChildren(parent);
    if (childCount <= 1)
        return;
    auto rows = new SortRow[childCount];
    TreeIter child;
    if (!store.iterChildren(child, parent))
        return;
    int rowPosition;
    do
    {
        auto kind = store.getValueString(child, 1);
        auto rank = kind == "Directory" ? 0 : kind == "File" ? 1 : 2;
        rows[rowPosition] = SortRow(rowPosition, rank, store.getValueString(child, 0),
            store.getValueString(child, TREE_COL_SORT_SIZE),
            store.getValueString(child, TREE_COL_NODE_ID));
        ++rowPosition;
    }
    while (store.iterNext(child));
    sort!((a, b) {
        if (a.rank != b.rank)
            return a.rank < b.rank;
        if (a.rank == 2)
            return a.id < b.id;
        if (order == TreeSortOrder.sizeAscending
            || order == TreeSortOrder.sizeDescending)
        {
            if (a.size != b.size)
                return order == TreeSortOrder.sizeAscending
                    ? a.size < b.size : a.size > b.size;
        }
        if (a.name != b.name)
            return order == TreeSortOrder.nameDescending
                ? a.name > b.name : a.name < b.name;
        return a.id < b.id;
    })(rows);
    auto newOrder = new int[rows.length];
    foreach (orderIndex, row; rows)
        newOrder[orderIndex] = row.oldIndex;
    store.reorder(parent, newOrder);
}

private TreeIter treeStoreIter(DocumentTab document, TreeIter viewIter)
{
    if (document.directoryTreeFilterModel is null)
        return viewIter;
    TreeIter storeIter;
    document.directoryTreeFilterModel.convertIterToChildIter(storeIter, viewIter);
    return storeIter;
}

private TreeIter treeViewIter(DocumentTab document, TreeIter storeIter)
{
    if (document.directoryTreeFilterModel is null)
        return storeIter;
    TreeIter viewIter;
    if (!document.directoryTreeFilterModel.convertChildIterToIter(viewIter, storeIter))
        return null;
    return viewIter;
}

/** Configure the transitional directory tree columns. */
void configureDirectoryTreeColumns(TreeView treeView)
{
    void addColumn(string title, int modelColumn, bool expand)
    {
        auto renderer = new CellRendererText();
        auto column = new TreeViewColumn();
        column.setTitle(title);
        column.packStart(renderer, true);
        column.addAttribute(renderer, "text", modelColumn);
        column.setResizable(true);
        column.setExpand(expand);
        treeView.appendColumn(column);
    }

    addColumn("Name", 0, true);
    addColumn("Kind", 1, false);
    addColumn("Size", 2, false);
    treeView.setHeadersClickable(false);
}

private void setBlobTableVirtualMode(TreeView treeView, bool virtualMode)
{
    treeView.setFixedHeightMode(false);
    auto widths = [55, 95, 90, 45, 90, MAIN_TABLE_FIXED_COLUMN_WIDTH,
        MAIN_TABLE_FIXED_COLUMN_WIDTH];
    foreach (index; 0 .. cast(int) treeView.getNColumns())
    {
        auto column = treeView.getColumn(index);
        if (column is null)
            continue;
        if (virtualMode)
        {
            column.setSizing(GtkTreeViewColumnSizing.FIXED);
            if (index < widths.length)
                column.setFixedWidth(widths[index]);
        }
        else if (index == 5 || index == 6)
        {
            column.setSizing(GtkTreeViewColumnSizing.FIXED);
            column.setFixedWidth(MAIN_TABLE_FIXED_COLUMN_WIDTH);
        }
        else
        {
            column.setSizing(GtkTreeViewColumnSizing.AUTOSIZE);
        }
    }
    if (virtualMode)
        treeView.setFixedHeightMode(true);
}

private DirectoryNode[] sortedDirectories(DirectorySource source, string parentId,
    TreeSortOrder order, FileFilter filter = FileFilter())
{
    auto result = source.listDirectories(parentId, filter);
    sort!((a, b) {
        if (order == TreeSortOrder.nameDescending)
            return a.name > b.name;
        return a.name < b.name;
    })(result);
    return result;
}

private FileFilter treeFilterForDocument(DocumentTab document, bool caseSensitive)
{
    FileFilter filter;
    filter.text = document.filterQuery;
    filter.caseSensitive = caseSensitive;
    filter.video = document.filterVideo;
    filter.audio = document.filterAudio;
    filter.image = document.filterImage;
    filter.textStream = document.filterText;
    filter.mediaNegated = document.filterMediaNegated;
    filter.fileType = document.filterFileType;
    filter.archive = document.filterArchive;
    filter.torrent = document.filterTorrent;
    return filter;
}

private bool sameTreeFilter(FileFilter left, FileFilter right)
{
    return left.text == right.text && left.caseSensitive == right.caseSensitive
        && left.video == right.video && left.audio == right.audio
        && left.image == right.image && left.textStream == right.textStream
        && left.mediaNegated == right.mediaNegated && left.fileType == right.fileType
        && left.archive == right.archive && left.torrent == right.torrent;
}

private bool validBlobTableSortColumn(int columnId)
{
    return columnId == COL_INDEX_SORT || columnId == COL_FILE_SIZE_SORT
        || columnId == COL_CHECKSUM_SET || columnId == COL_FILE_TYPE
        || columnId == COL_MEDIA_INFO || columnId == COL_HAS_ARCHIVE
        || columnId == COL_HAS_TORRENT;
}

private FileSortOrder sourceFileSortOrder(TreeSortOrder order)
{
    final switch (order)
    {
    case TreeSortOrder.nameAscending: return FileSortOrder.pathAscending;
    case TreeSortOrder.nameDescending: return FileSortOrder.pathDescending;
    case TreeSortOrder.sizeAscending: return FileSortOrder.sizeAscending;
    case TreeSortOrder.sizeDescending: return FileSortOrder.sizeDescending;
    }
}

private SourceQuery sourceQueryForDocument(DocumentTab document, bool caseSensitive)
{
    SourceQuery query;
    query.text = document.filterQuery;
    query.caseSensitive = caseSensitive;
    query.video = document.filterVideo;
    query.audio = document.filterAudio;
    query.image = document.filterImage;
    query.textStream = document.filterText;
    query.mediaNegated = document.filterMediaNegated;
    query.fileType = document.filterFileType;
    query.archive = document.filterArchive;
    query.torrent = document.filterTorrent;
    return query;
}

private void appendDirectoryTreeNode(TreeStore store, DirectorySource source,
    const DirectoryNode node, TreeIter parent, FileFilter filter = FileFilter(),
    TreeSortOrder order = TreeSortOrder.nameAscending, Value visibilityValue = null)
{
    TreeIter iter;
    if (!findTreeChildById(store, parent, node.id, iter))
        iter = store.createIter(parent);
    store.setValue(iter, 0, node.name.length > 0 ? node.name : "(source root)");
    store.setValue(iter, 1, "Directory");
    store.setValue(iter, 2, format("%s files | %s bytes", node.fileCount, node.aggregateSize));
    store.setValue(iter, TREE_COL_BASE_SUMMARY,
        format("%s files | %s bytes", node.fileCount, node.aggregateSize));
    store.setValue(iter, 3, node.id);
    store.setValue(iter, 5, node.relativePath);
    store.setValue(iter, TREE_COL_NODE_ID, node.id);
    store.setValue(iter, TREE_COL_PROJECTION_INDEX, node.sourceIndex.to!string);
    store.setValue(iter, TREE_COL_SORT_SIZE, format("%020d", node.aggregateSize));
    store.setValue(iter, TREE_COL_BASE_SORT_SIZE,
        format("%020d", node.aggregateSize));
    setTreeNodeVisible(store, iter, true, visibilityValue);
    auto hasActiveFilter = filter.text.length > 0 || filter.video || filter.audio
        || filter.image || filter.textStream || filter.fileType || filter.archive
        || filter.torrent;
    auto hasChildren = hasActiveFilter
        ? source.listDirectories(node.id, filter).length > 0
            || source.hasMatchingFileInDirectory(node.id, filter)
        : node.childDirectoryCount > 0 || node.fileCount > 0;
    if (hasChildren && store.iterNChildren(iter) == 0)
    {
        auto loadingIter = store.createIter(iter);
        store.setValue(loadingIter, 0, "Loading...");
        store.setValue(loadingIter, 1, "Placeholder");
        store.setValue(loadingIter, 2, "");
        store.setValue(loadingIter, 3, node.id);
        store.setValue(loadingIter, TREE_COL_NODE_ID, "Placeholder:" ~ node.id);
        store.setValue(loadingIter, TREE_COL_PROJECTION_INDEX,
            node.sourceIndex.to!string);
        store.setValue(loadingIter, TREE_COL_SORT_SIZE, "");
        setTreeNodeVisible(store, loadingIter, true, visibilityValue);
    }
}

private void populateDirectoryTreeNode(TreeStore store, DirectorySource source,
    TreeIter parent, string directoryId, FileCursor cursor = FileCursor(), bool includeDirectories = true,
    FileFilter filter = FileFilter(), TreeSortOrder order = TreeSortOrder.nameAscending)
{
    auto visibilityValue = new Value();
    visibilityValue.init(GType.BOOLEAN);
    if (includeDirectories)
    {
        foreach (child; sortedDirectories(source, directoryId, order, filter))
            appendDirectoryTreeNode(store, source, child, parent, filter, order,
                visibilityValue);
    }
    auto page = source.listFilteredFilesPage(directoryId, cursor, 251, filter,
        sourceFileSortOrder(order));
    populateDirectoryTreeRows(store, parent, [], page.files, false, order,
        page.hasMore, page.nextCursor, visibilityValue);
}

private void populateDirectoryTreeRows(TreeStore store, TreeIter parent,
    const(DirectoryNode)[] directories, const(FileNode)[] files,
    bool includeDirectories = true, TreeSortOrder order = TreeSortOrder.nameAscending,
    bool hasMore = false, FileCursor nextCursor = FileCursor(),
    Value visibilityValue = null)
{
    if (visibilityValue is null)
    {
        visibilityValue = new Value();
        visibilityValue.init(GType.BOOLEAN);
    }
    auto directoryId = store.getValueString(parent, 3);
    removeTreeChildById(store, parent, "Placeholder:" ~ directoryId);
    auto sortedDirectoryRows = directories.dup;
    auto sortedFileRows = files.dup;
    sort!((a, b) {
        if (order == TreeSortOrder.nameDescending)
            return a.name > b.name;
        if (order == TreeSortOrder.sizeAscending)
            return a.aggregateSize < b.aggregateSize;
        if (order == TreeSortOrder.sizeDescending)
            return a.aggregateSize > b.aggregateSize;
        return a.name < b.name;
    })(sortedDirectoryRows);
    sort!((a, b) {
        if (order == TreeSortOrder.sizeAscending)
            return a.size < b.size;
        if (order == TreeSortOrder.sizeDescending)
            return a.size > b.size;
        if (order == TreeSortOrder.nameDescending)
            return a.name > b.name;
        return a.name < b.name;
    })(sortedFileRows);
    if (includeDirectories)
    foreach (directory; sortedDirectoryRows)
    {
        TreeIter directoryIter;
        if (!findTreeChildById(store, parent, directory.id, directoryIter))
            directoryIter = store.createIter(parent);
        store.setValue(directoryIter, 0, directory.name);
        store.setValue(directoryIter, 1, "Directory");
        store.setValue(directoryIter, 2, format("%s files | %s bytes",
            directory.fileCount, directory.aggregateSize));
        store.setValue(directoryIter, TREE_COL_BASE_SUMMARY,
            format("%s files | %s bytes", directory.fileCount,
                directory.aggregateSize));
        store.setValue(directoryIter, 3, directory.id);
        store.setValue(directoryIter, 5, directory.relativePath);
        store.setValue(directoryIter, TREE_COL_NODE_ID, directory.id);
        store.setValue(directoryIter, TREE_COL_PROJECTION_INDEX,
            directory.sourceIndex.to!string);
        store.setValue(directoryIter, TREE_COL_SORT_SIZE,
            format("%020d", directory.aggregateSize));
        store.setValue(directoryIter, TREE_COL_BASE_SORT_SIZE,
            format("%020d", directory.aggregateSize));
        setTreeNodeVisible(store, directoryIter, true, visibilityValue);
        if ((directory.childDirectoryCount > 0 || directory.fileCount > 0)
            && store.iterNChildren(directoryIter) == 0)
        {
            auto loadingIter = store.createIter(directoryIter);
            store.setValue(loadingIter, 0, "Loading...");
            store.setValue(loadingIter, 1, "Placeholder");
            store.setValue(loadingIter, 2, "");
            store.setValue(loadingIter, 3, directory.id);
            store.setValue(loadingIter, TREE_COL_NODE_ID,
                "Placeholder:" ~ directory.id);
            store.setValue(loadingIter, TREE_COL_PROJECTION_INDEX,
                directory.sourceIndex.to!string);
            store.setValue(loadingIter, TREE_COL_SORT_SIZE, "");
            setTreeNodeVisible(store, loadingIter, true, visibilityValue);
        }
    }
    auto fileLimit = sortedFileRows.length > 250 ? 250 : sortedFileRows.length;
    foreach (file; sortedFileRows[0 .. fileLimit])
    {
        auto nodeId = file.cursorId.length > 0 ? file.cursorId : file.id;
        TreeIter fileIter;
        if (!findTreeChildById(store, parent, nodeId, fileIter))
            fileIter = store.createIter(parent);
        store.setValue(fileIter, 0, file.name);
        store.setValue(fileIter, 1, "File");
        store.setValue(fileIter, 2, format("%s bytes", file.size));
        store.setValue(fileIter, 3, file.id);
        store.setValue(fileIter, 5, file.relativePath);
        store.setValue(fileIter, 6, file.cursorId);
        store.setValue(fileIter, 7, file.size.to!string);
        store.setValue(fileIter, 8, file.hasFileType ? "1" : "0");
        store.setValue(fileIter, 9, file.hasMedia ? "1" : "0");
        store.setValue(fileIter, 10, file.hasVideo ? "1" : "0");
        store.setValue(fileIter, 11, file.hasAudio ? "1" : "0");
        store.setValue(fileIter, 12, file.hasImage ? "1" : "0");
        store.setValue(fileIter, 13, file.hasText ? "1" : "0");
        store.setValue(fileIter, 14, file.hasArchive ? "1" : "0");
        store.setValue(fileIter, 15, file.hasTorrent ? "1" : "0");
        store.setValue(fileIter, TREE_COL_NODE_ID, nodeId);
        store.setValue(fileIter, TREE_COL_PROJECTION_INDEX,
            file.sourceIndex.to!string);
        store.setValue(fileIter, TREE_COL_SORT_SIZE, format("%020d", file.size));
        setTreeNodeVisible(store, fileIter, true, visibilityValue);
    }
    if (sortedFileRows.length > fileLimit)
    {
        hasMore = true;
        auto lastVisible = sortedFileRows[fileLimit - 1];
        nextCursor = FileCursor(lastVisible.relativePath, lastVisible.cursorId,
            lastVisible.size);
    }
    auto pageNodeId = "Page:" ~ directoryId;
    if (hasMore)
    {
        TreeIter moreIter;
        if (!findTreeChildById(store, parent, pageNodeId, moreIter))
            moreIter = store.createIter(parent);
        store.setValue(moreIter, 0, "More files available...");
        store.setValue(moreIter, 1, "Page");
        store.setValue(moreIter, 2, "");
        store.setValue(moreIter, 3, directoryId);
        store.setValue(moreIter, 4, nextCursor.relativePath);
        store.setValue(moreIter, 5, nextCursor.id);
        store.setValue(moreIter, 6, nextCursor.size.to!string);
        store.setValue(moreIter, TREE_COL_NODE_ID, pageNodeId);
        store.setValue(moreIter, TREE_COL_PROJECTION_INDEX,
            store.getValueString(parent, TREE_COL_PROJECTION_INDEX));
        store.setValue(moreIter, TREE_COL_SORT_SIZE, "");
        setTreeNodeVisible(store, moreIter, true, visibilityValue);
    }
    else
        removeTreeChildById(store, parent, pageNodeId);

    reorderTreeChildren(store, parent, order);
}

private bool findNestedDirectoryChild(TreeModelIF model, TreeIter parent, string relativePath,
    out TreeIter match)
{
    TreeIter child;
    if (!model.iterChildren(child, parent))
        return false;
    do
    {
        if (model.getValueString(child, 3) == "Directory"
            && model.getValueString(child, 2) == relativePath)
        {
            match = child;
            return true;
        }
    }
    while (model.iterNext(child));
    return false;
}

private void appendNestedEntry(TreeStore store, TreeModelIF model, TreeIter rootParent,
    NestedFileNode entry, string blobId)
{
    auto normalizedPath = entry.relativePath.replace('\\', '/');
    auto parts = normalizedPath.split("/");
    if (parts.length == 0)
        return;
    TreeIter parent = rootParent;
    string directoryPath;
    foreach (part; parts[0 .. $ - 1])
    {
        if (part.length == 0)
            continue;
        directoryPath = directoryPath.length == 0 ? part : directoryPath ~ "/" ~ part;
        TreeIter directory;
        if (!findNestedDirectoryChild(model, parent, directoryPath, directory))
        {
            directory = store.createIter(parent);
            store.setValue(directory, 0, part);
            store.setValue(directory, 1, "");
            store.setValue(directory, 2, directoryPath);
            store.setValue(directory, 3, "Directory");
            store.setValue(directory, 4, blobId);
        }
        parent = directory;
    }
    auto fileName = parts[$ - 1];
    if (fileName.length == 0)
        return;
    auto file = store.createIter(parent);
    store.setValue(file, 0, fileName);
    store.setValue(file, 1, format("%s bytes", entry.size));
    store.setValue(file, 2, normalizedPath);
    store.setValue(file, 3, "File");
    store.setValue(file, 4, blobId);
}

private void appendNestedPageMarker(TreeStore store, TreeIter parent, string blobId,
    bool archive, size_t offset, string requestToken)
{
    auto marker = store.createIter(parent);
    store.setValue(marker, 0, "More entries available...");
    store.setValue(marker, 1, "");
    store.setValue(marker, 2, "");
    store.setValue(marker, 3, archive ? "ArchivePage" : "TorrentPage");
    store.setValue(marker, 4, blobId);
    store.setValue(marker, 5, offset.to!string);
    store.setValue(marker, 6, requestToken);
}

private bool findDirectoryTreeIter(TreeModelIF model, TreeIter parent, bool hasParent,
    string id, ref TreeIter result)
{
    TreeIter iter;
    if (hasParent)
    {
        if (!model.iterChildren(iter, parent))
            return false;
    }
    else if (!model.getIterFirst(iter))
    {
        return false;
    }

    do
    {
        if (model.getValueString(iter, 1) == "Directory"
            && model.getValueString(iter, 3) == id)
        {
            result = iter;
            return true;
        }
        if (model.iterHasChild(iter) && findDirectoryTreeIter(model, iter, true, id, result))
            return true;
    }
    while (model.iterNext(iter));
    return false;
}

private bool findLoadingDirectoryPlaceholder(TreeModelIF model, string directoryId,
    ref TreeIter directory, ref TreeIter placeholder)
{
    if (!findDirectoryTreeIter(model, new TreeIter(), false, directoryId, directory))
        return false;
    TreeIter child;
    if (!model.iterChildren(child, directory))
        return false;
    do
    {
        auto kind = model.getValueString(child, 1);
        if ((kind == "Placeholder" || kind == "Loading")
            && model.getValueString(child, 3) == directoryId)
        {
            placeholder = child;
            return true;
        }
    }
    while (model.iterNext(child));
    return false;
}

private bool findTreeIterByValue(TreeModelIF model, TreeIter parent, bool hasParent,
    int column, string value, ref TreeIter result)
{
    TreeIter iter;
    if (hasParent)
    {
        if (!model.iterChildren(iter, parent))
            return false;
    }
    else if (!model.getIterFirst(iter))
    {
        return false;
    }
    do
    {
        if (model.getValueString(iter, column) == value)
        {
            result = iter;
            return true;
        }
        if (model.iterHasChild(iter) && findTreeIterByValue(model, iter, true,
            column, value, result))
            return true;
    }
    while (model.iterNext(iter));
    return false;
}

private void restoreExpandedDirectories(TreeView treeView, string[] expandedIds)
{
    auto model = treeView.getModel();
    foreach (id; expandedIds)
    {
        TreeIter root;
        TreeIter iter;
        if (findDirectoryTreeIter(model, root, false, id, iter))
            treeView.expandRow(model.getPath(iter), false);
    }
}

private void expandFirstTreeRoot(TreeView treeView)
{
    auto model = treeView.getModel();
    TreeIter root;
    if (model !is null && model.getIterFirst(root))
        treeView.expandRow(model.getPath(root), false);
}

private string[] findDirectoryPathForFile(DirectorySource source, string parentId,
    string fileId)
{
    foreach (file; source.listFiles(parentId, 0, size_t.max))
    {
        if (file.id == fileId)
            return [parentId];
    }
    foreach (directory; source.listDirectories(parentId))
    {
        auto nested = findDirectoryPathForFile(source, directory.id, fileId);
        if (nested.length > 0)
            return [parentId] ~ nested;
    }
    return [];
}

private void selectPendingTreeFile(DocumentTab document)
{
    if (document.pendingTreeRevealFileId.length == 0)
        return;
    TreeIter root;
    TreeIter fileIter;
    auto model = document.directoryTreeView.getModel();
    auto found = findDirectoryTreeIter(model, root, false,
        document.pendingTreeRevealFileId, fileIter);
    if (!found && document.selectedTreeCursor.relativePath.length > 0)
        found = findTreeIterByValue(model, root, false, 5,
            document.selectedTreeCursor.relativePath, fileIter);
    if (found)
    {
        document.syncingTreeSelection = true;
        document.directoryTreeView.getSelection().selectIter(fileIter);
        document.syncingTreeSelection = false;
        document.pendingTreeRevealFileId = "";
    }
}

private void updateTreeNodeVisibility(DocumentTab document, TreeIter iter,
    Value visibilityValue)
{
    auto store = document.directoryTreeStore;
    auto kind = store.getValueString(iter, 1);
    auto nodeId = store.getValueString(iter, TREE_COL_NODE_ID);
    auto parentId = store.getValueString(iter, 3);
    auto sourceIndexText = store.getValueString(iter, TREE_COL_PROJECTION_INDEX);
    size_t sourceIndex = size_t.max;
    if (sourceIndexText.length > 0)
    {
        try
            sourceIndex = to!size_t(sourceIndexText);
        catch (Exception)
        {
        }
    }
    if (kind == "Directory")
    {
        if (document.directorySourceFiltered && !document.directorySourceRemote)
        {
            auto fileCount = sourceIndex < document.visibleDirectoryFileCounts.length
                ? document.visibleDirectoryFileCounts[sourceIndex] : 0;
            auto aggregateSize = sourceIndex
                < document.visibleDirectoryAggregateSizes.length
                ? document.visibleDirectoryAggregateSizes[sourceIndex] : 0;
            store.setValue(iter, 2, format("%s files | %s bytes",
                fileCount, aggregateSize));
            store.setValue(iter, TREE_COL_SORT_SIZE,
                format("%020d", aggregateSize));
        }
        else if (!document.directorySourceFiltered)
        {
            store.setValue(iter, 2,
                store.getValueString(iter, TREE_COL_BASE_SUMMARY));
            store.setValue(iter, TREE_COL_SORT_SIZE,
                store.getValueString(iter, TREE_COL_BASE_SORT_SIZE));
        }
    }
    auto visible = document.directorySourceFiltered
        ? (document.directorySourceRemote
            ? directoryTreeNodeVisible(kind, nodeId, parentId, true,
                document.visibleTreeNodeIds)
            : directoryTreeNodeVisibleByIndex(kind, sourceIndex, true,
                document.visibleTreeFileIndexes,
                document.visibleTreeDirectoryIndexes,
                document.hasVisibleTreeMatches))
        : true;
    setTreeNodeVisible(store, iter, visible, visibilityValue);

    TreeIter child;
    if (store.iterChildren(child, iter))
    {
        do
            updateTreeNodeVisibility(document, child, visibilityValue);
        while (store.iterNext(child));
    }
    if (kind == "Directory"
        && (document.treeSortOrder == TreeSortOrder.sizeAscending
            || document.treeSortOrder == TreeSortOrder.sizeDescending))
        reorderTreeChildren(store, iter, document.treeSortOrder);
}

private bool collectMaterializedTreeMatches(DocumentTab document, TreeIter iter,
    string parentDirectoryId, FileFilter filter)
{
    auto store = document.directoryTreeStore;
    auto kind = store.getValueString(iter, 1);
    auto nodeId = store.getValueString(iter, TREE_COL_NODE_ID);
    bool visible;
    if (kind == "Directory")
    {
        visible = nodeId == "root"
            || (nodeId in document.visibleTreeNodeIds) !is null;
        TreeIter child;
        if (store.iterChildren(child, iter))
        {
            do
                visible = collectMaterializedTreeMatches(document, child,
                    nodeId, filter) || visible;
            while (store.iterNext(child));
        }
        if (visible)
            document.visibleTreeNodeIds[nodeId] = true;
        return visible;
    }
    if (kind == "File"
        && treeFileMatchesFilter(store.getValueString(iter, 0),
            store.getValueString(iter, 5),
            store.getValueString(iter, 10) == "1",
            store.getValueString(iter, 11) == "1",
            store.getValueString(iter, 12) == "1",
            store.getValueString(iter, 13) == "1",
            store.getValueString(iter, 8) == "1",
            store.getValueString(iter, 14) == "1",
            store.getValueString(iter, 15) == "1", filter))
    {
        document.visibleTreeNodeIds[nodeId] = true;
        document.visibleTreeNodeIds[parentDirectoryId] = true;
        return true;
    }
    return false;
}

private void updateTreeModelVisibility(DocumentTab document, FileFilter filter)
{
    if (document.directorySourceFiltered && document.directorySourceRemote)
    {
        document.visibleTreeNodeIds["root"] = true;
        TreeIter root;
        if (document.directoryTreeStore.getIterFirst(root))
            collectMaterializedTreeMatches(document, root, "", filter);
    }
    auto visibilityValue = new Value();
    visibilityValue.init(GType.BOOLEAN);
    TreeIter iter;
    if (document.directoryTreeStore.getIterFirst(iter))
    {
        do
            updateTreeNodeVisibility(document, iter, visibilityValue);
        while (document.directoryTreeStore.iterNext(iter));
    }
    document.directoryTreeFilterModel.refilter();
}

private void setTreeSubtreeVisible(TreeStore store, TreeIter iter, bool visible,
    Value visibilityValue = null)
{
    if (visibilityValue is null)
    {
        visibilityValue = new Value();
        visibilityValue.init(GType.BOOLEAN);
    }
    setTreeNodeVisible(store, iter, visible, visibilityValue);
    TreeIter child;
    if (store.iterChildren(child, iter))
    {
        do
            setTreeSubtreeVisible(store, child, visible, visibilityValue);
        while (store.iterNext(child));
    }
}

/** Render or update a source projection while preserving materialized JSON nodes. */
void renderDirectoryTree(DocumentTab document, DirectorySource source,
    string[] expandedIds, FileFilter filter = FileFilter(),
    TreeSortOrder order = TreeSortOrder.nameAscending)
{
    auto store = document.directoryTreeStore;
    auto treeView = document.directoryTreeView;
    string previousSelectionId;
    TreeModelIF previousSelectionModel;
    TreeIter previousSelectionIter;
    if (treeView.getSelection().getSelected(previousSelectionModel,
            previousSelectionIter)
        && previousSelectionModel.getValueString(previousSelectionIter, 1) == "File")
    {
        previousSelectionId = previousSelectionModel.getValueString(
            previousSelectionIter, 3);
        document.selectedTreeFileId = previousSelectionId;
        document.selectedTreeCursor.relativePath = previousSelectionModel.getValueString(
            previousSelectionIter, 5);
    }
    auto resetTree = !document.reuseDirectoryTreeNodes;
    if (resetTree)
        store.clear();

    TreeIter root;
    auto rootNode = source.root;
    if (!findDirectoryTreeIter(store, new TreeIter(), false, rootNode.id, root))
        appendDirectoryTreeNode(store, source, rootNode, null, filter, order);
    else
    {
        store.setValue(root, 0, rootNode.name.length > 0
            ? rootNode.name : "(source root)");
        store.setValue(root, 2,
            format("%s files | %s bytes", rootNode.fileCount, rootNode.aggregateSize));
        store.setValue(root, 5, rootNode.relativePath);
        store.setValue(root, TREE_COL_PROJECTION_INDEX,
            rootNode.sourceIndex.to!string);
        store.setValue(root, TREE_COL_BASE_SUMMARY,
            format("%s files | %s bytes", rootNode.fileCount,
                rootNode.aggregateSize));
        store.setValue(root, TREE_COL_SORT_SIZE,
            format("%020d", rootNode.aggregateSize));
        store.setValue(root, TREE_COL_BASE_SORT_SIZE,
            format("%020d", rootNode.aggregateSize));
    }

    if (document.directorySourceFiltered)
        updateTreeModelVisibility(document, filter);
    else
    {
        TreeIter iter;
        auto visibilityValue = new Value();
        visibilityValue.init(GType.BOOLEAN);
        if (store.getIterFirst(iter))
        {
            do
                setTreeSubtreeVisible(store, iter, true, visibilityValue);
            while (store.iterNext(iter));
        }
        document.directoryTreeFilterModel.refilter();
    }
    document.reuseDirectoryTreeNodes = true;
    restoreExpandedDirectories(treeView, expandedIds);
    if (previousSelectionId.length > 0)
        document.pendingTreeRevealFileId = previousSelectionId;
    selectPendingTreeFile(document);
}

/** Keep the current tree visible while its background filter runs. */
private void showFilteringTreePlaceholder(DocumentTab document)
{
    document.status.setText("Filtering files...");
}

/** Show a non-expandable loading row until a document source is attached. */
private void showDocumentTreeLoadingPlaceholder(DocumentTab document)
{
    document.directoryTreeStore.clear();
    auto iter = document.directoryTreeStore.createIter(null);
    document.directoryTreeStore.setValue(iter, 0, "Loading directory tree...");
    document.directoryTreeStore.setValue(iter, 1, "Loading");
    document.directoryTreeStore.setValue(iter, TREE_COL_NODE_ID, "Loading:source");
    setTreeNodeVisible(document.directoryTreeStore, iter, true);
}

private void collectDirectoryTreeNodeIds(TreeStore store, TreeIter parent,
    bool hasParent, ref string[] ids, ref bool[string] seen,
    const(bool[string]) expandedIds)
{
    TreeIter iter;
    if (hasParent)
    {
        if (!store.iterChildren(iter, parent))
            return;
    }
    else if (!store.getIterFirst(iter))
        return;

    do
    {
        if (store.getValueString(iter, 1) == "Directory")
        {
            auto id = store.getValueString(iter, 3);
            bool hasLoadedChildren;
            TreeIter child;
            if (store.iterChildren(child, iter))
            {
                do
                {
                    auto childKind = store.getValueString(child, 1);
                    if (childKind != "Placeholder" && childKind != "Loading"
                        && childKind != "Page" && childKind != "LoadingPage")
                    {
                        hasLoadedChildren = true;
                        break;
                    }
                }
                while (store.iterNext(child));
            }
            if (id.length > 0 && id !in seen
                && ((id in expandedIds) !is null || hasLoadedChildren))
            {
                seen[id] = true;
                ids ~= id;
            }
        }
        if (store.iterHasChild(iter))
            collectDirectoryTreeNodeIds(store, iter, true, ids, seen,
                expandedIds);
    }
    while (store.iterNext(iter));
}

private string[] directoryTreeIdsToRefresh(TreeStore store,
    const(string)[] expandedIds)
{
    string[] ids;
    bool[string] seen;
    bool[string] expanded;
    foreach (id; expandedIds)
    {
        if (id.length > 0 && id !in seen)
        {
            seen[id] = true;
            expanded[id] = true;
            ids ~= id;
        }
    }
    collectDirectoryTreeNodeIds(store, new TreeIter(), false, ids, seen,
        expanded);
    return ids;
}

/** Worker result payload for background JSON loading. */
struct AsyncLoadResult
{
    BlobRow[] allRows;
    DirectoryTree directoryTree;
    DirectorySource directorySource;
    bool[string] visibleTreeNodeIds;
    AsyncExpandedDirectoryRows[] expandedDirectoryRows;
    string filePath;
    int dataVersion = -1;
    string rootShape;
    string rootKeysSummary;
    string error;
    long elapsedMs;
    size_t pageOffset;
    size_t pageTotal;
    bool pagedSource;
    long nextBlobId;
    bool hasMore;
    long[] blobIds;
    RepositoryBlobFlags[] blobFlags;
}

struct AsyncDirectoryResult
{
    string filePath;
    string directoryId;
    bool initial;
    FileFilter filter;
    TreeSortOrder sortOrder;
    DirectoryNode[] directories;
    FileNode[] files;
    string error;
}

struct AsyncNestedEntryResult
{
    string filePath;
    string blobId;
    bool archive;
    size_t offset;
    size_t nextOffset;
    NestedFileNode[] entries;
    bool hasMore;
    string error;
}

enum size_t repositoryPageSize = 250;

/** Worker result payload for background text filtering. */
struct AsyncExpandedDirectoryRows
{
    string directoryId;
    DirectoryNode[] directories;
    FilePage filePage;
}

struct AsyncFilterResult
{
    BlobRow[] filteredRows;
    bool[] visibleTreeFileIndexes;
    bool[] visibleTreeDirectoryIndexes;
    size_t[] visibleDirectoryFileCounts;
    ulong[] visibleDirectoryAggregateSizes;
    size_t[] visibleDirectoryChildCounts;
    bool hasVisibleTreeMatches;
    AsyncExpandedDirectoryRows[] expandedDirectoryRows;
    string query;
    bool caseSensitive;
    string mediaStats;
    string error;
    long elapsedMs;
}

/** Reconcile only already-expanded JSON directories without rebuilding the tree. */
private void refreshExpandedJsonDirectories(DocumentTab document, FileFilter filter,
    TreeSortOrder order, bool caseSensitive)
{
    auto source = document.unfilteredDirectorySource;
    if (source is null || document.directorySourceRemote)
        return;
    auto sourcePath = document.filePath;
    auto requestId = ++document.directoryTreeRefreshRequestId;
    auto expandedIds = directoryTreeIdsToRefresh(document.directoryTreeStore,
        document.expandedDirectoryIds);
    new Thread({
        AsyncExpandedDirectoryRows[] pages;
        string error;
        try
        {
            foreach (directoryId; expandedIds)
            {
                AsyncExpandedDirectoryRows page;
                page.directoryId = directoryId;
                page.directories = source.listDirectories(directoryId, filter);
                page.filePage = source.listFilteredFilesPage(directoryId,
                    FileCursor(), 251, filter, sourceFileSortOrder(order));
                pages ~= page;
            }
        }
        catch (Exception ex)
            error = ex.msg;
        new Idle({
            if (document.filePath != sourcePath
                || requestId != document.directoryTreeRefreshRequestId
                || document.directorySourceFiltered
                || !sameTreeFilter(filter,
                    treeFilterForDocument(document, caseSensitive)))
                return false;
            if (error.length > 0)
            {
                document.status.setText("Failed to restore directory rows: " ~ error);
                return false;
            }
            foreach (page; pages)
            {
                TreeIter root;
                TreeIter parent;
                if (!findDirectoryTreeIter(document.directoryTreeStore, root, false,
                        page.directoryId, parent))
                    continue;
                populateDirectoryTreeRows(document.directoryTreeStore, parent,
                    page.directories, page.filePage.files, true, order,
                    page.filePage.hasMore, page.filePage.nextCursor);
            }
            updateTreeModelVisibility(document, filter);
            restoreExpandedDirectories(document.directoryTreeView,
                document.expandedDirectoryIds);
            return false;
        });
    }).start();
}

/** Smallest window width accepted when restoring geometry. */
enum int MIN_VALID_WINDOW_WIDTH = 320;
/** Smallest window height accepted when restoring geometry. */
enum int MIN_VALID_WINDOW_HEIGHT = 240;

/** Summarize checksum availability for the list view.
 *
 * Params:
 *     row = Blob row whose checksum fields should be summarized.
 * Returns: none, partial, or full depending on checksum coverage.
 * Throws: None.
 */
string checksumSetStatus(const(BlobRow) row)
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
    return present == 1 ? "partial (1/3)" : "partial (2/3)";
}

/** Summarize media subtype flags for the list view.
 *
 * Params:
 *     row = Blob row whose media flags should be summarized.
 * Returns: A compact media marker list or yes/dash when no individual type
 *     markers apply.
 * Throws: None.
 */
string mediaInfoSummary(const(BlobRow) row)
{
    auto flags = (row.hasVideo ? 1 : 0) | (row.hasAudio ? 2 : 0)
        | (row.hasImage ? 4 : 0) | (row.hasText ? 8 : 0);
    final switch (flags)
    {
    case 0: return row.hasMedia ? "yes" : "-";
    case 1: return "V";
    case 2: return "A";
    case 3: return "V,A";
    case 4: return "I";
    case 5: return "V,I";
    case 6: return "A,I";
    case 7: return "V,A,I";
    case 8: return "T";
    case 9: return "V,T";
    case 10: return "A,T";
    case 11: return "V,A,T";
    case 12: return "I,T";
    case 13: return "V,I,T";
    case 14: return "A,I,T";
    case 15: return "V,A,I,T";
    }
}

/** Estimate the natural width required for the blob table columns.
 *
 * Params:
 *     document = Active document tab whose table should be measured.
 *     columnLimit = Optional maximum column count to include in the sum.
 * Returns: Estimated width in pixels for the visible table columns.
 * Throws: None.
 */
int measureTableColumnsWidth(DocumentTab document, int columnLimit = -1)
{
    auto columnCount = cast(int) document.tableView.getNColumns();
    if (columnCount <= 0)
    {
        return 0;
    }

    if (columnLimit >= 0 && columnLimit < columnCount)
    {
        columnCount = columnLimit;
    }

    int totalWidth = 0;
    foreach (columnIndex; 0 .. columnCount)
    {
        auto column = document.tableView.getColumn(columnIndex);
        if (column is null || !column.getVisible())
        {
            continue;
        }
        auto columnWidth = column.getWidth();
        auto minWidth = column.getMinWidth();
        totalWidth += columnWidth > minWidth ? columnWidth : minWidth;
    }

    return totalWidth;
}

/** Estimate or return the cached natural width of the blob table.
 *
 * Params:
 *     document = Active document tab whose cached width should be read.
 * Returns: Cached natural width when available, otherwise a fresh estimate.
 * Throws: None.
 */
int naturalListWidth(DocumentTab document)
{
    return document.tableNaturalWidth > 0 ? document.tableNaturalWidth
        : measureTableColumnsWidth(document);
}

/** Estimate or return the cached minimum width that keeps the first two columns visible.
 *
 * Params:
 *     document = Active document tab whose cached minimum width should be read.
 * Returns: Cached minimum width when available, otherwise a fresh estimate for
 *     the leading columns.
 * Throws: None.
 */
int minimumListWidth(DocumentTab document)
{
    return document.tableMinimumWidth > 0 ? document.tableMinimumWidth
        : measureTableColumnsWidth(document, 2);
}

/** Measure the table columns once and freeze them at their natural widths.
 *
 * Params:
 *     document = Active document tab whose blob table should be measured.
 * Returns: Nothing.
 * Throws: None.
 */
void lockMainTableColumnWidths(DocumentTab document)
{
    if (document is null || document.tableView is null || document.tableNaturalWidth > 0)
    {
        return;
    }

    if (document.tableView.getModel() is null)
    {
        document.tableView.setModel(document.tableStore);
    }

    document.tableView.columnsAutosize();

    auto columnCount = cast(int) document.tableView.getNColumns();
    int totalWidth = 0;
    int minimumWidth = 0;
    logLineVerbose("[layout] measuring columns for ", document.filePath,
        ": columnCount=", columnCount);
    foreach (columnIndex; 0 .. columnCount)
    {
        auto column = document.tableView.getColumn(columnIndex);
        if (column is null || !column.getVisible())
        {
            continue;
        }

        auto measuredWidth = column.getWidth();
        auto measuredMinWidth = column.getMinWidth();
        if (measuredWidth <= 0)
        {
            measuredWidth = measuredMinWidth;
        }
        if (measuredWidth <= 0 && columnIndex >= 5)
        {
            measuredWidth = MAIN_TABLE_FIXED_COLUMN_WIDTH;
        }
        if (measuredWidth <= 0)
        {
            logLineVerbose("[layout] column ", columnIndex,
                " skipped for ", document.filePath,
                ": width=", column.getWidth(),
                ", min=", measuredMinWidth,
                ", fallbackFixed=", (columnIndex >= 5 ? MAIN_TABLE_FIXED_COLUMN_WIDTH : -1));
            continue;
        }

        column.setSizing(GtkTreeViewColumnSizing.FIXED);
        column.setFixedWidth(measuredWidth);
        totalWidth += measuredWidth;
        if (columnIndex < 2)
        {
            minimumWidth += measuredWidth;
        }
        logLineVerbose("[layout] column ", columnIndex,
            " measured for ", document.filePath,
            ": width=", measuredWidth,
            ", min=", measuredMinWidth,
            ", fallbackFixed=", (columnIndex >= 5 ? MAIN_TABLE_FIXED_COLUMN_WIDTH : -1),
            ", fixed=", measuredWidth,
            ", runningTotal=", totalWidth,
            ", runningMinimum=", minimumWidth);
    }

    document.tableNaturalWidth = totalWidth;
    document.tableMinimumWidth = minimumWidth;
    logLineVerbose("[layout] measured table widths for ", document.filePath,
        ": total=", totalWidth, ", minimum=", minimumWidth);
}

/** Measure table widths after GTK has finished laying out the current model.
 *
 * Params:
 *     document = Active document tab whose table should be finalized.
 *     fitHorizontalSplit = Callback used when the split should be fit to the
 *         measured table width.
 *     restoreSplit = Callback used when the previous split position should be
 *         restored instead.
 * Returns: Nothing.
 * Throws: None.
 */
void finalizeTableColumnMeasurement(
    DocumentTab document,
    void delegate(DocumentTab) fitHorizontalSplit,
    void delegate(DocumentTab) restoreSplit
)
{
    if (document is null || document.tableView is null)
    {
        return;
    }

    if (document.tableView.getModel() is null)
    {
        document.tableView.setModel(document.tableStore);
    }

    lockMainTableColumnWidths(document);
    logLineVerbose("[layout] finalize measurement for ", document.filePath,
        ": fitAfterLoad=", document.fitHorizontalSplitAfterLoad);

    if (document.fitHorizontalSplitAfterLoad)
    {
        if (fitHorizontalSplit !is null)
        {
            fitHorizontalSplit(document);
        }
    }
    else
    {
        if (restoreSplit !is null)
        {
            restoreSplit(document);
        }
    }
}

/** Count media subtype hits in the currently filtered row set.
 *
 * Params:
 *     rows = Blob rows to count media subtype hits from.
 * Returns: Formatted string with counts of each media subtype.
 * Throws: None.
 */
string mediaHitStats(const(BlobRow)[] rows)
{
    size_t videoCount = 0;
    size_t audioCount = 0;
    size_t imageCount = 0;
    size_t textCount = 0;
    size_t fileTypeCount = 0;
    size_t archiveCount = 0;
    size_t torrentCount = 0;

    foreach (row; rows)
    {
        if (row.hasVideo)
        {
            ++videoCount;
        }
        if (row.hasAudio)
        {
            ++audioCount;
        }
        if (row.hasImage)
        {
            ++imageCount;
        }
        if (row.hasText)
        {
            ++textCount;
        }
        if (row.hasFileType)
        {
            ++fileTypeCount;
        }
        if (row.hasArchive)
        {
            ++archiveCount;
        }
        if (row.hasTorrent)
        {
            ++torrentCount;
        }
    }

    return format("hits V:%s A:%s I:%s T:%s FT:%s AR:%s TO:%s", videoCount, audioCount, imageCount, textCount, fileTypeCount, archiveCount, torrentCount);
}

private string primaryTreeFileNodeId(const(BlobRow) row, size_t fallbackOrdinal)
{
    auto sourceOrdinal = row.sourceOrdinal == size_t.max
        ? fallbackOrdinal : row.sourceOrdinal;
    if (row.sourceBlob !is null)
    {
        foreach (referenceIndex, spec; row.sourceBlob.fileSpecs)
        {
            if (spec !is null && spec.fileName.length > 0
                && (row.primaryFileName.length == 0
                    || spec.fileName == row.primaryFileName))
                return jsonFileNodeId(sourceOrdinal, referenceIndex);
        }
    }
    return jsonFileNodeId(sourceOrdinal, 0);
}

/** Convert a base64-encoded digest into lowercase hexadecimal text.
 *
 * Params:
 *     digest = Base64-encoded digest string.
 * Returns: Lowercase hexadecimal representation of the digest, or an error
 *     placeholder when the input is invalid.
 * Throws: None.
 */
string digestBase64ToHex(string digest)
{
    if (digest.length == 0)
    {
        return "-";
    }

    try
    {
        auto bytes = Base64.decode(digest);
        auto builder = appender!string();
        foreach (b; bytes)
        {
            builder.put(format("%02x", b));
        }
        return builder.data;
    }
    catch (Exception)
    {
        return "<invalid base64>";
    }
}

/** Program entry point.
 *
 * Params:
 *     args = Process command-line arguments.
 * Returns: Exit code for the application process.
 * Throws: Unexpected startup or runtime failures may propagate.
 */
int runMainWindow(string[] args, ref CliOptions cli)
{
    auto loadedState = loadAppState();

    GStreamer.init(args);
    Main.init(args);
    installApplicationCss();

    // Construct the main window and shared toolbar widgets, which will be manipulated and re-parented by document tabs.

    auto mainBuilder = new Builder();
    logLineVerbose("[ui] loading main window builder");
    mainBuilder.addFromString(import("source/ui/mainwindow.ui"));
    logLineVerbose("[ui] main window builder loaded, objects=", mainBuilder.getObjects().length);

    auto window = builderObject!Window(mainBuilder, "main", "mainWindow");
    window.setDefaultSize(loadedState.windowWidth, loadedState.windowHeight);

    auto accelGroup = new AccelGroup();
    window.addAccelGroup(accelGroup);

    auto root = builderObject!Box(mainBuilder, "main", "root");
    auto fileMenu = builderObject!Menu(mainBuilder, "main", "fileMenu");
    auto editMenu = builderObject!Menu(mainBuilder, "main", "editMenu");
    auto helpMenu = builderObject!Menu(mainBuilder, "main", "helpMenu");
    auto recentFilesMenuItem = builderObject!MenuItem(mainBuilder, "main", "recentFilesMenuItem");
    auto content = builderObject!Box(mainBuilder, "main", "content");
    auto separator = builderObject!Separator(mainBuilder, "main", "separator");
    auto toolbar = builderObject!Box(mainBuilder, "main", "toolbar");
    auto fileOpenMenuItem = builderObject!MenuItem(mainBuilder, "main", "fileOpenMenuItem");
    auto fileOpenRepositoryMenuItem = builderObject!MenuItem(mainBuilder, "main", "fileOpenRepositoryMenuItem");
    auto fileExportCsvMenuItem = builderObject!MenuItem(mainBuilder, "main", "fileExportCsvMenuItem");
    auto fileExportJsonMenuItem = builderObject!MenuItem(mainBuilder, "main", "fileExportJsonMenuItem");
    auto fileCloseMenuItem = builderObject!MenuItem(mainBuilder, "main", "fileCloseMenuItem");
    auto fileReloadMenuItem = builderObject!MenuItem(mainBuilder, "main", "fileReloadMenuItem");
    auto fileCancelOperationMenuItem = builderObject!MenuItem(mainBuilder, "main", "fileCancelOperationMenuItem");
    auto fileQuitMenuItem = builderObject!MenuItem(mainBuilder, "main", "fileQuitMenuItem");
    auto editApplyFilterMenuItem = builderObject!MenuItem(mainBuilder, "main", "editApplyFilterMenuItem");
    auto editClearFilterMenuItem = builderObject!MenuItem(mainBuilder, "main", "editClearFilterMenuItem");
    auto editResetMetricsMenuItem = builderObject!MenuItem(mainBuilder, "main", "editResetMetricsMenuItem");
    auto editPreferencesMenuItem = builderObject!MenuItem(mainBuilder, "main", "editPreferencesMenuItem");
    auto helpShortcutsMenuItem = builderObject!MenuItem(mainBuilder, "main", "helpShortcutsMenuItem");
    auto helpAboutMenuItem = builderObject!MenuItem(mainBuilder, "main", "helpAboutMenuItem");
    auto btnReload = builderObject!Button(mainBuilder, "main", "btnReload");
    auto btnRelayout = builderObject!Button(mainBuilder, "main", "btnRelayout");
    auto btnCancelLoad = builderObject!Button(mainBuilder, "main", "btnCancelLoad");
    auto loadSpinner = builderObject!Spinner(mainBuilder, "main", "loadSpinner");
    Entry filterEntry;
    CheckButton filterMediaNot;
    CheckButton filterVideo;
    CheckButton filterAudio;
    CheckButton filterImage;
    CheckButton filterText;
    CheckButton filterFileType;
    CheckButton filterArchive;
    CheckButton filterTorrent;
    auto progressBar = builderObject!ProgressBar(mainBuilder, "main", "progressBar");
    auto notebook = builderObject!Notebook(mainBuilder, "main", "notebook");

    DocumentTab[] documents;
    string[] pendingStartupPaths;
    int pendingStartupSelectIndex = -1;

    bool prefAutoApplyFilter = loadedState.prefAutoApplyFilter;
    bool prefCaseSensitiveFilter = loadedState.prefCaseSensitiveFilter;
    bool prefDetailsBelow = loadedState.prefDetailsBelow;
    bool prefRestoreOpenFiles = loadedState.prefRestoreOpenFiles;
    string[] recentFilePaths = loadedState.recentFilePaths.dup;
    string externalOpenProgram = loadedState.externalOpenProgram.length > 0 ? loadedState.externalOpenProgram : "xdg-open";
    bool previewVideoAutostart = loadedState.previewVideoAutostart;
    double previewVideoVolume = loadedState.previewVideoVolume < 0.0 ? 0.5
        : loadedState.previewVideoVolume > 1.0 ? 1.0 : loadedState.previewVideoVolume;
    int recentFileLimit = loadedState.maxRecentFileCount;
    if (recentFileLimit < 0)
    {
        recentFileLimit = 10;
    }
    bool clearSavedWindowGeometryOnExit;
    bool allowRuntimeStatePersistence = !loadedState.hasWindowSize;
    bool isSyncingToolbarState;
    bool startupFilterPending = cli.filterOnStart.length > 0;
    bool selfTestQuitScheduled;
    int splitPositionHorizontal = loadedState.splitPositionHorizontal;
    int splitPositionVertical = loadedState.splitPositionVertical;
    int splitPositionPreview = loadedState.hasSplitPositionPreview ? loadedState.splitPositionPreview : 0;
    PreviewScaleMode previewScaleMode = clampPreviewScaleMode(loadedState.previewScaleMode);
    int lastKnownWindowWidth = loadedState.windowWidth;
    int lastKnownWindowHeight = loadedState.windowHeight;
    Timeout windowSizePersistTimer;
    bool isLoading;
    DocumentTab busyDocument;
    Timeout progressPulseTimer;
    Timeout previewVideoProgressTimer;
    Timeout selfTestQuitTimer;

    if (cli.disableAutoFilter)
    {
        prefAutoApplyFilter = false;
    }
    if (cli.caseSensitiveFilter)
    {
        prefCaseSensitiveFilter = true;
    }

    logLineVerbose("[startup] initial filter text length=", cli.filterOnStart.length,
        ", verbose=", cli.argVerboseOutputs);
    logLineVerbose("[startup] self-test mode=", cli.selfTestMode ? "yes" : "no",
        ", delayMs=", cli.selfTestDelayMs);

    /** Format internal timing values for status labels. */
    string formatTimingValue(long valueMs)
    {
        return valueMs >= 0 ? format("%s", valueMs) : "-";
    }

    /** Return the currently selected document tab, if any. */
    DocumentTab currentDocument()
    {
        auto pageIndex = notebook.getCurrentPage();
        if (pageIndex < 0 || pageIndex >= documents.length)
        {
            return null;
        }
        return documents[pageIndex];
    }

    /** Return the notebook page index for a given document instance. */
    int indexOfDocument(DocumentTab target)
    {
        foreach (idx, document; documents)
        {
            if (document is target)
            {
                return cast(int) idx;
            }
        }
        return -1;
    }

    /** Attach a standard application accelerator to one menu item. */
    void attachMenuAccelerator(MenuItem menuItem, char accelKey, GdkModifierType accelMods = GdkModifierType.CONTROL_MASK)
    {
        menuItem.addAccelerator("activate", accelGroup, accelKey, accelMods, GtkAccelFlags.VISIBLE);
    }

    /** Normalize a path so duplicate startup entries map to the same document tab. */
    string normalizeDocumentPath(string filePath)
    {
        if (filePath.length == 0)
        {
            return filePath;
        }
        return absolutePath(filePath);
    }

    void delegate(DocumentTab) closeDocumentTab;

    /** Build a compact mode-aware notebook tab label with a useful tooltip. */
    Widget createDocumentTabLabel(string filePath)
    {
        auto labelBox = new Box(Orientation.HORIZONTAL, 4);
        auto repositorySource = isRepositorySource(filePath);
        auto displayPath = repositorySource ? Repository.findRoot(filePath) : filePath;
        auto icon = new Image(repositorySource ? "folder" : "text-x-generic",
            GtkIconSize.MENU);
        auto label = new Label(baseName(displayPath));
        auto closeButton = new Button();
        closeButton.setLabel("x");
        closeButton.setTooltipText("Close tab");
        closeButton.addOnClicked((Button _) {
            foreach (document; documents)
            {
                if (document.filePath == filePath && closeDocumentTab !is null)
                {
                    closeDocumentTab(document);
                    break;
                }
            }
        });
        labelBox.packStart(icon, false, false, 0);
        labelBox.packStart(label, false, false, 0);
        labelBox.packStart(closeButton, false, false, 0);
        labelBox.setTooltipText((repositorySource ? "SQLite repository: " : "JSON file: ")
            ~ displayPath);
        labelBox.showAll();
        return labelBox;
    }

    /** Find an already open document tab by JSON file path. */
    DocumentTab findDocumentByPath(string filePath)
    {
        auto normalizedPath = normalizeDocumentPath(filePath);
        foreach (document; documents)
        {
            if (document.filePath == normalizedPath)
            {
                return document;
            }
        }
        return null;
    }

    /** Resolve a known-file entry path relative to the owning JSON file. */
    string resolveKnownFilePath(DocumentTab document, string knownFileName)
    {
        auto repositoryRoot = document.directorySourceRemote
            ? Repository.findRoot(document.filePath) : "";
        return resolveDocumentSourcePath(document.filePath, knownFileName,
            repositoryRoot);
    }

    void launchExternalPath(DocumentTab document, string resolvedPath,
        string program, string missingPathMessage)
    {
        if (resolvedPath.length == 0)
            return;
        if (!exists(resolvedPath))
        {
            document.status.setText(missingPathMessage ~ resolvedPath);
            return;
        }
        try
            spawnProcess([program, resolvedPath], null, Config.detached);
        catch (ProcessException ex)
            document.status.setText(format("Failed to launch %s: %s", program, ex.msg));
    }

    void openPathInFileManager(DocumentTab document, string sourcePath,
        bool containingDirectory = false)
    {
        auto resolvedPath = resolveKnownFilePath(document, sourcePath);
        if (containingDirectory)
            resolvedPath = dirName(resolvedPath);
        launchExternalPath(document, resolvedPath, "xdg-open", "Path not found: ");
    }

    /** Launch one known file in the user-configured external program. */
    void openKnownFileExternally(DocumentTab document, string knownFileName)
    {
        auto resolvedPath = resolveKnownFilePath(document, knownFileName);
        auto program = externalOpenProgram.length > 0 ? externalOpenProgram : "xdg-open";
        launchExternalPath(document, resolvedPath, program, "Known file not found: ");
    }

    void exportFilteredRows(DocumentTab document, bool json)
    {
        if (document is null)
            return;
        if (isLoading)
        {
            document.status.setText("Wait for the current operation before exporting.");
            return;
        }
        auto extension = json ? "json" : "csv";
        auto chooser = new FileChooserDialog(
            json ? "Export Filtered Rows as JSON" : "Export Filtered Rows as CSV",
            window, FileChooserAction.SAVE, ["_Cancel", "_Export"],
            [ResponseType.CANCEL, ResponseType.ACCEPT]);
        chooser.setDoOverwriteConfirmation(true);
        chooser.setCurrentName("dosierskanilo-subset." ~ extension);
        auto response = chooser.run();
        auto outputPath = response == cast(int) ResponseType.ACCEPT
            ? chooser.getFilename() : "";
        chooser.destroy();
        if (outputPath.length == 0)
            return;

        auto sourcePath = document.filePath;
        auto query = sourceQueryForDocument(document, prefCaseSensitiveFilter);
        document.status.setText(format("Exporting filtered rows to %s ...", outputPath));
        new Thread({
            size_t exportedRows;
            string error;
            try
            {
                auto rows = loadFilteredExportRows(sourcePath, query);
                exportedRows = rows.length;
                if (json)
                    writeRowsJson(outputPath, rows);
                else
                    writeRowsCsv(outputPath, rows);
            }
            catch (Exception ex)
                error = ex.msg;
            new Idle({
                if (findDocumentByPath(sourcePath) is document)
                    document.status.setText(error.length > 0
                        ? "Export failed: " ~ error
                        : format("Exported %s rows to %s", exportedRows, outputPath));
                return false;
            });
        }).start();
    }

    /** Refresh toolbar sensitivity from the global busy state and active tab presence. */
    void syncToolbarSensitivity()
    {
        auto hasCurrentDocument = currentDocument() !is null;
        // pathEntry und btnLoad entfernt
        btnReload.setSensitive(!isLoading && hasCurrentDocument);
        fileReloadMenuItem.setSensitive(!isLoading && hasCurrentDocument);
        fileExportCsvMenuItem.setSensitive(!isLoading && hasCurrentDocument);
        fileExportJsonMenuItem.setSensitive(!isLoading && hasCurrentDocument);
        btnCancelLoad.setSensitive(isLoading);
        fileCancelOperationMenuItem.setSensitive(isLoading);
        fileCloseMenuItem.setSensitive(!isLoading && hasCurrentDocument);
        fileOpenMenuItem.setSensitive(!isLoading);
        fileOpenRepositoryMenuItem.setSensitive(!isLoading);
        fileQuitMenuItem.setSensitive(true);
        recentFilesMenuItem.setSensitive(!isLoading && recentFilePaths.length > 0);
        if (hasCurrentDocument)
        {
            filterEntry.setSensitive(!isLoading);
            filterVideo.setSensitive(!isLoading);
            filterAudio.setSensitive(!isLoading);
            filterImage.setSensitive(!isLoading);
            filterText.setSensitive(!isLoading);
            filterMediaNot.setSensitive(!isLoading);
            filterFileType.setSensitive(!isLoading);
            filterArchive.setSensitive(!isLoading);
            filterTorrent.setSensitive(!isLoading);
            currentDocument().btnApplyFilter.setSensitive(!isLoading);
            currentDocument().btnClearFilter.setSensitive(!isLoading);
        }
        editApplyFilterMenuItem.setSensitive(!isLoading && hasCurrentDocument);
        editClearFilterMenuItem.setSensitive(!isLoading && hasCurrentDocument);
        editPreferencesMenuItem.setSensitive(!isLoading);
        editResetMetricsMenuItem.setSensitive(hasCurrentDocument);
        helpShortcutsMenuItem.setSensitive(true);
        helpAboutMenuItem.setSensitive(true);
    }

    /** Mirror the active tab's path and filter settings back into the shared toolbar. */
    void syncToolbarFromCurrentDocument()
    {
        isSyncingToolbarState = true;
        auto document = currentDocument();
        if (document is null)
        {
            syncToolbarSensitivity();
            isSyncingToolbarState = false;
            return;
        }
        filterEntry = document.filterEntry;
        filterVideo = document.filterVideoWidget;
        filterAudio = document.filterAudioWidget;
        filterImage = document.filterImageWidget;
        filterText = document.filterTextWidget;
        filterMediaNot = document.filterMediaNotWidget;
        filterFileType = document.filterFileTypeWidget;
        filterArchive = document.filterArchiveWidget;
        filterTorrent = document.filterTorrentWidget;

        // pathEntry entfernt
        filterEntry.setText(document.filterQuery is null ? "" : document.filterQuery);
        filterVideo.setActive(document.filterVideo);
        filterAudio.setActive(document.filterAudio);
        filterImage.setActive(document.filterImage);
        filterText.setActive(document.filterText);
        filterMediaNot.setActive(document.filterMediaNegated);
        filterFileType.setActive(document.filterFileType);
        filterArchive.setActive(document.filterArchive);
        filterTorrent.setActive(document.filterTorrent);
        syncToolbarSensitivity();
        isSyncingToolbarState = false;
    }

    /** Mirror the active tab's preview mode button state back into the preview toolbar. */
    void syncPreviewToolbarFromCurrentDocument()
    {
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }

        isSyncingToolbarState = true;
        document.detailPreviewContainButton.setActive(document.previewScaleMode == PreviewScaleMode.contain);
        document.detailPreviewFitWidthButton.setActive(document.previewScaleMode == PreviewScaleMode.fitWidth);
        document.detailPreviewFitHeightButton.setActive(document.previewScaleMode == PreviewScaleMode.fitHeight);
        document.detailPreviewCenterButton.setActive(document.previewScaleMode == PreviewScaleMode.center);
        document.detailPreviewCoverButton.setActive(document.previewScaleMode == PreviewScaleMode.cover);
        if (document.detailPreviewVolumeScale !is null)
        {
            document.detailPreviewVolumeScale.setValue(document.previewVideoVolume);
        }
        isSyncingToolbarState = false;
    }

    /** Update the preview-mode buttons of one tab without triggering toggle callbacks. */
    void syncPreviewToolbarFromDocument(DocumentTab document)
    {
        isSyncingToolbarState = true;
        document.detailPreviewContainButton.setActive(document.previewScaleMode == PreviewScaleMode.contain);
        document.detailPreviewFitWidthButton.setActive(document.previewScaleMode == PreviewScaleMode.fitWidth);
        document.detailPreviewFitHeightButton.setActive(document.previewScaleMode == PreviewScaleMode.fitHeight);
        document.detailPreviewCenterButton.setActive(document.previewScaleMode == PreviewScaleMode.center);
        document.detailPreviewCoverButton.setActive(document.previewScaleMode == PreviewScaleMode.cover);
        if (document.detailPreviewVolumeScale !is null)
        {
            document.detailPreviewVolumeScale.setValue(document.previewVideoVolume);
        }
        isSyncingToolbarState = false;
    }

    /** Apply one preview scaling mode to all open documents and refresh visible image previews. */
    void setPreviewScaleMode(PreviewScaleMode mode)
    {
        if (previewScaleMode == mode)
        {
            return;
        }

        previewScaleMode = mode;
        foreach (tab; documents)
        {
            tab.previewScaleMode = mode;
            if (tab.detailPreviewContainButton !is null)
            {
                syncPreviewToolbarFromDocument(tab);
            }
            if (tab.selectedPreviewIsImage)
            {
                refreshMediaPreview(tab);
            }
        }
    }

    /** Build the callback bundle required by the loading feedback helper. */
    LoadingStatusCallbacks loadingStatusCallbacks()
    {
        return LoadingStatusCallbacks(
            () { return isLoading; },
            (bool value) { isLoading = value; },
            () { return busyDocument; },
            (DocumentTab value) { busyDocument = value; },
            () { return progressPulseTimer; },
            (Timeout value) { progressPulseTimer = value; },
            () { syncToolbarSensitivity(); },
            (DocumentTab target, bool resizable) { setTableColumnsResizable(target, resizable); }
        );
    }


    /** Publish a global busy state while a tab-specific worker is active. */
    void setLoadingState(DocumentTab document, bool loading, string message = "")
    {
        ui.loadingstatus.setLoadingState(loadingStatusCallbacks(), document, loading, loadSpinner, progressBar, message);
    }

    /** Publish a load phase update onto the GTK main loop for a single document tab. */
    void setLoadingPhase(DocumentTab document, ulong expectedRequestId, string phaseText)
    {
        ui.loadingstatus.setLoadingPhase(loadingStatusCallbacks(), document, expectedRequestId, progressBar, phaseText);
    }

    /** Keep a document splitter divider within usable visible bounds. */
    int clampSplitPositionToVisibleBounds(DocumentTab document, Paned splitWidget, Orientation orientation, int requestedPosition)
    {
        enum int MIN_PRIMARY_EXTENT = 240;
        enum int MIN_DETAILS_EXTENT = 180;

        int totalExtent = orientation == Orientation.VERTICAL
            ? splitWidget.getAllocatedHeight() : splitWidget.getAllocatedWidth();

        if (totalExtent <= 0)
        {
            return requestedPosition;
        }
        if (totalExtent <= (MIN_PRIMARY_EXTENT + MIN_DETAILS_EXTENT))
        {
            return totalExtent / 2;
        }

        auto minPosition = MIN_PRIMARY_EXTENT;
        auto maxPosition = totalExtent - MIN_DETAILS_EXTENT;
        if (orientation == Orientation.HORIZONTAL)
        {
            auto naturalTableWidth = naturalListWidth(document);
            if (naturalTableWidth > 0 && naturalTableWidth < maxPosition)
            {
                maxPosition = naturalTableWidth;
            }

            minPosition = minimumListWidth(document);
        }
        if (requestedPosition < minPosition)
        {
            logLineVerbose("[layout] clamp low ", document.filePath,
                ": requested=", requestedPosition,
                ", min=", minPosition,
                ", max=", maxPosition,
                ", totalExtent=", totalExtent,
                ", natural=", naturalListWidth(document),
                ", minimum=", minimumListWidth(document));
            return minPosition;
        }
        if (requestedPosition > maxPosition)
        {
            logLineVerbose("[layout] clamp high ", document.filePath,
                ": requested=", requestedPosition,
                ", min=", minPosition,
                ", max=", maxPosition,
                ", totalExtent=", totalExtent,
                ", natural=", naturalListWidth(document),
                ", minimum=", minimumListWidth(document));
            return maxPosition;
        }
        logLineVerbose("[layout] clamp ok ", document.filePath,
            ": orientation=", cast(int) orientation,
            ", totalExtent=", totalExtent,
            ", requested=", requestedPosition,
            ", min=", minPosition,
            ", max=", maxPosition,
            ", natural=", naturalListWidth(document),
            ", minimum=", minimumListWidth(document));
        return requestedPosition;
    }

    /** Estimate the natural width required to show the blob list columns without truncating the split too early. */
    int preferredListSplitPosition(DocumentTab document)
    {
        return naturalListWidth(document);
    }

    /** Re-fit the horizontal splitter after GTK has real column widths available. */
    void schedulePreferredHorizontalSplit(DocumentTab document)
    {
        if (prefDetailsBelow)
        {
            return;
        }

        int attempt = 0;
        void delegate() fitLater;
        fitLater = {
            ++attempt;
            auto preferredPosition = preferredListSplitPosition(document);
            auto currentPosition = document.split.getPosition();
            auto targetPosition = preferredPosition > currentPosition ? preferredPosition
                : currentPosition;
            auto clampedPosition = clampSplitPositionToVisibleBounds(document, document.split, Orientation.HORIZONTAL, targetPosition);
            logLineVerbose("[layout] fit attempt ", attempt,
                " for ", document.filePath,
                ": current=", currentPosition,
                ", preferred=", preferredPosition,
                ", target=", targetPosition,
                ", clamped=", clampedPosition,
                ", tableNatural=", document.tableNaturalWidth,
                ", tableMinimum=", document.tableMinimumWidth);
            document.split.setPosition(clampedPosition);
            splitPositionHorizontal = clampedPosition;

            if (attempt >= 2 || clampedPosition == currentPosition)
            {
                return;
            }

            new Timeout(60, { fitLater(); return false; });
        };

        new Idle({ fitLater(); return false; });
    }

    /** Apply the shared details-pane orientation and divider position to one tab. */
    void applyDetailsPanePreference(DocumentTab document, bool captureCurrentPosition = true)
    {
        if (captureCurrentPosition && currentDocument() is document)
        {
            auto currentOrientation = document.split.getOrientation();
            auto currentPosition = document.split.getPosition();
            auto currentExtent = currentOrientation == Orientation.VERTICAL
                ? document.split.getAllocatedHeight() : document.split.getAllocatedWidth();
            if (currentExtent > 0 && currentOrientation == Orientation.VERTICAL)
            {
                splitPositionVertical = currentPosition;
            }
            else if (currentExtent > 0)
            {
                splitPositionHorizontal = currentPosition;
            }
        }

        auto orientation = prefDetailsBelow ? Orientation.VERTICAL : Orientation.HORIZONTAL;
        auto splitPosition = prefDetailsBelow ? splitPositionVertical : splitPositionHorizontal;
        document.split.setOrientation(orientation);

        if (orientation == Orientation.HORIZONTAL)
        {
            auto clampedPosition = clampSplitPositionToVisibleBounds(document, document.split,
                orientation, splitPosition);
            document.split.setPosition(clampedPosition);
        }
        int realizationAttempt;
        void delegate() applyRealizedPosition;
        applyRealizedPosition = {
            auto allocatedExtent = orientation == Orientation.VERTICAL
                ? document.split.getAllocatedHeight() : document.split.getAllocatedWidth();
            if (allocatedExtent <= 0 && realizationAttempt < 10)
            {
                ++realizationAttempt;
                new Timeout(50, { applyRealizedPosition(); return false; });
                return;
            }
            if (allocatedExtent <= 0)
            {
                logLineVerbose("[layout] defer split restore until tab is allocated for ",
                    document.filePath);
                return;
            }

            auto realizedClamped = clampSplitPositionToVisibleBounds(document, document.split,
                orientation, splitPosition);
            document.split.setPosition(realizedClamped);
            if (currentDocument() is document && orientation == Orientation.VERTICAL)
            {
                splitPositionVertical = realizedClamped;
            }
            else if (currentDocument() is document)
            {
                splitPositionHorizontal = realizedClamped;
            }
        };
        new Idle({ applyRealizedPosition(); return false; });
    }

    /** Apply the shared details-pane preference to all open document tabs. */
    void applyDetailsPanePreferenceToAll(bool captureCurrentPosition = true)
    {
        if (captureCurrentPosition)
        {
            auto active = currentDocument();
            if (active !is null)
            {
                auto orientation = active.split.getOrientation();
                auto extent = orientation == Orientation.VERTICAL
                    ? active.split.getAllocatedHeight() : active.split.getAllocatedWidth();
                if (extent > 0)
                {
                    if (orientation == Orientation.VERTICAL)
                        splitPositionVertical = active.split.getPosition();
                    else
                        splitPositionHorizontal = active.split.getPosition();
                }
            }
        }
        foreach (document; documents)
        {
            applyDetailsPanePreference(document, false);
        }
    }

    void delegate(DocumentTab) updateSelectedRowDetails;
    void delegate(DocumentTab) clearFilterForDocument;
    void delegate(string, string, DocumentTab) copyTextToClipboard;
    DocumentTab delegate(string, bool, bool) openDocumentFromPath;
    void delegate(DocumentTab) applyFilterForDocument;
    void delegate(DocumentTab, bool) loadDocument;
    void delegate(DocumentTab, string) revealTreeFile;
    void delegate() advanceStartupQueue;
    void delegate(bool) persistCurrentState;

    /** Build and wire a new document tab widget hierarchy. */
    DocumentTab createDocumentTab(string filePath)
    {
        auto document = new DocumentTab();
        document.filePath = filePath;
        auto useStartupFilter = startupFilterPending;
        startupFilterPending = false;
        bool restoredFilterState;
        auto treeStatePrefix = filePath ~ "\t";
        foreach (treeState; loadedState.expandedTreeStates)
        {
            if (treeState.length > treeStatePrefix.length
                && treeState[0 .. treeStatePrefix.length] == treeStatePrefix)
                document.expandedDirectoryIds ~= treeState[treeStatePrefix.length .. $];
        }
        foreach (treeState; loadedState.selectedTreeStates)
        {
            if (treeState.length > treeStatePrefix.length
                && treeState[0 .. treeStatePrefix.length] == treeStatePrefix)
            {
                document.pendingTreeRevealFileId = treeState[treeStatePrefix.length .. $];
                document.selectedTreeFileId = document.pendingTreeRevealFileId;
            }
        }
        foreach (cursorState; loadedState.treeCursorStates)
        {
            if (cursorState.documentPath != filePath)
                continue;
            document.selectedTreeDirectoryId = cursorState.directoryId;
            document.selectedTreeCursor = FileCursor(cursorState.relativePath,
                cursorState.cursorId, cursorState.size);
        }
        foreach (filterState; loadedState.documentFilterStates)
        {
            if (filterState.documentPath != filePath)
                continue;
            document.filterQuery = filterState.text;
            document.filterVideo = filterState.video;
            document.filterAudio = filterState.audio;
            document.filterImage = filterState.image;
            document.filterText = filterState.textStream;
            document.filterMediaNegated = filterState.mediaNegated;
            document.filterFileType = filterState.fileType;
            document.filterArchive = filterState.archive;
            document.filterTorrent = filterState.torrent;
            document.filterApplied = filterState.applied
                || documentFilterHasCriteria(document.filterQuery,
                    document.filterVideo, document.filterAudio, document.filterImage,
                    document.filterText, document.filterFileType, document.filterArchive,
                    document.filterTorrent);
            restoredFilterState = true;
        }
        foreach (treeState; loadedState.treeSortStates)
        {
            if (treeState.length > treeStatePrefix.length
                && treeState[0 .. treeStatePrefix.length] == treeStatePrefix)
            {
                auto sortText = treeState[treeStatePrefix.length .. $];
                try
                {
                    auto sortValue = to!int(sortText);
                    if (sortValue >= cast(int) TreeSortOrder.nameAscending
                        && sortValue <= cast(int) TreeSortOrder.sizeDescending)
                        document.treeSortOrder = cast(TreeSortOrder) sortValue;
                }
                catch (Exception)
                {
                }
            }
        }
        foreach (viewState; loadedState.viewModeStates)
        {
            if (viewState.length > treeStatePrefix.length
                && viewState[0 .. treeStatePrefix.length] == treeStatePrefix)
            {
                auto viewText = viewState[treeStatePrefix.length .. $];
                try
                {
                    auto viewValue = to!int(viewText);
                    if (viewValue >= 0 && viewValue <= 1)
                        document.resultViewPage = viewValue;
                }
                catch (Exception)
                {
                }
            }
        }
        foreach (sortState; loadedState.tableSortStates)
        {
            if (sortState.documentPath != filePath)
                continue;
            if (!sortState.sorted || !validBlobTableSortColumn(sortState.columnId)
                || (sortState.order != cast(int) GtkSortType.ASCENDING
                    && sortState.order != cast(int) GtkSortType.DESCENDING))
                continue;
            document.tableSortEnabled = true;
            document.tableSortColumnId = sortState.columnId;
            document.tableSortOrder = sortState.order;
        }
        if (!restoredFilterState)
            document.filterQuery = useStartupFilter ? cli.filterOnStart : "";
        document.previewScaleMode = previewScaleMode;
        document.previewVideoAutostart = previewVideoAutostart;
        document.previewVideoVolume = previewVideoVolume;

        document.tableStore = new ListStore([
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.UINT64,
            GType.UINT64,
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING,
            GType.STRING
        ]);
        document.tableView = new TreeView(document.tableStore);
        configureTableColumns(document.tableView);
        if (document.tableSortEnabled)
            document.tableStore.setSortColumnId(document.tableSortColumnId,
                cast(GtkSortType) document.tableSortOrder);
        document.tableStore.addOnSortColumnChanged((TreeSortableIF sortable) {
            int columnId;
            GtkSortType order;
            document.tableSortEnabled = document.tableStore.getSortColumnId(
                columnId, order);
            if (document.tableSortEnabled)
            {
                document.tableSortColumnId = columnId;
                document.tableSortOrder = cast(int) order;
            }
            if (currentDocument() is document)
                persistCurrentState(clearSavedWindowGeometryOnExit);
        });
        document.directoryTreeStore = new TreeStore([
            GType.STRING, GType.STRING, GType.STRING, GType.STRING, GType.STRING,
            GType.STRING, GType.STRING, GType.STRING, GType.STRING, GType.STRING,
            GType.STRING, GType.STRING, GType.STRING, GType.STRING, GType.STRING,
            GType.STRING, GType.STRING, GType.BOOLEAN, GType.STRING,
            GType.STRING, GType.STRING, GType.STRING
        ]);
        document.directoryTreeFilterModel = createDirectoryTreeFilter(
            document.directoryTreeStore);
        document.directoryTreeView = new TreeView(document.directoryTreeFilterModel);
        configureDirectoryTreeColumns(document.directoryTreeView);
        showDocumentTreeLoadingPlaceholder(document);
        document.directoryTreeView.addOnButtonPress((Event event, Widget _) {
            if (event.type != EventType.BUTTON_PRESS || event.button.button != 3)
                return false;
            auto buttonEvent = event.button;
            TreePath path;
            TreeViewColumn column;
            int cellX;
            int cellY;
            if (!document.directoryTreeView.getPathAtPos(cast(int) buttonEvent.x,
                cast(int) buttonEvent.y, path, column, cellX, cellY))
                return false;
            auto model = document.directoryTreeView.getModel();
            auto iter = new TreeIter();
            if (!model.getIter(iter, path))
                return false;
            document.directoryTreeView.getSelection().selectPath(path);
            auto kind = model.getValueString(iter, 1);
            if (kind == "Directory")
            {
                auto directoryId = model.getValueString(iter, 3);
                auto directoryPath = model.getValueString(iter, 5);
                auto menu = new Menu();
                menu.append(new MenuItem((MenuItem _) {
                    copyTextToClipboard("directory path", directoryPath, document);
                }, "Copy directory path", false));
                menu.append(new MenuItem((MenuItem _) {
                    openPathInFileManager(document, directoryPath);
                }, "Open in file manager", false));
                menu.append(new MenuItem((MenuItem _) {
                    if (directoryPath.length > 0)
                    {
                        filterEntry.setText(directoryPath);
                        document.filterQuery = directoryPath;
                        applyFilterForDocument(document);
                    }
                }, "Filter this directory", false));
                auto subtreeAction = document.directoryTreeView.rowExpanded(path)
                    ? "Collapse subtree" : "Expand subtree";
                menu.append(new MenuItem((MenuItem _) {
                    TreeIter currentIter;
                    TreeModelIF currentModel = document.directoryTreeView.getModel();
                    if (findDirectoryTreeIter(currentModel, new TreeIter(), false,
                            directoryId, currentIter))
                    {
                        toggleDirectorySubtree(document.directoryTreeView,
                            currentModel.getPath(currentIter));
                    }
                }, subtreeAction, false));
                menu.showAll();
                menu.popup(buttonEvent.button, buttonEvent.time);
                return true;
            }
            if (kind != "File")
                return false;
            auto name = model.getValueString(iter, 0);
            auto relativePath = model.getValueString(iter, 5);
            auto menu = new Menu();
            menu.append(new MenuItem((MenuItem _) {
                copyTextToClipboard("file name", name, document);
            }, "Copy file name", false));
            menu.append(new MenuItem((MenuItem _) {
                copyTextToClipboard("file path", relativePath, document);
            }, "Copy file path", false));
            menu.append(new MenuItem((MenuItem _) {
                openKnownFileExternally(document, relativePath);
            }, "Open file", false));
            menu.append(new MenuItem((MenuItem _) {
                openPathInFileManager(document, relativePath, true);
            }, "Show in file manager", false));
            menu.append(new MenuItem((MenuItem _) {
                updateSelectedRowDetails(document);
            }, "Show details", false));
            menu.append(new MenuItem((MenuItem _) {
                if (relativePath.length > 0)
                {
                    filterEntry.setText(relativePath);
                    document.filterQuery = relativePath;
                    applyFilterForDocument(document);
                }
            }, "Filter this file", false));
            menu.showAll();
            menu.popup(buttonEvent.button, buttonEvent.time);
            return true;
        });
        revealTreeFile = (DocumentTab target, string fileId) {
            if (target.directorySource is null)
                return;
            void applyReveal(string[] path)
            {
                if (path.length == 0)
                    return;
                target.pendingTreeRevealFileId = fileId;
                foreach (directoryId; path)
                {
                    bool known;
                    foreach (expandedId; target.expandedDirectoryIds)
                    {
                        if (expandedId == directoryId)
                        {
                            known = true;
                            break;
                        }
                    }
                    if (!known)
                        target.expandedDirectoryIds ~= directoryId;
                }
                restoreExpandedDirectories(target.directoryTreeView,
                    target.expandedDirectoryIds);
                selectPendingTreeFile(target);
            }

            if (!target.directorySourceRemote)
            {
                applyReveal(findDirectoryPathForFile(target.directorySource, "root", fileId));
                return;
            }

            auto sourcePath = target.filePath;
            new Thread({
                string[] path;
                try
                {
                    auto source = openRepositoryDirectorySource(sourcePath);
                    path = findDirectoryPathForFile(source, "root", fileId);
                    source.close();
                }
                catch (Exception)
                {
                    path = [];
                }
                new Idle({
                    if (target.filePath == sourcePath)
                        applyReveal(path);
                    return false;
                });
            }).start();
        };
        void delegate(TreePath, string, FileCursor, TreePath) loadRemoteDirectory;
        void delegate() loadExpandedTreePlaceholders;
        loadRemoteDirectory = (TreePath parentPath, string directoryId, FileCursor cursor,
            TreePath rowToRemovePath) {
            auto model = document.directoryTreeView.getModel();
            auto loadingIter = new TreeIter();
            if (!model.getIter(loadingIter, rowToRemovePath))
                return;
            auto markerKind = model.getValueString(loadingIter, 1);
            if (cursor.id.length == 0
                ? markerKind != "Placeholder" && markerKind != "Loading"
                : markerKind != "Page")
                return;
            auto loadingKind = cursor.id.length == 0 ? "Loading" : "LoadingPage";
            auto loadingStoreIter = treeStoreIter(document, loadingIter);
            document.directoryTreeStore.setValue(loadingStoreIter, 0, "Loading...");
            document.directoryTreeStore.setValue(loadingStoreIter, 1, loadingKind);
            auto filePath = document.filePath;
            auto fileFilter = treeFilterForDocument(document, prefCaseSensitiveFilter);
            auto treeSortOrder = document.treeSortOrder;
            auto fileSortOrder = sourceFileSortOrder(treeSortOrder);
            new Thread({
                AsyncDirectoryResult result;
                result.filePath = filePath;
                result.directoryId = directoryId;
                result.initial = cursor.id.length == 0;
                result.filter = fileFilter;
                result.sortOrder = treeSortOrder;
                try
                {
                    auto source = openRepositoryDirectorySource(filePath);
                    result.directories = source.listDirectories(directoryId, fileFilter);
                    auto page = source.listFilteredFilesPage(directoryId, cursor, 251,
                        fileFilter, fileSortOrder);
                    result.files = page.files;
                    source.close();
                }
                catch (Exception ex)
                {
                    result.error = ex.msg;
                }
                new Idle({
                    if (result.filePath != document.filePath || document.directorySource is null)
                        return false;
                    if (!sameTreeFilter(result.filter,
                            treeFilterForDocument(document, prefCaseSensitiveFilter))
                        || result.sortOrder != document.treeSortOrder)
                    {
                        if (loadExpandedTreePlaceholders !is null)
                            new Idle({ loadExpandedTreePlaceholders(); return false; });
                        return false;
                    }
                    TreeModelIF model = document.directoryTreeView.getModel();
                    auto parent = new TreeIter();
                    auto rowToRemove = new TreeIter();
                    if (result.initial)
                    {
                        if (!findLoadingDirectoryPlaceholder(model,
                                result.directoryId, parent, rowToRemove))
                        {
                            if (loadExpandedTreePlaceholders !is null)
                                new Idle({ loadExpandedTreePlaceholders(); return false; });
                            return false;
                        }
                    }
                    else if (!model.getIter(parent, parentPath)
                        || !model.getIter(rowToRemove, rowToRemovePath)
                        || model.getValueString(rowToRemove, 1) != "LoadingPage")
                        return false;
                    auto parentStore = treeStoreIter(document, parent);
                    auto removeStore = treeStoreIter(document, rowToRemove);
                    document.directoryTreeStore.remove(removeStore);
                    if (result.error.length > 0)
                    {
                        auto errorIter = document.directoryTreeStore.createIter(parentStore);
                        document.directoryTreeStore.setValue(errorIter, 0,
                            "Failed to load: " ~ result.error);
                        document.directoryTreeStore.setValue(errorIter, 1, "Error");
                        document.directoryTreeStore.setValue(errorIter, 2, "");
                        document.directoryTreeStore.setValue(errorIter, 3, result.directoryId);
                        document.directoryTreeStore.setValue(errorIter, TREE_COL_NODE_ID,
                            "Error:" ~ result.directoryId);
                        document.directoryTreeStore.setValue(errorIter,
                            TREE_COL_PROJECTION_INDEX,
                            document.directoryTreeStore.getValueString(parentStore,
                                TREE_COL_PROJECTION_INDEX));
                        setTreeNodeVisible(document.directoryTreeStore, errorIter, true);
                    }
                    else
                    {
                        populateDirectoryTreeRows(document.directoryTreeStore, parentStore,
                            result.directories, result.files, result.initial,
                            document.treeSortOrder);
                        restoreExpandedDirectories(document.directoryTreeView,
                            document.expandedDirectoryIds);
                        selectPendingTreeFile(document);
                        if (loadExpandedTreePlaceholders !is null)
                            new Idle({ loadExpandedTreePlaceholders(); return false; });
                    }
                    return false;
                });
            }).start();
        };
        loadExpandedTreePlaceholders = () {
            if (!document.directorySourceRemote)
                return;
            loadExpandedDirectoryPlaceholders(document.directoryTreeView,
                (TreePath directoryPath, string directoryId, TreePath placeholderPath) {
                    loadRemoteDirectory(directoryPath, directoryId, FileCursor(),
                        placeholderPath);
                });
        };
        document.reconcileDirectoryLoads = loadExpandedTreePlaceholders;
        document.directoryTreeView.addOnRowExpanded((TreeIter iter, TreePath _, TreeView treeView) {
            TreeModelIF model = document.directoryTreeView.getModel();
            TreeIter child;
            if (!model.iterChildren(child, iter))
                return;
            auto childKind = model.getValueString(child, 1);
            if (childKind != "Placeholder" && childKind != "Loading")
                return;

            auto directoryId = model.getValueString(iter, 3);
            bool alreadyExpanded;
            foreach (expandedId; document.expandedDirectoryIds)
            {
                if (expandedId == directoryId)
                {
                    alreadyExpanded = true;
                    break;
                }
            }
            if (!alreadyExpanded)
                document.expandedDirectoryIds ~= directoryId;
            if (document.directorySourceRemote)
            {
                loadRemoteDirectory(model.getPath(iter), directoryId, FileCursor(),
                    model.getPath(child));
                return;
            }
            auto parentStore = treeStoreIter(document, iter);
            auto childStore = treeStoreIter(document, child);
            document.directoryTreeStore.remove(childStore);
            populateDirectoryTreeNode(document.directoryTreeStore, document.directorySource,
                parentStore, directoryId, FileCursor(), true,
                treeFilterForDocument(document, prefCaseSensitiveFilter),
                document.treeSortOrder);
            restoreExpandedDirectories(document.directoryTreeView,
                document.expandedDirectoryIds);
            selectPendingTreeFile(document);
        });
        document.directoryTreeView.addOnRowCollapsed((TreeIter iter, TreePath _, TreeView treeView) {
            auto model = document.directoryTreeView.getModel();
            auto directoryId = model.getValueString(iter, 3);
            foreach (index, expandedId; document.expandedDirectoryIds)
            {
                if (expandedId == directoryId)
                {
                    document.expandedDirectoryIds = document.expandedDirectoryIds[0 .. index]
                        ~ document.expandedDirectoryIds[index + 1 .. $];
                    break;
                }
            }
        });
        document.directoryTreeView.addOnRowActivated((TreePath path, TreeViewColumn _, TreeView treeView) {
            TreeModelIF model = document.directoryTreeView.getModel();
            auto pageIter = new TreeIter();
            if (!model.getIter(pageIter, path))
                return;
            auto kind = model.getValueString(pageIter, 1);
            if (kind == "File")
            {
                openKnownFileExternally(document, model.getValueString(pageIter, 5));
                return;
            }
            if (kind == "Directory")
            {
                toggleDirectoryExpansion(treeView, path);
                return;
            }
            if (kind != "Page")
                return;
            TreeIter parentIter;
            if (!model.iterParent(parentIter, pageIter))
                return;
            auto directoryId = model.getValueString(pageIter, 3);
            FileCursor cursor;
            cursor.relativePath = model.getValueString(pageIter, 4);
            cursor.id = model.getValueString(pageIter, 5);
            auto cursorSize = model.getValueString(pageIter, 6);
            if (cursorSize.length > 0)
                cursor.size = to!ulong(cursorSize);
            if (document.directorySourceRemote)
                loadRemoteDirectory(model.getPath(parentIter), directoryId, cursor, path);
            else
            {
                auto parentStore = treeStoreIter(document, parentIter);
                auto pageStore = treeStoreIter(document, pageIter);
                document.directoryTreeStore.remove(pageStore);
                populateDirectoryTreeNode(document.directoryTreeStore,
                    document.directorySource, parentStore, directoryId, cursor, false,
                    treeFilterForDocument(document, prefCaseSensitiveFilter), document.treeSortOrder);
            }
        });
        void selectTableRowFromTree(TreeIter tableIter, string fileName, string filePath)
        {
            document.syncingTreeSelection = true;
            scope (exit)
                document.syncingTreeSelection = false;
            document.tableView.getSelection().selectIter(tableIter);
            updateSelectedRowDetails(document);
            if (fileName.length > 0)
                document.selectedFileName = fileName;
            if (filePath.length > 0)
                document.selectedFilePath = filePath;
        }
        document.directoryTreeView.getSelection().addOnChanged((TreeSelection _) {
            TreeModelIF model;
            TreeIter treeIter;
            if (!document.directoryTreeView.getSelection().getSelected(model, treeIter))
                return;
            if (model.getValueString(treeIter, 1) != "File")
                return;
            if (document.syncingTreeSelection)
                return;

            auto selectedId = model.getValueString(treeIter, 3);
            document.selectedTreeFileId = selectedId;
            document.treePreviousFileButton.setSensitive(true);
            document.treeNextFileButton.setSensitive(true);
            TreeIter parentIter;
            if (model.iterParent(parentIter, treeIter))
            {
                document.selectedTreeDirectoryId = model.getValueString(parentIter, 3);
                document.selectedTreeCursor.relativePath = model.getValueString(treeIter, 5);
                document.selectedTreeCursor.id = model.getValueString(treeIter, 6);
                auto fileSizeText = model.getValueString(treeIter, 7);
                document.selectedTreeCursor.size = fileSizeText.length > 0
                    ? to!ulong(fileSizeText) : 0;
            }
            auto selectedTreeFileName = model.getValueString(treeIter, 0);
            auto selectedTreeRelativePath = model.getValueString(treeIter, 5);
            auto selectedSourcePath = resolveKnownFilePath(document,
                selectedTreeRelativePath);
            bool rowReferencesSelectedPath(const(BlobRow) candidate)
            {
                if (candidate.sourceBlob is null)
                    return resolveKnownFilePath(document, candidate.primaryFileName)
                        == selectedSourcePath;
                foreach (spec; candidate.sourceBlob.fileSpecs)
                {
                    if (spec !is null && spec.fileName.length > 0
                        && resolveKnownFilePath(document, spec.fileName) == selectedSourcePath)
                        return true;
                }
                return candidate.sourceBlob.fileSpecs.length == 0
                    && resolveKnownFilePath(document, candidate.primaryFileName)
                        == selectedSourcePath;
            }
            auto hasFileType = model.getValueString(treeIter, 8) == "1";
            auto hasMedia = model.getValueString(treeIter, 9) == "1";
            auto hasVideo = model.getValueString(treeIter, 10) == "1";
            auto hasAudio = model.getValueString(treeIter, 11) == "1";
            auto hasImage = model.getValueString(treeIter, 12) == "1";
            auto hasText = model.getValueString(treeIter, 13) == "1";
            auto hasArchive = model.getValueString(treeIter, 14) == "1";
            auto hasTorrent = model.getValueString(treeIter, 15) == "1";
            foreach (rowIndex, row; document.visibleRows)
            {
                bool rowSelected;
                if (row.sourceId >= 0)
                    rowSelected = row.sourceId.to!string == selectedId;
                else
                    rowSelected = rowReferencesSelectedPath(row);
                if (!rowSelected)
                    continue;
                auto tableModel = document.tableView.getModel();
                TreeIter tableIter;
                if (tableModel is null || !tableModel.getIterFirst(tableIter))
                    return;
                bool foundTableRow;
                do
                {
                    if (tableIndexMatchesVisibleRow(
                        tableModel.getValueString(tableIter, COL_INDEX), rowIndex))
                    {
                        foundTableRow = true;
                        break;
                    }
                }
                while (tableModel.iterNext(tableIter));
                if (!foundTableRow)
                    return;
                selectTableRowFromTree(tableIter, selectedTreeFileName,
                    selectedTreeRelativePath);
                return;
            }
            if (!document.directorySourceRemote)
            {
                foreach (rowIndex, row; document.loadedRows)
                {
                    if (!rowReferencesSelectedPath(row))
                        continue;
                    document.directSelectedRow = row;
                    document.hasDirectSelectedRow = true;
                    document.directSelectedIndex = rowIndex.to!string;
                    document.syncingTreeSelection = true;
                    scope (exit)
                        document.syncingTreeSelection = false;
                    document.tableView.getSelection().unselectAll();
                    updateSelectedRowDetails(document);
                    document.selectedFileName = selectedTreeFileName;
                    document.selectedFilePath = selectedTreeRelativePath;
                    return;
                }
            }
            if (document.directorySourceRemote)
            {
                TreeIter tableIter;
                auto tableModel = document.tableView.getModel();
                if (tableModel !is null && tableModel.getIterFirst(tableIter))
                {
                    do
                    {
                        if (tableModel.getValueString(tableIter, COL_SOURCE_ID) == selectedId)
                        {
                            selectTableRowFromTree(tableIter, selectedTreeFileName,
                                selectedTreeRelativePath);
                            return;
                        }
                    }
                    while (tableModel.iterNext(tableIter));
                }
            }
            if (document.directorySourceRemote && selectedId.length > 0)
            {
                long sourceId;
                try
                    sourceId = to!long(selectedId);
                catch (Exception)
                    return;
                auto requestId = ++document.detailRequestId;
                auto sourcePath = document.filePath;
                document.status.setText("Loading tree selection details ...");
                new Thread({
                    NamedBinaryBlob details;
                    string error;
                    try
                        details = loadDocumentDetails(sourcePath, sourceId);
                    catch (Exception ex)
                        error = ex.msg;
                    new Idle({
                        if (requestId != document.detailRequestId)
                            return false;
                        if (error.length > 0)
                        {
                            document.status.setText("Failed to load tree selection: " ~ error);
                            return false;
                        }
                        auto rows = extractRowsFromBlobs([details]);
                        if (rows.length == 0)
                            return false;
                        auto row = rows[0];
                        row.sourceId = sourceId;
                        row.detailsLoaded = true;
                        row.hasSummaryFlags = true;
                        row.summaryHasFileType = hasFileType;
                        row.summaryHasMedia = hasMedia;
                        row.summaryHasVideo = hasVideo;
                        row.summaryHasAudio = hasAudio;
                        row.summaryHasImage = hasImage;
                        row.summaryHasText = hasText;
                        row.summaryHasArchive = hasArchive;
                        row.summaryHasTorrent = hasTorrent;
                        document.tableView.getSelection().unselectAll();
                        document.directSelectedRow = row;
                        document.hasDirectSelectedRow = true;
                        document.directSelectedIndex = "Tree";
                        updateSelectedRowDetails(document);
                        return false;
                    });
                }).start();
            }
        });
        document.tableView.addOnSizeAllocate((allocation, Widget _) {
            if (!document.pendingColumnMeasurement)
            {
                return;
            }

            document.pendingColumnMeasurement = false;
            new Idle({
                finalizeTableColumnMeasurement(
                document,
                (DocumentTab measuredDocument) {
                    schedulePreferredHorizontalSplit(measuredDocument);
                },
                (DocumentTab measuredDocument) {
                    applyDetailsPanePreference(measuredDocument, false);
                }
                );
                return false;
            });
        });

        auto scroll = new ScrolledWindow(null, null);
        scroll.setVexpand(true);
        scroll.setHexpand(true);
        scroll.add(document.tableView);
        auto directoryScroll = new ScrolledWindow(null, null);
        directoryScroll.setHexpand(true);
        directoryScroll.setVexpand(false);
        directoryScroll.setSizeRequest(-1, 220);
        directoryScroll.add(document.directoryTreeView);
        auto resultViews = new Notebook();
        resultViews.appendPage(directoryScroll, new Label("Directory tree"));
        resultViews.appendPage(scroll, new Label("Blob table"));
        document.resultViews = resultViews;
        resultViews.setCurrentPage(document.resultViewPage);
        resultViews.addOnSwitchPage((Widget _, uint pageNumber, Notebook __) {
            document.resultViewPage = cast(int) pageNumber;
            if (currentDocument() is document)
                persistCurrentState(clearSavedWindowGeometryOnExit);
        });
        auto previewUi = loadDetailPreviewUi(document);
        auto detailUi = loadDetailPaneUi(document);
        auto pageUi = loadDocumentPageUi(document);
        document.treeSortCombo.setActive(cast(int) document.treeSortOrder);
        auto hasRestoredTreeCursor = document.selectedTreeCursor.id.length > 0;
        document.treePreviousFileButton.setSensitive(hasRestoredTreeCursor);
        document.treeNextFileButton.setSensitive(hasRestoredTreeCursor);
        void navigateTreeFile(bool forward)
        {
            if (document.selectedTreeDirectoryId.length == 0
                || document.selectedTreeCursor.id.length == 0)
                return;
            auto sourcePath = document.filePath;
            auto directoryId = document.selectedTreeDirectoryId;
            auto cursor = document.selectedTreeCursor;
            auto filter = treeFilterForDocument(document, prefCaseSensitiveFilter);
            auto order = sourceFileSortOrder(document.treeSortOrder);
            document.treePreviousFileButton.setSensitive(false);
            document.treeNextFileButton.setSensitive(false);
            new Thread({
                FilePage page;
                string error;
                try
                {
                    DirectorySource source = document.directorySourceRemote
                        ? openRepositoryDirectorySource(sourcePath) : document.directorySource;
                    page = forward
                        ? source.listFilteredFilesPage(directoryId, cursor, 1, filter, order)
                        : source.listPreviousFilteredFilesPage(directoryId, cursor, 1, filter, order);
                    if (document.directorySourceRemote)
                        source.close();
                }
                catch (Exception ex)
                    error = ex.msg;
                new Idle({
                    if (document.filePath != sourcePath)
                        return false;
                    if (error.length > 0)
                    {
                        document.status.setText("Failed to navigate files: " ~ error);
                    }
                    else if (page.files.length > 0)
                    {
                        auto target = page.files[0];
                        auto model = document.directoryTreeView.getModel();
                        TreeIter targetIter;
                        TreeIter rootSearch;
                        if (!findTreeIterByValue(model, rootSearch, false, 6,
                            target.cursorId, targetIter))
                        {
                            TreeIter root;
                            TreeIter parent;
                            if (findDirectoryTreeIter(model, root, false, directoryId, parent))
                            {
                                auto parentStore = treeStoreIter(document, parent);
                                auto targetStore = document.directoryTreeStore.createIter(
                                    parentStore);
                                document.directoryTreeStore.setValue(targetStore, 0, target.name);
                                document.directoryTreeStore.setValue(targetStore, 1, "File");
                                document.directoryTreeStore.setValue(targetStore, 2,
                                    format("%s bytes", target.size));
                                document.directoryTreeStore.setValue(targetStore, 3, target.id);
                                document.directoryTreeStore.setValue(targetStore, 5, target.relativePath);
                                document.directoryTreeStore.setValue(targetStore, 6, target.cursorId);
                                document.directoryTreeStore.setValue(targetStore, 7, target.size.to!string);
                                document.directoryTreeStore.setValue(targetStore, 8, target.hasFileType ? "1" : "0");
                                document.directoryTreeStore.setValue(targetStore, 9, target.hasMedia ? "1" : "0");
                                document.directoryTreeStore.setValue(targetStore, 10, target.hasVideo ? "1" : "0");
                                document.directoryTreeStore.setValue(targetStore, 11, target.hasAudio ? "1" : "0");
                                document.directoryTreeStore.setValue(targetStore, 12, target.hasImage ? "1" : "0");
                                document.directoryTreeStore.setValue(targetStore, 13, target.hasText ? "1" : "0");
                                document.directoryTreeStore.setValue(targetStore, 14, target.hasArchive ? "1" : "0");
                                document.directoryTreeStore.setValue(targetStore, 15, target.hasTorrent ? "1" : "0");
                                document.directoryTreeStore.setValue(targetStore,
                                    TREE_COL_NODE_ID, target.cursorId.length > 0
                                        ? target.cursorId : target.id);
                                document.directoryTreeStore.setValue(targetStore,
                                    TREE_COL_PROJECTION_INDEX,
                                    target.sourceIndex.to!string);
                                document.directoryTreeStore.setValue(targetStore,
                                    TREE_COL_SORT_SIZE, format("%020d", target.size));
                                setTreeNodeVisible(document.directoryTreeStore,
                                    targetStore, true);
                                reorderTreeChildren(document.directoryTreeStore,
                                    parentStore, document.treeSortOrder);
                                targetIter = treeViewIter(document, targetStore);
                            }
                        }
                        if (targetIter !is null)
                            document.directoryTreeView.getSelection().selectIter(targetIter);
                    }
                    document.treePreviousFileButton.setSensitive(true);
                    document.treeNextFileButton.setSensitive(true);
                    return false;
                });
            }).start();
        }
        document.treePreviousFileButton.addOnClicked((Button _) { navigateTreeFile(false); });
        document.treeNextFileButton.addOnClicked((Button _) { navigateTreeFile(true); });
        bindFilterSignals(document.filterEntry, document.filterVideoWidget,
            document.filterAudioWidget, document.filterImageWidget,
            document.filterTextWidget, document.filterMediaNotWidget,
            document.filterFileTypeWidget, document.filterArchiveWidget,
            document.filterTorrentWidget, () {
                if (isSyncingToolbarState)
                    return;
                captureDocumentFilterState(document);
                if (applyFilterForDocument !is null)
                    applyFilterForDocument(document);
            });
        document.btnApplyFilter.addOnClicked((Button _) {
            if (isSyncingToolbarState)
                return;
            captureDocumentFilterState(document);
            if (applyFilterForDocument !is null)
                applyFilterForDocument(document);
        });
        document.btnClearFilter.addOnClicked((Button _) {
            if (clearFilterForDocument !is null)
                clearFilterForDocument(document);
        });
        auto previewPane = previewUi.previewPane;
        auto detailsPane = detailUi.detailsPane;
        auto detailsContent = detailUi.detailsContent;
        auto previewSlot = detailUi.previewSlot;
        auto pageRoot = pageUi.pageRoot;
        auto splitSlot = pageUi.splitSlot;

        void delegate(TreeView, TreeStore, bool, TreePath, TreePath, string, size_t,
            string, string, string)
            loadNestedEntryPage;
        loadNestedEntryPage = (TreeView treeView, TreeStore store, bool archive,
            TreePath parentPath, TreePath removePath, string blobId, size_t offset,
            string selectionToken, string markerToken, string loadingKind) {
            auto stableParentPath = parentPath.copy();
            auto stableRemovePath = removePath.copy();
            auto sourcePath = document.filePath;
            new Thread({
                AsyncNestedEntryResult result;
                result.filePath = sourcePath;
                result.blobId = blobId;
                result.archive = archive;
                result.offset = offset;
                try
                {
                    result.entries = archive
                        ? loadRepositoryArchiveEntries(sourcePath, to!long(blobId), offset, 251)
                        : loadRepositoryTorrentFiles(sourcePath, to!long(blobId), offset, 251);
                    auto page = prepareNestedEntryPage(result.entries, offset);
                    result.entries = page.entries;
                    result.hasMore = page.hasMore;
                    result.nextOffset = page.nextOffset;
                }
                catch (Exception ex)
                    result.error = ex.msg;
                new Idle({
                    if (result.filePath != document.filePath)
                        return false;
                    auto model = treeView.getModel();
                    auto parent = new TreeIter();
                    auto remove = new TreeIter();
                    if (!model.getIter(parent, stableParentPath)
                        || !model.getIter(remove, stableRemovePath))
                        return false;
                    if (!nestedEntryReplyMatches(model, stableParentPath,
                            stableRemovePath, archive, result.blobId, result.offset,
                            selectionToken, loadingKind, markerToken))
                    {
                        return false;
                    }
                    store.remove(remove);
                    if (result.error.length > 0)
                    {
                        auto error = store.createIter(parent);
                        store.setValue(error, 0, "Failed to load: " ~ result.error);
                        store.setValue(error, 3, "Error");
                        return false;
                    }
                    foreach (entry; result.entries)
                        appendNestedEntry(store, model, parent, entry, blobId);
                    if (result.hasMore)
                        appendNestedPageMarker(store, parent, blobId, archive,
                            result.nextOffset,
                            (++document.nestedEntryRequestId).to!string);
                    return false;
                });
            }).start();
        };

        void bindNestedEntryTree(TreeView treeView, TreeStore store, bool archive)
        {
            treeView.addOnRowExpanded((TreeIter iter, TreePath path, TreeView _) {
                auto model = treeView.getModel();
                auto kind = model.getValueString(iter, 3);
                if (kind != (archive ? "ArchiveRoot" : "TorrentRoot"))
                    return;
                TreeIter child;
                if (!model.iterChildren(child, iter) || model.getValueString(child, 3) != "Loading")
                    return;
                auto selectionToken = model.getValueString(iter, 6);
                auto markerToken = (++document.nestedEntryRequestId).to!string;
                auto loadingKind = archive ? "ArchiveLoading" : "TorrentLoading";
                store.setValue(child, 3, loadingKind);
                store.setValue(child, 4, model.getValueString(iter, 4));
                store.setValue(child, 5, "0");
                store.setValue(child, 6, markerToken);
                loadNestedEntryPage(treeView, store, archive, path, model.getPath(child),
                    model.getValueString(iter, 4), 0, selectionToken, markerToken,
                    loadingKind);
            });
            bindNestedPageActivation(treeView, (TreePath parentPath,
                    TreePath pagePath, NestedPageActivation request) {
                auto markerToken = (++document.nestedEntryRequestId).to!string;
                auto loadingKind = request.archive
                    ? "ArchiveLoadingPage" : "TorrentLoadingPage";
                auto page = new TreeIter();
                if (!treeView.getModel().getIter(page, pagePath))
                    return;
                store.setValue(page, 3, loadingKind);
                store.setValue(page, 6, markerToken);
                loadNestedEntryPage(treeView, store, request.archive, parentPath,
                    pagePath, request.blobId, request.offset, request.selectionToken,
                    markerToken, loadingKind);
            });
        }
        bindNestedEntryTree(document.detailArchiveTreeView, document.detailArchiveTreeStore, true);
        bindNestedEntryTree(document.detailTorrentTreeView, document.detailTorrentTreeStore, false);

        document.pageFirstButton.addOnClicked((Button _) {
            if (document.pageOffset == 0)
                return;
            document.pageOffset = 0;
            loadDocument(document, false);
        });
        document.pagePreviousButton.addOnClicked((Button _) {
            if (document.pageOffset < document.pageSize)
                return;
            document.pageOffset -= document.pageSize;
            loadDocument(document, false);
        });
        document.pageNextButton.addOnClicked((Button _) {
            if (document.pageOffset + document.pageSize >= document.pageTotal)
                return;
            document.pageOffset += document.pageSize;
            loadDocument(document, false);
        });
        document.pageLastButton.addOnClicked((Button _) {
            if (document.pageTotal == 0 || document.pageOffset + document.pageSize >= document.pageTotal)
                return;
            document.pageOffset = ((document.pageTotal - 1) / document.pageSize) * document.pageSize;
            loadDocument(document, false);
        });
        document.pageSizeCombo.addOnChanged((ComboBoxText combo) {
            auto value = combo.getActiveText();
            if (value == "All rows")
            {
                document.loadAllRows = true;
            }
            else
            {
                document.loadAllRows = false;
                document.pageSize = to!size_t(value);
            }
            document.pageOffset = 0;
            loadDocument(document, false);
        });
        document.treeSortCombo.addOnChanged((ComboBoxText combo) {
            auto active = combo.getActive();
            if (active < 0 || active > cast(int) TreeSortOrder.sizeDescending)
                return;
            document.treeSortOrder = cast(TreeSortOrder) active;
            if (document.directorySource !is null)
            {
                document.reuseDirectoryTreeNodes = false;
                renderDirectoryTree(document, document.directorySource,
                    document.expandedDirectoryIds,
                    treeFilterForDocument(document, prefCaseSensitiveFilter), document.treeSortOrder);
                selectPendingTreeFile(document);
                if (document.reconcileDirectoryLoads !is null)
                    new Idle({ document.reconcileDirectoryLoads(); return false; });
            }
        });

        syncPreviewToolbarFromDocument(document);
        bindDetailPreviewSignals(document, DetailPreviewCallbacks(
            () => isSyncingToolbarState,
            (PreviewScaleMode mode) { setPreviewScaleMode(mode); },
            () { syncPreviewToolbarFromCurrentDocument(); },
            (bool value) { previewVideoAutostart = value; },
            (double value) { previewVideoVolume = value; }
        ));

        bindDetailPaneSignals(document, DetailPaneCallbacks(
            (DocumentTab doc, string fileName) { openKnownFileExternally(doc, fileName); },
            (string title, string text, DocumentTab doc) { copyTextToClipboard(title, text, doc); },
            (DocumentTab doc) { updateSelectedRowDetails(doc); }
        ));

        logLineVerbose("[ui] populating preview slot for ", filePath);
        previewSlot.packStart(previewPane, true, true, 0);
        document.detailPreviewSplit = detailsContent;
        detailsContent.addOnNotify((ParamSpec _, ObjectG __) {
            auto currentPosition = document.detailPreviewSplit.getPosition();
            splitPositionPreview = currentPosition;
        }, "position");
        detailsContent.addOnSizeAllocate((allocation, Widget _) {
            if (splitPositionPreview > 0 || allocation.width <= 0)
            {
                return;
            }

            auto initialPosition = cast(int) (allocation.width * 0.25);
            if (initialPosition < 1)
            {
                initialPosition = 1;
            }
            document.detailPreviewSplit.setPosition(initialPosition);
            splitPositionPreview = initialPosition;
        });

        document.split = new Paned(Orientation.HORIZONTAL);
        document.split.pack1(resultViews, false, true);
        document.split.pack2(detailsPane, true, false);
        document.split.setPosition(splitPositionHorizontal);
        document.split.addOnNotify((ParamSpec _, ObjectG __) {
            auto currentOrientation = document.split.getOrientation();
            auto extent = currentOrientation == Orientation.VERTICAL
                ? document.split.getAllocatedHeight() : document.split.getAllocatedWidth();
            if (extent <= 0)
                return;

            auto currentPosition = document.split.getPosition();
            auto clampedPosition = clampSplitPositionToVisibleBounds(document, document.split,
                currentOrientation, currentPosition);
            if (clampedPosition != currentPosition)
            {
                logLineVerbose("[layout] notify::position clamp for ", document.filePath,
                    ": current=", currentPosition,
                    ", clamped=", clampedPosition,
                    ", stored=", currentOrientation == Orientation.VERTICAL
                        ? splitPositionVertical : splitPositionHorizontal,
                    ", natural=", document.tableNaturalWidth,
                    ", minimum=", document.tableMinimumWidth);
                document.split.setPosition(clampedPosition);
            }
            if (currentDocument() is document)
            {
                if (currentOrientation == Orientation.VERTICAL)
                    splitPositionVertical = clampedPosition;
                else
                    splitPositionHorizontal = clampedPosition;
            }
        }, "position");
        document.split.addOnSizeAllocate((allocation, Widget _) {
            if (document.split.getOrientation() != Orientation.VERTICAL
                || document.split.getAllocatedHeight() <= 0)
                return;
            auto currentPosition = document.split.getPosition();
            auto clampedPosition = clampSplitPositionToVisibleBounds(document,
                document.split, Orientation.VERTICAL, currentPosition);
            if (clampedPosition != currentPosition)
                document.split.setPosition(clampedPosition);
            if (currentDocument() is document)
                splitPositionVertical = clampedPosition;
        });

        document.rowDetails.setText("Selection: none");
        document.status.setText(format("Ready: %s", filePath));

        splitSlot.packStart(document.split, true, true, 0);
        document.pageRoot = pageRoot;
        document.pageRoot.showAll();
        // Repository pages are internal cursor chunks; do not expose the legacy
        // row-count/page-size controls after showAll() re-enables their widgets.
        document.pageFirstButton.hide();
        document.pagePreviousButton.hide();
        document.pageNextButton.hide();
        document.pageLastButton.hide();
        document.pageSizeCombo.hide();
        document.pageStatus.hide();

        clearSelectionDetails(document);
        applyDetailsPanePreference(document, false);
        return document;
    }

    /** Snapshot the current preferences, splitter state, window size, and open tabs. */
    AppState currentAppState(bool clearWindowGeometry = false)
    {
        AppState state;
        state.prefAutoApplyFilter = prefAutoApplyFilter;
        state.prefCaseSensitiveFilter = prefCaseSensitiveFilter;
        state.prefDetailsBelow = prefDetailsBelow;
        state.prefRestoreOpenFiles = prefRestoreOpenFiles;
        state.externalOpenProgram = externalOpenProgram;
        state.previewScaleMode = cast(int) previewScaleMode;
        state.previewVideoAutostart = previewVideoAutostart;
        state.recentFilePaths = recentFilePaths;
        state.maxRecentFileCount = recentFileLimit;
        state.splitPositionPreview = splitPositionPreview;
        state.hasSplitPositionPreview = splitPositionPreview > 0;

        auto document = currentDocument();
        state.previewVideoVolume = document is null
            ? previewVideoVolume
            : document.detailPreviewVolumeScale is null
                ? document.previewVideoVolume
                : document.detailPreviewVolumeScale.getValue();
        if (document !is null)
        {
            auto currentOrientation = document.split.getOrientation();
            auto currentSplitPosition = document.split.getPosition();
            auto splitExtent = currentOrientation == Orientation.VERTICAL
                ? document.split.getAllocatedHeight() : document.split.getAllocatedWidth();
            if (splitExtent > 0 && currentOrientation == Orientation.VERTICAL)
            {
                splitPositionVertical = currentSplitPosition;
            }
            else if (splitExtent > 0)
            {
                splitPositionHorizontal = currentSplitPosition;
            }

            if (document.detailPreviewSplit !is null)
            {
                splitPositionPreview = document.detailPreviewSplit.getPosition();
                state.splitPositionPreview = splitPositionPreview;
                state.hasSplitPositionPreview = true;
            }

            previewScaleMode = document.previewScaleMode;
        }

        state.splitPositionHorizontal = splitPositionHorizontal;
        state.splitPositionVertical = splitPositionVertical;
        state.splitPositionPreview = splitPositionPreview;
        state.previewScaleMode = cast(int) previewScaleMode;

        int width = lastKnownWindowWidth;
        int height = lastKnownWindowHeight;
        auto allocatedWidth = window.getAllocatedWidth();
        auto allocatedHeight = window.getAllocatedHeight();
        if (allocatedWidth >= MIN_VALID_WINDOW_WIDTH && allocatedHeight >= MIN_VALID_WINDOW_HEIGHT)
        {
            width = allocatedWidth;
            height = allocatedHeight;
        }
        if (width < MIN_VALID_WINDOW_WIDTH)
        {
            width = 960;
        }
        if (height < MIN_VALID_WINDOW_HEIGHT)
        {
            height = 640;
        }

        lastKnownWindowWidth = width;
        lastKnownWindowHeight = height;
        state.hasWindowSize = true;
        state.windowWidth = width;
        state.windowHeight = height;
        foreach (openDocument; documents)
        {
            state.openFilePaths ~= openDocument.filePath;
            foreach (directoryId; openDocument.expandedDirectoryIds)
                state.expandedTreeStates ~= openDocument.filePath ~ "\t" ~ directoryId;
            if (openDocument.selectedTreeFileId.length > 0)
                state.selectedTreeStates ~= openDocument.filePath ~ "\t"
                    ~ openDocument.selectedTreeFileId;
            state.treeSortStates ~= openDocument.filePath ~ "\t"
                ~ (cast(int) openDocument.treeSortOrder).to!string;
            state.viewModeStates ~= openDocument.filePath ~ "\t"
                ~ openDocument.resultViewPage.to!string;
            state.tableSortStates ~= TableSortState(openDocument.filePath,
                openDocument.tableSortEnabled, openDocument.tableSortColumnId,
                openDocument.tableSortOrder);
            state.documentFilterStates ~= DocumentFilterState(openDocument.filePath,
                openDocument.filterApplied, openDocument.filterQuery,
                openDocument.filterVideo,
                openDocument.filterAudio, openDocument.filterImage,
                openDocument.filterText, openDocument.filterMediaNegated,
                openDocument.filterFileType, openDocument.filterArchive,
                openDocument.filterTorrent);
            if (openDocument.selectedTreeCursor.id.length > 0)
            {
                state.treeCursorStates ~= TreeCursorState(openDocument.filePath,
                    openDocument.selectedTreeDirectoryId,
                    openDocument.selectedTreeCursor.relativePath,
                    openDocument.selectedTreeCursor.id,
                    openDocument.selectedTreeCursor.size);
            }
        }
        state.activeTabIndex = notebook.getCurrentPage();

        if (clearWindowGeometry)
        {
            state.hasWindowGeometry = false;
            state.windowX = 0;
            state.windowY = 0;
            state.windowMonitorIndex = -1;
            return state;
        }

        state.hasWindowGeometry = false;
        state.windowX = 0;
        state.windowY = 0;
        state.windowMonitorIndex = -1;
        return state;
    }

    /** Persist the current application state and surface write failures in the active tab. */
    persistCurrentState = (bool clearWindowGeometry) {
        try
        {
            saveAppState(currentAppState(clearWindowGeometry));
        }
        catch (Exception ex)
        {
            auto document = currentDocument();
            if (document !is null)
            {
                document.status.setText(format("Failed to persist app state: %s", ex.msg));
            }
        }
    };

    /** Keep the in-memory recent-files list within the configured size limit. */
    void enforceRecentFileLimit()
    {
        if (recentFileLimit <= 0)
        {
            recentFilePaths.length = 0;
            return;
        }

        if (recentFilePaths.length > recentFileLimit)
        {
            recentFilePaths = recentFilePaths[0 .. recentFileLimit];
        }
    }

    /** Rebuild the recent-files submenu from the current in-memory list. */
    void refreshRecentFilesMenu()
    {
        auto menu = new Menu();
        if (recentFilePaths.length == 0)
        {
            auto emptyItem = new MenuItem("No recently used files", false);
            emptyItem.setSensitive(false);
            menu.append(emptyItem);
        }
        else
        {
            foreach (idx, path; recentFilePaths)
            {
                auto recentPath = path;
                auto label = format("%s. %s", idx + 1, recentPath);
                menu.append(new MenuItem((MenuItem _) {
                    auto document = openDocumentFromPath(recentPath, true, true);
                    if (document !is null && !document.sourceLoaded)
                    {
                        loadDocument(document, true);
                    }
                }, label, false));
            }
        }

        recentFilesMenuItem.setSubmenu(menu);
        recentFilesMenuItem.setSensitive(!isLoading && recentFilePaths.length > 0);
    }

    /** Move one file path to the top of the recent-files list and persist it. */
    void noteRecentFile(string filePath)
    {
        auto normalizedPath = normalizeDocumentPath(filePath);
        if (normalizedPath.length == 0)
        {
            return;
        }

        foreach (idx, existingPath; recentFilePaths)
        {
            if (existingPath == normalizedPath)
            {
                recentFilePaths = recentFilePaths[0 .. idx] ~ recentFilePaths[idx + 1 .. $];
                break;
            }
        }

        recentFilePaths = [normalizedPath] ~ recentFilePaths;
        enforceRecentFileLimit();
        refreshRecentFilesMenu();
        persistCurrentState(clearSavedWindowGeometryOnExit);
    }

    /** Clear the recent-files list, rebuild the menu, and save the change. */
    void clearRecentFiles()
    {
        recentFilePaths.length = 0;
        refreshRecentFilesMenu();
        persistCurrentState(clearSavedWindowGeometryOnExit);
    }

    /** Re-render one document's row set into its list model in GTK-friendly batches. */
    void renderRows(DocumentTab document, BlobRow[] rows, string filterLabel = "",
        bool appendRows = false, ulong completedFilterRequestId = 0)
    {
        if (!appendRows)
            setBlobTableVirtualMode(document.tableView, false);
        if (document.filePath.length == 0)
        {
            document.tableStore.clear();
            document.visibleRows = [];
            clearSelectionDetails(document);
            document.loadedDataVersion = -1;
            document.loadedRootShape = "-";
            document.loadedRootKeysSummary = "-";
            document.status.setText("Ready.");
            return;
        }

        // Keep the input slice alive across idle render batches instead of
        // copying hundreds of thousands of BlobRows synchronously on GTK.
        BlobRow[] rowsCopyData = rows;
        MonoTime renderStarted = MonoTime.currTime;
        auto localRenderRequestId = ++document.renderRequestId;
        enum size_t RENDER_BATCH_SIZE = 500;

        logLineVerbose("[render] start ", document.filePath,
            ": rows=", rowsCopyData.length,
            ", filter=", filterLabel.length > 0 ? filterLabel : "<none>");

        auto startingRowCount = appendRows
            ? (isRepositorySource(document.filePath) && document.drainRepositoryPages
                ? document.pageOffset : document.visibleRows.length)
            : 0;

        // Performance hack: un-couple TreeView for bulk-imports
        TreeModelIF oldModel = document.tableView.getModel();
        document.tableView.setModel(null);

        if (!appendRows)
        {
            document.tableStore.clear();
            document.visibleRows = [];
            clearSelectionDetails(document);
            startingRowCount = 0;
        }

        size_t nextIndex = 0;
        auto indexSortValue = new Value();
        indexSortValue.init(GType.UINT64);
        auto fileSizeSortValue = new Value();
        fileSizeSortValue.init(GType.UINT64);
        bool delegate() renderStep;
        renderStep = {
            if (localRenderRequestId != document.renderRequestId)
            {
                logLineVerbose("[render] aborted ", document.filePath);
                return false;
            }

            auto endIndex = nextIndex + RENDER_BATCH_SIZE;
            if (endIndex > rowsCopyData.length)
            {
                endIndex = rowsCopyData.length;
            }

            foreach (idx; nextIndex .. endIndex)
            {
                auto row = rowsCopyData[idx];
                auto globalIndex = startingRowCount + idx;
                auto indexText = to!string(globalIndex + 1);
                auto sizeText = to!string(row.fileSize);
                auto checksumsText = checksumSetStatus(row);
                auto fileTypeText = boolStatusIcon(row.hasFileType);
                auto mediaInfoText = mediaInfoSummary(row);
                auto archiveText = boolStatusIcon(row.hasArchive);
                auto torrentText = boolStatusIcon(row.hasTorrent);

                TreeIter iter;
                document.tableStore.append(iter);
                document.tableStore.set(
                    iter,
                    [
                    COL_INDEX, COL_FILE_SIZE, COL_CHECKSUM_SET, COL_FILE_TYPE,
                    COL_MEDIA_INFO, COL_HAS_ARCHIVE, COL_HAS_TORRENT, COL_SOURCE_ID,
                    COL_HAS_FILE_TYPE_FLAG, COL_HAS_MEDIA_FLAG, COL_HAS_VIDEO_FLAG,
                    COL_HAS_AUDIO_FLAG, COL_HAS_IMAGE_FLAG, COL_HAS_TEXT_FLAG,
                    COL_HAS_ARCHIVE_FLAG, COL_HAS_TORRENT_FLAG
                ],
                    [
                    indexText, sizeText, checksumsText, fileTypeText,
                    mediaInfoText, archiveText, torrentText,
                    row.sourceId >= 0 ? row.sourceId.to!string : "",
                    row.hasFileType ? "1" : "0", row.hasMedia ? "1" : "0",
                    row.hasVideo ? "1" : "0", row.hasAudio ? "1" : "0",
                    row.hasImage ? "1" : "0", row.hasText ? "1" : "0",
                    row.hasArchive ? "1" : "0", row.hasTorrent ? "1" : "0"
                ]
                );
                indexSortValue.setUint64(cast(ulong) globalIndex + 1);
                document.tableStore.setValue(iter, COL_INDEX_SORT, indexSortValue);
                fileSizeSortValue.setUint64(row.fileSize);
                document.tableStore.setValue(iter, COL_FILE_SIZE_SORT,
                    fileSizeSortValue);
            }

            nextIndex = endIndex;
            if (nextIndex < rowsCopyData.length)
            {
                document.status.setText(format("Rendering rows: %s/%s ...", nextIndex, rowsCopyData
                        .length));
                return true;
            }

            if (isRepositorySource(document.filePath) && document.drainRepositoryPages)
                document.visibleRows = [];
            else if (appendRows)
                document.visibleRows ~= rowsCopyData;
            else
                document.visibleRows = rowsCopyData;
            document.lastRenderElapsedMs = cast(long)(MonoTime.currTime - renderStarted)
                .total!"msecs";
            updatePerfStatus(document);
            logLineVerbose("[render] finished ", document.filePath,
                ": rows=", rowsCopyData.length,
                ", elapsedMs=", document.lastRenderElapsedMs);

            auto visibleCount = isRepositorySource(document.filePath)
                && document.drainRepositoryPages ? document.repositoryRowsLoaded
                : document.visibleRows.length;
            auto totalCount = isRepositorySource(document.filePath)
                && document.drainRepositoryPages ? document.pageTotal
                : document.loadedRows.length;
            string baseStatus;
            if (filterLabel.length > 0)
            {
                baseStatus = format(
                    "Showing %s/%s rows (filter: %s, case-sensitive: %s)",
                    visibleCount,
                    totalCount,
                    filterLabel,
                    prefCaseSensitiveFilter ? "yes" : "no"
                );
            }
            else
            {
                baseStatus = format("Showing %s/%s rows", visibleCount, totalCount);
            }

            // Nach dem Laden: Spaltenbreiten einmal festziehen, danach bleiben sie stabil.
            document.pendingColumnMeasurement =
                document.tableNaturalWidth <= 0 && filterLabel.length == 0
                && (document.drainRepositoryPages ? document.pageOffset == 0
                    : rowsCopyData.length == document.loadedRows.length);

            // Nach dem Befüllen TreeView wieder verbinden und eine neue Layout-Runde anstoßen.
            document.tableView.setModel(document.tableStore);
            if (document.directorySource !is null && !appendRows)
            {
                renderDirectoryTree(document, document.directorySource,
                    document.expandedDirectoryIds,
                    treeFilterForDocument(document, prefCaseSensitiveFilter), document.treeSortOrder);
                if (document.reconcileDirectoryLoads !is null)
                    new Idle({ document.reconcileDirectoryLoads(); return false; });
            }
            if (completedFilterRequestId != 0)
                document.filterRequest.complete(completedFilterRequestId);
            document.tableView.setSensitive(true);
            document.directoryTreeView.setSensitive(true);
            if (document.pendingColumnMeasurement)
            {
                document.tableView.queueResize();
            }
            if (busyDocument is document)
            {
                setLoadingState(document, false);
            }
            if (document.drainAfterRender)
            {
                document.drainAfterRender = false;
                if (document.repositoryRowsLoaded < document.pageTotal)
                {
                    document.pageOffset = document.repositoryRowsLoaded;
                    document.drainPageRequest = true;
                    document.status.setText(format("Loading rows: %s/%s ...",
                        document.repositoryRowsLoaded, document.pageTotal));
                    new Idle({ loadDocument(document, false); return false; });
                }
            }
            if (!isLoading && pendingStartupPaths.length > 0 && advanceStartupQueue !is null)
                new Idle({ advanceStartupQueue(); return false; });
            document.status.setText(baseStatus);

            return false;
        };

        new Idle(renderStep);
    }

    /** Update one document tab's detail pane from the selected row. */
    updateSelectedRowDetails = (DocumentTab document) {
        TreeModelIF model;
        TreeIter iter;
        auto selection = document.tableView.getSelection();
        auto hasTableSelection = selection.getSelected(model, iter);
        if (hasTableSelection && !document.directorySourceRemote)
        {
            // A direct TreeView selection can outlive filtering. Once the user
            // selects a table row, its row data must become authoritative again.
            document.hasDirectSelectedRow = false;
            document.directSelectedRow = BlobRow.init;
            document.directSelectedIndex = "";
        }
        if (hasTableSelection && document.directorySourceRemote)
        {
            auto sourceIdText = model.getValueString(iter, COL_SOURCE_ID);
            if (sourceIdText.length > 0)
            {
                auto sourceId = to!long(sourceIdText);
                if (!document.hasDirectSelectedRow
                    || document.directSelectedRow.sourceId != sourceId)
                {
                    BlobRow summary;
                    summary.sourceId = sourceId;
                    summary.detailsLoaded = false;
                    summary.fileSize = to!ulong(model.getValueString(iter, COL_FILE_SIZE));
                    summary.hasSummaryFlags = true;
                    summary.summaryHasFileType = model.getValueString(iter, COL_HAS_FILE_TYPE_FLAG) == "1";
                    summary.summaryHasMedia = model.getValueString(iter, COL_HAS_MEDIA_FLAG) == "1";
                    summary.summaryHasVideo = model.getValueString(iter, COL_HAS_VIDEO_FLAG) == "1";
                    summary.summaryHasAudio = model.getValueString(iter, COL_HAS_AUDIO_FLAG) == "1";
                    summary.summaryHasImage = model.getValueString(iter, COL_HAS_IMAGE_FLAG) == "1";
                    summary.summaryHasText = model.getValueString(iter, COL_HAS_TEXT_FLAG) == "1";
                    summary.summaryHasArchive = model.getValueString(iter, COL_HAS_ARCHIVE_FLAG) == "1";
                    summary.summaryHasTorrent = model.getValueString(iter, COL_HAS_TORRENT_FLAG) == "1";
                    document.directSelectedRow = summary;
                    document.hasDirectSelectedRow = true;
                    document.directSelectedIndex = model.getValueString(iter, COL_INDEX);
                }
            }
        }
        if (!hasTableSelection && !document.hasDirectSelectedRow)
        {
            clearSelectionDetails(document);
            return;
        }

        string idx;
        string size;
        string checksums;
        string fileType;
        string mediaInfo;
        string archive;
        string torrent;
        BlobRow row;
        size_t rowIndex;
        if (document.hasDirectSelectedRow)
        {
            idx = document.directSelectedIndex;
            row = document.directSelectedRow;
            size = row.fileSize.to!string;
            checksums = checksumSetStatus(row);
            fileType = boolStatusIcon(row.hasFileType);
            mediaInfo = mediaInfoSummary(row);
            archive = boolStatusIcon(row.hasArchive);
            torrent = boolStatusIcon(row.hasTorrent);
        }
        else
        {
            document.hasDirectSelectedRow = false;
            idx = model.getValueString(iter, COL_INDEX);
            size = model.getValueString(iter, COL_FILE_SIZE);
            checksums = model.getValueString(iter, COL_CHECKSUM_SET);
            fileType = model.getValueString(iter, COL_FILE_TYPE);
            mediaInfo = model.getValueString(iter, COL_MEDIA_INFO);
            archive = model.getValueString(iter, COL_HAS_ARCHIVE);
            torrent = model.getValueString(iter, COL_HAS_TORRENT);
        }
        document.rowDetails.setText(format(
                "Selection: #%s | size=%s | checksums=%s | type=%s | media=%s | archive=%s | torrent=%s",
                idx,
                size,
                checksums,
                fileType,
                mediaInfo,
                archive,
                torrent
        ));

        if (!document.hasDirectSelectedRow)
        {
            try
                rowIndex = to!size_t(idx) - 1;
            catch (Exception)
            {
                clearSelectionDetails(document);
                document.status.setText("Failed to resolve selected row index.");
                return;
            }
            if (rowIndex >= document.visibleRows.length)
            {
                clearSelectionDetails(document);
                document.status.setText("Selected row is outside visible data range.");
                return;
            }
            row = document.visibleRows[rowIndex];
        }

        auto treeSelectionId = row.sourceId >= 0
            ? row.sourceId.to!string : primaryTreeFileNodeId(row, rowIndex);
        TreeIter treeRoot;
        TreeIter treeFile;
        auto foundTreeFile = !document.syncingTreeSelection
            && findDirectoryTreeIter(document.directoryTreeView.getModel(), treeRoot,
                false, treeSelectionId, treeFile);
        final switch (treeSelectionFollowup(document.syncingTreeSelection,
            foundTreeFile))
        {
        case TreeSelectionFollowup.ignoreSynchronizedChange:
            break;
        case TreeSelectionFollowup.selectMaterializedTreeRow:
            document.syncingTreeSelection = true;
            document.directoryTreeView.getSelection().selectIter(treeFile);
            document.syncingTreeSelection = false;
            break;
        case TreeSelectionFollowup.revealTreeFile:
            if (revealTreeFile !is null)
                revealTreeFile(document, treeSelectionId);
            break;
        }
        if (isRepositorySource(document.filePath) && row.sourceId >= 0
            && !row.detailsLoaded)
        {
            auto requestId = ++document.detailRequestId;
            auto sourcePath = document.filePath;
            auto sourceId = row.sourceId;
            setKnownFilesTable(document, row);
            document.status.setText("Loading selected repository details ...");
            auto worker = new Thread({
                NamedBinaryBlob details;
                string error;
                try
                    details = loadDocumentDetails(sourcePath, sourceId);
                catch (Exception ex)
                    error = ex.msg;

                new Idle({
                    if (requestId != document.detailRequestId)
                        return false;
                    if (error.length > 0)
                    {
                        document.status.setText(format(
                            "Failed to load selected details: %s", error));
                        return false;
                    }
                    if (document.hasDirectSelectedRow
                        && document.directSelectedRow.sourceId == sourceId)
                    {
                        auto rows = extractRowsFromBlobs([details]);
                        if (rows.length > 0)
                        {
                            auto flags = document.directSelectedRow;
                            document.directSelectedRow = rows[0];
                            document.directSelectedRow.sourceId = sourceId;
                            document.directSelectedRow.detailsLoaded = true;
                            document.directSelectedRow.hasSummaryFlags = flags.hasSummaryFlags;
                            document.directSelectedRow.summaryHasFileType = flags.summaryHasFileType;
                            document.directSelectedRow.summaryHasMedia = flags.summaryHasMedia;
                            document.directSelectedRow.summaryHasVideo = flags.summaryHasVideo;
                            document.directSelectedRow.summaryHasAudio = flags.summaryHasAudio;
                            document.directSelectedRow.summaryHasImage = flags.summaryHasImage;
                            document.directSelectedRow.summaryHasText = flags.summaryHasText;
                            document.directSelectedRow.summaryHasArchive = flags.summaryHasArchive;
                            document.directSelectedRow.summaryHasTorrent = flags.summaryHasTorrent;
                        }
                    }
                    else
                    {
                        foreach (ref candidate; document.loadedRows)
                        {
                            if (candidate.sourceId == sourceId)
                            {
                                candidate.sourceBlob = details;
                                candidate.detailsLoaded = true;
                            }
                        }
                        foreach (ref candidate; document.visibleRows)
                        {
                            if (candidate.sourceId == sourceId)
                            {
                                candidate.sourceBlob = details;
                                candidate.detailsLoaded = true;
                            }
                        }
                    }
                    updateSelectedRowDetails(document);
                    return false;
                });
            });
            worker.start();
            return;
        }
        document.selectedSha1 = row.sha1;
        document.selectedFileName = row.primaryFileName;
        document.selectedFilePath = row.primaryFileName;
        setDetailEntry(document.detailSha1HexEntry, digestBase64ToHex(row.sha1));
        setDetailEntry(document.detailMd5HexEntry, digestBase64ToHex(row.md5));
        setDetailEntry(document.detailXxh64HexEntry, digestBase64ToHex(row.xxh64));
        setDetailEntry(document.detailIndexEntry, idx);
        setDetailEntry(document.detailSizeEntry, format("%s bytes", row.fileSize));
        setMetadataStatusLabel(document.detailChecksumStatus, "Checksums", checksumStatusSummary(
                row));
        document.detailChecksumExpander.setSensitive(
            row.md5.length > 0 || row.sha1.length > 0 || row.xxh64.length > 0
        );
        setMetadataStatusLabel(document.detailMediaInfoStatus, "MediaInfo", mediaInfoStatusSummary(
                row));
        setMetadataStatusLabel(document.detailFileTypeStatus, "File Type", metadataPresenceSummary(
                row.hasFileType));
        setMetadataStatusLabel(document.detailArchiveStatus, "Archive", metadataPresenceSummary(
                row.hasArchive));
        setMetadataStatusLabel(document.detailTorrentStatus, "Torrent", metadataPresenceSummary(
                row.hasTorrent));
        setMediaInfoStreamDetails(document, row);
        setFallbackDetails(document, row);
        setFileTypeDetails(document.detailFileTypeExpander, document.detailFileTypeLabel,
            row.fileTypeDetails);
        setMetadataDetails(document.detailArchiveExpander, document.detailArchiveView,
            "Archive", archiveMetadataSummary(row));
        setMetadataDetails(document.detailTorrentExpander, document.detailTorrentView,
            "Torrent", torrentMetadataSummary(row));
        setMediaPreview(document, row);
        if (document.selectedPreviewIsVideo)
        {
            new Timeout(60, {
                if (document.selectedPreviewIsVideo)
                {
                    refreshMediaPreview(document);
                }
                return false;
            });
        }
        auto detailsText = format(
            "Selected Row Details\n\n" ~
                "Index: %s\n" ~
                "All file references: %s\n" ~
                "File size: %s bytes\n" ~
                "File references: %s\n" ~
                "Media types: video=%s | audio=%s | image=%s | text=%s\n" ~
                "Checksum set: %s\n" ~
                "MD5 (hex): %s\n" ~
                "SHA1 (hex): %s\n" ~
                "xxh64 (hex): %s\n" ~
                "Has media metadata: %s\n" ~
                "Has file type metadata: %s\n" ~
                "Has archive metadata: %s\n" ~
                "Has torrent metadata: %s\n" ~
                "\nMediaInfo details\n%s\n" ~
                "\nArchive details\n%s\n" ~
                "\nTorrent details\n%s\n" ~
                "\nRaw JSON Object\n\n" ~
                "%s\n",
            idx,
            row.knownFileNamesText,
            row.fileSize,
            row.fileCount,
            row.hasVideo ? "yes" : "no",
            row.hasAudio ? "yes" : "no",
            row.hasImage ? "yes" : "no",
            row.hasText ? "yes" : "no",
            checksumSetStatus(row),
            digestBase64ToHex(row.md5),
            digestBase64ToHex(row.sha1),
            digestBase64ToHex(row.xxh64),
            row.hasMedia ? "yes" : "no",
            row.hasFileType ? "yes" : "no",
            row.hasArchive ? "yes" : "no",
            row.hasTorrent ? "yes" : "no",
            row.mediaInfoDetails.length > 0 ? row.mediaInfoDetails : "-",
            row.archiveDetails.length > 0 ? row.archiveDetails : "-",
            row.torrentDetails.length > 0 ? row.torrentDetails
                : "-",
            row.sourceBlobDetails.length > 0 ? row.sourceBlobDetails : "{}"
        );
        document.selectedDetailsText = detailsText;
        document.btnCopySha1.setSensitive(!isLoading && document.selectedSha1.length > 0);
        document.btnCopyFile.setSensitive(!isLoading && document.selectedFileName.length > 0);
        document.btnCopyPath.setSensitive(!isLoading && document.selectedFilePath.length > 0);
        document.btnCopyDetails.setSensitive(!isLoading && document.selectedDetailsText.length > 0);
        setKnownFilesTable(document, row);
        if (cli.selfTestMode && document.directorySourceRemote)
        {
            if (row.hasArchive)
                expandFirstTreeRoot(document.detailArchiveTreeView);
            if (row.hasTorrent)
                expandFirstTreeRoot(document.detailTorrentTreeView);
        }
    };

    /** Copy a selected value into the system clipboard. */
    copyTextToClipboard = (string label, string value, DocumentTab document) {
        if (value.length == 0)
        {
            document.status.setText(format("No %s value available for selected row.", label));
            return;
        }

        auto display = Display.getDefault();
        if (display is null)
        {
            document.status.setText("Clipboard unavailable: no active display.");
            return;
        }

        auto clipboard = Clipboard.getDefault(display);
        if (clipboard is null)
        {
            document.status.setText("Clipboard unavailable.");
            return;
        }

        clipboard.setText(value, -1);
        document.status.setText(format("Copied %s to clipboard.", label));
    };

    /** Continue automatic startup restoration of saved tabs one file at a time. */
    void loadNextPendingStartupPath()
    {
        if (isLoading)
        {
            return;
        }

        while (pendingStartupPaths.length > 0)
        {
            auto nextPath = pendingStartupPaths[0];
            pendingStartupPaths = pendingStartupPaths[1 .. $];

            if (findDocumentByPath(nextPath) !is null)
            {
                continue;
            }

            auto document = openDocumentFromPath(nextPath, false, false);
            if (document is null)
                continue;
            loadDocument(document, true);
            return;
        }

        if (pendingStartupPaths.length == 0)
        {
            if (!isLoading && pendingStartupSelectIndex >= 0 && pendingStartupSelectIndex < notebook.getNPages())
            {
                notebook.setCurrentPage(pendingStartupSelectIndex);
            }

            scheduleSelfTestQuit(cli.selfTestMode, selfTestQuitScheduled, cli.selfTestDelayMs, selfTestQuitTimer, () { Main.quit(); });
            return;
        }
    }

    advanceStartupQueue = () { loadNextPendingStartupPath(); };

    closeDocumentTab = (DocumentTab document) {
        if (isLoading && busyDocument is document)
        {
            document.status.setText(
                "Cancel or wait for the active operation before closing this tab.");
            return;
        }
        auto pageIndex = notebook.pageNum(document.pageRoot);
        if (pageIndex < 0)
            return;
        if (document.directorySource !is null)
            document.directorySource.close();
        notebook.removePage(pageIndex);
        documents = documents[0 .. pageIndex] ~ documents[pageIndex + 1 .. $];
        syncToolbarFromCurrentDocument();
        persistCurrentState(clearSavedWindowGeometryOnExit);
    };

    /** Open a document in a tab, selecting it optionally, without forcing a reload. */
    openDocumentFromPath = (string filePath, bool selectTab, bool addToRecent) {
        auto normalizedPath = normalizeDocumentPath(filePath);
        if (isRepositorySource(normalizedPath))
        {
            auto repositoryRoot = Repository.findRoot(normalizedPath);
            if (repositoryRoot.length == 0)
            {
                logLine("[open] no repository root found for ", normalizedPath);
                return null;
            }
            normalizedPath = repositoryRoot;
        }
        else
        {
            if (!exists(normalizedPath) || isDir(normalizedPath))
            {
                logLine("[open] not a JSON file: ", normalizedPath);
                return null;
            }
        }
        auto document = findDocumentByPath(normalizedPath);
        if (document is null)
        {
            document = createDocumentTab(normalizedPath);
            documents ~= document;
            auto pageIndex = notebook.appendPage(document.pageRoot,
                createDocumentTabLabel(normalizedPath));
            notebook.setTabReorderable(document.pageRoot, true);
            if (selectTab)
            {
                notebook.setCurrentPage(pageIndex);
            }
            persistCurrentState(clearSavedWindowGeometryOnExit);
        }
        else if (selectTab)
        {
            notebook.setCurrentPage(indexOfDocument(document));
        }

        if (addToRecent)
        {
            noteRecentFile(normalizedPath);
        }

        syncToolbarFromCurrentDocument();
        return document;
    };

    /** Apply the active toolbar filter settings to the current document tab. */
    void applyFilterFromEntry()
    {
        if (isSyncingToolbarState)
        {
            return;
        }
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }

        captureDocumentFilterState(document);
        applyFilterForDocument(document);
    }

    /** Apply one document tab's stored text and media filters in a background worker. */
    applyFilterForDocument = (DocumentTab document) {
        if (isLoading)
        {
            document.status.setText(
                "Background operation in progress. Please wait before filtering.");
            return;
        }
        if (isRepositorySource(document.filePath))
        {
            document.filterApplied = true;
            document.preserveDirectoryTreeNodesOnNextLoad = true;
            persistCurrentState(clearSavedWindowGeometryOnExit);
            document.pageOffset = 0;
            document.drainPageRequest = false;
            loadDocument(document, false);
            return;
        }
        auto hasFilterCriteria = documentFilterHasCriteria(document.filterQuery,
            document.filterVideo, document.filterAudio, document.filterImage,
            document.filterText, document.filterFileType, document.filterArchive,
            document.filterTorrent);
        auto hadFilteredProjection = document.directorySourceFiltered;
        ++document.directoryTreeRefreshRequestId;
        if (!jsonFilterNeedsRebuild(hasFilterCriteria))
        {
            document.filterApplied = false;
            document.directorySourceFiltered = false;
            document.visibleTreeNodeIds = null;
            document.visibleTreeFileIndexes = null;
            document.visibleTreeDirectoryIndexes = null;
            document.visibleDirectoryFileCounts = null;
            document.visibleDirectoryAggregateSizes = null;
            document.visibleDirectoryChildCounts = null;
            document.hasVisibleTreeMatches = false;
            if (document.unfilteredDirectorySource !is null)
            {
                document.directoryTree = document.unfilteredDirectoryTree;
                document.directorySource = document.unfilteredDirectorySource;
            }
            persistCurrentState(clearSavedWindowGeometryOnExit);
            if (hadFilteredProjection)
            {
                if (document.directorySource !is null)
                    renderDirectoryTree(document, document.directorySource,
                        document.expandedDirectoryIds, FileFilter(),
                        document.treeSortOrder);
                refreshExpandedJsonDirectories(document, FileFilter(),
                    document.treeSortOrder, prefCaseSensitiveFilter);
                renderRows(document, document.loadedRows);
            }
            else
                document.status.setText(format("Showing %s/%s rows",
                    document.loadedRows.length, document.loadedRows.length));
            return;
        }
        document.filterApplied = true;
        persistCurrentState(clearSavedWindowGeometryOnExit);
        /* Abort async filter results from previous requests, if any, by invalidating their requestId with a new one. */
        auto requestId = document.filterRequest.begin();
        ++document.directoryTreeRefreshRequestId;

        /* Check the filter requirements set for this document. */
        auto query = document.filterQuery;
        auto caseSensitive = prefCaseSensitiveFilter;

        auto requireVideo = document.filterVideo;
        auto requireAudio = document.filterAudio;
        auto requireImage = document.filterImage;
        auto requireText = document.filterText;
        auto negateMediaFilter = document.filterMediaNegated;

        auto requireFileType = document.filterFileType;
        auto requireArchive = document.filterArchive;
        auto requireTorrent = document.filterTorrent;
        bool hasFilterRequirements = requireVideo || requireAudio || requireImage
            || requireText || requireFileType || requireArchive || requireTorrent;

        // The load/filter busy guard prevents operations that mutate loadedRows
        // until this worker finishes, so share the stable slice instead of
        // synchronously copying a potentially huge catalog on the GTK thread.
        const(BlobRow)[] sourceRows = document.loadedRows;
        auto sourceTree = document.unfilteredDirectoryTree;
        auto treeSource = document.unfilteredDirectorySource !is null
            ? document.unfilteredDirectorySource : document.directorySource;
        auto expandedTreeIds = directoryTreeIdsToRefresh(
            document.directoryTreeStore, document.expandedDirectoryIds);
        auto treeFilterSnapshot = treeFilterForDocument(document,
            prefCaseSensitiveFilter);
        auto treeSortSnapshot = document.treeSortOrder;

        string mediaFilterSummary()
        {
            if (!hasFilterRequirements)
            {
                return "";
            }
            auto labels = appender!(string[])();
            if (requireVideo)
                labels.put("V");
            if (requireAudio)
                labels.put("A");
            if (requireImage)
                labels.put("I");
            if (requireText)
                labels.put("T");
            if (requireFileType)
                labels.put("FT");
            if (requireArchive)
                labels.put("AR");
            if (requireTorrent)
                labels.put("TO");
            auto summary = labels.data.join(",");
            return negateMediaFilter ? format("NOT %s", summary) : summary;
        }

        setLoadingState(document, true, format("Filtering %s rows ...", sourceRows.length));
        progressBar.setText("Filtering rows ...");
        document.tableView.setSensitive(false);
        document.directoryTreeView.setSensitive(false);
        showFilteringTreePlaceholder(document);

        auto worker = new Thread({
            MonoTime started = MonoTime.currTime;
            AsyncFilterResult result;
            result.query = query;
            result.caseSensitive = caseSensitive;

            try
            {
                JsonFilterOptions filterOptions;
                filterOptions.text = query;
                filterOptions.caseSensitive = caseSensitive;
                filterOptions.video = requireVideo;
                filterOptions.audio = requireAudio;
                filterOptions.image = requireImage;
                filterOptions.textStream = requireText;
                filterOptions.mediaNegated = negateMediaFilter;
                filterOptions.fileType = requireFileType;
                filterOptions.archive = requireArchive;
                filterOptions.torrent = requireTorrent;
                auto filtered = filterJsonRows(sourceRows, sourceTree, filterOptions);
                result.filteredRows = filtered.rows;
                result.visibleTreeFileIndexes = filtered.visibleTreeFileIndexes;
                result.visibleTreeDirectoryIndexes = filtered.visibleTreeDirectoryIndexes;
                result.visibleDirectoryFileCounts = filtered.visibleDirectoryFileCounts;
                result.visibleDirectoryAggregateSizes =
                    filtered.visibleDirectoryAggregateSizes;
                result.visibleDirectoryChildCounts = filtered.visibleDirectoryChildCounts;
                result.hasVisibleTreeMatches = filtered.hasVisibleTreeMatches;
                result.mediaStats = mediaHitStats(result.filteredRows);
                if (treeSource !is null)
                {
                    foreach (directoryId; expandedTreeIds)
                    {
                        AsyncExpandedDirectoryRows directoryRows;
                        directoryRows.directoryId = directoryId;
                        directoryRows.directories = treeSource.listDirectories(
                            directoryId, treeFilterSnapshot);
                        directoryRows.filePage = treeSource.listFilteredFilesPage(
                            directoryId, FileCursor(), 251, treeFilterSnapshot,
                            sourceFileSortOrder(treeSortSnapshot));
                        result.expandedDirectoryRows ~= directoryRows;
                    }
                }
            }
            catch (Exception ex)
            {
                result.error = ex.msg;
            }

            result.elapsedMs = cast(long)(MonoTime.currTime - started).total!"msecs";

            new Idle({
                if (!document.filterRequest.isCurrent(requestId))
                {
                    return false;
                }
                if (result.error.length > 0)
                {
                    document.filterRequest.complete(requestId);
                    document.tableView.setSensitive(true);
                    document.directoryTreeView.setSensitive(true);
                    if (document.directorySource !is null)
                        renderDirectoryTree(document, document.directorySource,
                            document.expandedDirectoryIds,
                            treeFilterForDocument(document, prefCaseSensitiveFilter),
                            document.treeSortOrder);
                    setLoadingState(document, false, format("Filtering failed: %s", result.error));
                    return false;
                }

                document.lastFilterElapsedMs = result.elapsedMs;

                auto filterLabel = result.query;
                auto mediaSummary = mediaFilterSummary();
                if (mediaSummary.length > 0 && filterLabel.length > 0)
                {
                    filterLabel = format("%s | media:%s", filterLabel, mediaSummary);
                }
                else if (mediaSummary.length > 0)
                {
                    filterLabel = format("media:%s", mediaSummary);
                }
                if (result.mediaStats.length > 0)
                {
                    filterLabel = filterLabel.length > 0
                    ? format("%s | %s", filterLabel, result.mediaStats) : result.mediaStats;
                }
                document.visibleTreeNodeIds = null;
                document.visibleTreeFileIndexes = result.visibleTreeFileIndexes;
                document.visibleTreeDirectoryIndexes = result.visibleTreeDirectoryIndexes;
                document.visibleDirectoryFileCounts = result.visibleDirectoryFileCounts;
                document.visibleDirectoryAggregateSizes =
                    result.visibleDirectoryAggregateSizes;
                document.visibleDirectoryChildCounts = result.visibleDirectoryChildCounts;
                document.hasVisibleTreeMatches = result.hasVisibleTreeMatches;
                document.directorySourceFiltered = true;
                if (!document.reuseDirectoryTreeNodes && document.directorySource !is null)
                    renderDirectoryTree(document, document.directorySource,
                        document.expandedDirectoryIds,
                        treeFilterForDocument(document, prefCaseSensitiveFilter),
                        document.treeSortOrder);
                foreach (directoryRows; result.expandedDirectoryRows)
                {
                    TreeIter root;
                    TreeIter parent;
                    if (!findDirectoryTreeIter(document.directoryTreeStore, root, false,
                            directoryRows.directoryId, parent))
                        continue;
                    populateDirectoryTreeRows(document.directoryTreeStore, parent,
                        directoryRows.directories, directoryRows.filePage.files, true,
                        document.treeSortOrder, directoryRows.filePage.hasMore,
                        directoryRows.filePage.nextCursor);
                }
                updateTreeModelVisibility(document,
                    treeFilterForDocument(document, prefCaseSensitiveFilter));
                renderRows(document, result.filteredRows, filterLabel, false,
                    requestId);
                return false;
            });
        });

        worker.start();
    };

    /** Rebuild the current tab's layout measurement after manual widget relayout. */
    void relayoutCurrentDocument()
    {
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }

        logLineVerbose("[relayout] manual relayout requested for ", document.filePath);
        document.pendingColumnMeasurement = true;
        document.tableView.setModel(document.repositoryTableModel is null
            ? cast(TreeModelIF) document.tableStore : document.repositoryTableModel);
        document.tableView.queueResize();
    }

    clearFilterForDocument = (DocumentTab document) {
        if (document is null)
            return;
        if (isLoading)
        {
            document.status.setText("Wait for the current operation before clearing filters.");
            return;
        }

        auto hadFilteredProjection = document.directorySourceFiltered;
        resetFilterState(document);
        document.filterApplied = false;
        document.visibleTreeNodeIds = null;
        document.visibleTreeFileIndexes = null;
        document.visibleTreeDirectoryIndexes = null;
        document.visibleDirectoryFileCounts = null;
        document.visibleDirectoryAggregateSizes = null;
        document.visibleDirectoryChildCounts = null;
        document.hasVisibleTreeMatches = false;
        ++document.directoryTreeRefreshRequestId;
        auto previousSyncState = isSyncingToolbarState;
        isSyncingToolbarState = true;
        document.filterEntry.setText("");
        document.filterVideoWidget.setActive(false);
        document.filterAudioWidget.setActive(false);
        document.filterImageWidget.setActive(false);
        document.filterTextWidget.setActive(false);
        document.filterMediaNotWidget.setActive(false);
        document.filterFileTypeWidget.setActive(false);
        document.filterArchiveWidget.setActive(false);
        document.filterTorrentWidget.setActive(false);
        isSyncingToolbarState = previousSyncState;
        persistCurrentState(clearSavedWindowGeometryOnExit);

        if (currentDocument() is document)
            syncToolbarSensitivity();
        if (isRepositorySource(document.filePath))
        {
            document.preserveDirectoryTreeNodesOnNextLoad = true;
            document.pageOffset = 0;
            document.drainPageRequest = false;
            loadDocument(document, false);
        }
        else
        {
            if (document.unfilteredDirectorySource !is null)
            {
                document.directoryTree = document.unfilteredDirectoryTree;
                document.directorySource = document.unfilteredDirectorySource;
            }
            document.directorySourceFiltered = false;
            if (hadFilteredProjection)
            {
                renderDirectoryTree(document, document.directorySource,
                    document.expandedDirectoryIds, FileFilter(),
                    document.treeSortOrder);
                refreshExpandedJsonDirectories(document, FileFilter(),
                    document.treeSortOrder, prefCaseSensitiveFilter);
                renderRows(document, document.loadedRows);
            }
            else
                document.status.setText(format("Showing %s/%s rows",
                    document.loadedRows.length, document.loadedRows.length));
        }
    };

    /** Clear all active toolbar filter state for the current document tab. */
    void clearCurrentFilter()
    {
        auto document = currentDocument();
        if (document !is null)
            clearFilterForDocument(document);
    }

    /** Load and normalize the JSON file for one open document tab.
     *
     * Params:
     *   document = the document tab to load
     */
    loadDocument = (DocumentTab document, bool fitHorizontalSplitAfterLoad = true) {
        if (isLoading)
        {
            auto current = currentDocument();
            if (current !is null)
            {
                current.status.setText("A load is already in progress.");
            }
            return;
        }

        if (!exists(document.filePath))
        {
            document.status.setText(format("File not found: %s", document.filePath));
            document.tableStore.clear();
            document.tableNaturalWidth = -1;
            document.tableMinimumWidth = -1;
            document.fitHorizontalSplitAfterLoad = false;
            document.pendingColumnMeasurement = false;
            return;
        }

        auto requestId = ++document.loadRequestId;
        auto repositorySource = isRepositorySource(document.filePath);
        auto preserveTreeNodes = document.preserveDirectoryTreeNodesOnNextLoad;
        document.preserveDirectoryTreeNodesOnNextLoad = false;
        if (!preserveTreeNodes)
            document.reuseDirectoryTreeNodes = false;
        if (repositorySource)
        {
            if (!document.drainPageRequest)
            {
                document.drainRepositoryPages = true;
                document.pageOffset = 0;
                document.repositoryRowsLoaded = 0;
                document.repositoryBlobCursor = 0;
                document.loadedRows = [];
            }
            document.drainPageRequest = false;
        }
        document.tableNaturalWidth = -1;
        document.tableMinimumWidth = -1;
        document.fitHorizontalSplitAfterLoad = fitHorizontalSplitAfterLoad;
        document.pendingColumnMeasurement = false;
        logLineVerbose("[load] start ", document.filePath,
            ", fitAfterLoad=", fitHorizontalSplitAfterLoad,
            ", verbose=", cli.argVerboseOutputs);
        setLoadingState(document, true, format("Loading %s ...", document.filePath));
        auto sourceQuerySnapshot = sourceQueryForDocument(document,
            prefCaseSensitiveFilter);
        auto treeFilterSnapshot = treeFilterForDocument(document,
            prefCaseSensitiveFilter);
        auto expandedTreeIdsSnapshot = directoryTreeIdsToRefresh(
            document.directoryTreeStore, document.expandedDirectoryIds);
        auto treeSortSnapshot = document.treeSortOrder;
        auto hasTreeFilterSnapshot = documentFilterHasCriteria(
            treeFilterSnapshot.text, treeFilterSnapshot.video, treeFilterSnapshot.audio,
            treeFilterSnapshot.image, treeFilterSnapshot.textStream,
            treeFilterSnapshot.fileType, treeFilterSnapshot.archive,
            treeFilterSnapshot.torrent);

        auto worker = new Thread({
            MonoTime started = MonoTime.currTime;
            AsyncLoadResult result;
            result.filePath = document.filePath;

            try
            {
                setLoadingPhase(document, requestId,
                    isRepositorySource(document.filePath)
                    ? "Loading SQLite repository via library ..."
                    : "Loading scanner data via library ...");
                logLineVerbose("[load-worker] parsing ", document.filePath);
                NamedBinaryBlob[] blobs;
                if (isRepositorySource(document.filePath))
                {
                    if (document.drainRepositoryPages)
                    {
                        result.pageOffset = document.repositoryRowsLoaded;
                        auto page = loadDocumentCursorPage(document.filePath,
                            document.repositoryBlobCursor, document.pageSize,
                            sourceQuerySnapshot);
                        blobs = page.blobs;
                        result.blobIds = page.blobIds;
                        result.blobFlags = page.flags;
                        result.pageTotal = page.total;
                        result.nextBlobId = page.nextBlobId;
                        result.hasMore = page.hasMore;
                    }
                    else if (document.loadAllRows)
                    {
                        auto page = loadDocumentPage(document.filePath, 0,
                            size_t.max, sourceQuerySnapshot);
                        blobs = page.blobs;
                        result.blobIds = page.blobIds;
                        result.blobFlags = page.flags;
                        result.pageOffset = page.offset;
                        result.pageTotal = page.total;
                    }
                    else
                    {
                        auto page = loadDocumentPage(document.filePath,
                            document.pageOffset, document.pageSize,
                            sourceQuerySnapshot);
                        blobs = page.blobs;
                        result.blobIds = page.blobIds;
                        result.blobFlags = page.flags;
                        result.pageOffset = page.offset;
                        result.pageTotal = page.total;
                    }
                    result.pagedSource = true;
                }
                else
                {
                    blobs = loadDocumentSource(document.filePath);
                }
                if (isRepositorySource(document.filePath))
                {
                    result.dataVersion = 3;
                    result.rootShape = "repository";
                    result.rootKeysSummary = "SQLite repository";
                }
                else
                {
                    result.dataVersion = DATA_CLASS_VERSION2;
                    result.rootShape = "library";
                    result.rootKeysSummary = "NamedBinaryBlob[]";
                }

                setLoadingPhase(document, requestId, "Projecting blob rows for GUI ...");
                result.allRows = extractRowsFromBlobs(blobs);
                foreach (index, blobId; result.blobIds)
                {
                    if (index >= result.allRows.length)
                        break;
                    result.allRows[index].sourceId = blobId;
                    if (index < result.blobFlags.length)
                    {
                        auto flags = result.blobFlags[index];
                        auto row = &result.allRows[index];
                        row.hasSummaryFlags = true;
                        row.summaryHasMedia = flags.hasMedia;
                        row.summaryHasVideo = flags.hasVideo;
                        row.summaryHasAudio = flags.hasAudio;
                        row.summaryHasImage = flags.hasImage;
                        row.summaryHasText = flags.hasText;
                        row.summaryHasFileType = flags.hasFileType;
                        row.summaryHasArchive = flags.hasArchive;
                        row.summaryHasTorrent = flags.hasTorrent;
                        row.detailsLoaded = false;
                        // The blob table retains only the compact summary DTO.
                        // Full file references and nested metadata are fetched
                        // on selection through loadDocumentDetails().
                        row.sourceBlob = null;
                    }
                }
                if (isRepositorySource(document.filePath))
                {
                    result.directoryTree = DirectoryTree();
                    if (hasTreeFilterSnapshot || preserveTreeNodes)
                    {
                        auto treeSource = openRepositoryDirectorySource(
                            document.filePath);
                        scope (exit)
                            treeSource.close();
                        if (hasTreeFilterSnapshot)
                            result.visibleTreeNodeIds["root"] = true;
                        auto queryDirectoryIds = expandedTreeIdsSnapshot.dup;
                        if (hasTreeFilterSnapshot
                            && !queryDirectoryIds.canFind("root")
                            && (treeSource.listDirectories("root",
                                treeFilterSnapshot).length > 0
                                || treeSource.hasMatchingFileInDirectory("root",
                                    treeFilterSnapshot)))
                            result.visibleTreeNodeIds["root:match"] = true;
                        foreach (directoryId; queryDirectoryIds)
                        {
                            AsyncExpandedDirectoryRows directoryRows;
                            directoryRows.directoryId = directoryId;
                            directoryRows.directories = treeSource.listDirectories(
                                directoryId, treeFilterSnapshot);
                            directoryRows.filePage = treeSource.listFilteredFilesPage(
                                directoryId, FileCursor(), 251, treeFilterSnapshot,
                                sourceFileSortOrder(treeSortSnapshot));
                            if (hasTreeFilterSnapshot
                                && (directoryRows.directories.length > 0
                                    || directoryRows.filePage.files.length > 0))
                                result.visibleTreeNodeIds[directoryId] = true;
                            foreach (directory; directoryRows.directories)
                            {
                                if (hasTreeFilterSnapshot)
                                {
                                    result.visibleTreeNodeIds[directory.id] = true;
                                    result.visibleTreeNodeIds[directory.parentId] = true;
                                }
                            }
                            if (hasTreeFilterSnapshot)
                                foreach (file; directoryRows.filePage.files)
                                    result.visibleTreeNodeIds[file.cursorId] = true;
                            result.expandedDirectoryRows ~= directoryRows;
                        }
                    }
                }
                else
                {
                    setLoadingPhase(document, requestId,
                        "Building JSON directory index ...");
                    result.directoryTree = projectRowsToDirectoryTree(result.allRows);
                    result.directorySource = new ProjectedDirectorySource(
                        result.directoryTree);
                }

                logLineVerbose("[load-worker] done ", document.filePath,
                    ": rows=", result.allRows.length);
            }
            catch (Exception ex)
            {
                result.error = ex.msg;
                logLineVerbose("[load-worker] failed ", document.filePath, ": ", ex.msg);
            }

            result.elapsedMs = cast(long)(MonoTime.currTime - started).total!"msecs";

            new Idle({
                if (requestId != document.loadRequestId)
                {
                    return false;
                }

                if (result.error.length > 0)
                {
                    document.tableStore.clear();
                    document.loadedRows = [];
                    document.visibleRows = [];
                    document.loadedDataVersion = -1;
                    document.loadedRootShape = "-";
                    document.loadedRootKeysSummary = "-";
                    clearSelectionDetails(document);
                setLoadingState(document, false, format("Failed to parse JSON: %s", result
                    .error));
                    if (pendingStartupPaths.length > 0)
                    {
                        new Idle({ loadNextPendingStartupPath(); return false; });
                    }
                    return false;
                }

                document.sourceLoaded = true;
                if (result.pagedSource && document.drainRepositoryPages)
                {
                    document.repositoryRowsLoaded = result.pageOffset + result.allRows.length;
                    document.repositoryBlobCursor = result.nextBlobId;
                    document.loadedRows = [];
                }
                else
                {
                    document.repositoryRowsLoaded = 0;
                    document.loadedRows = result.allRows;
                }
                document.directorySourceRemote = isRepositorySource(document.filePath);
                if (document.directorySourceRemote)
                {
                    document.directoryTree = result.directoryTree;
                    document.unfilteredDirectoryTree = DirectoryTree();
                    document.directorySource = openRepositoryDirectorySource(document.filePath);
                    document.unfilteredDirectorySource = null;
                    document.directorySourceFiltered = documentFilterHasCriteria(
                        document.filterQuery, document.filterVideo,
                        document.filterAudio, document.filterImage,
                        document.filterText, document.filterFileType,
                        document.filterArchive, document.filterTorrent);
                    document.visibleTreeNodeIds = result.visibleTreeNodeIds;
                    document.visibleTreeFileIndexes = null;
                    document.visibleTreeDirectoryIndexes = null;
                    document.visibleDirectoryFileCounts = null;
                    document.visibleDirectoryAggregateSizes = null;
                    document.visibleDirectoryChildCounts = null;
                    document.hasVisibleTreeMatches = false;
                }
                else
                {
                    document.directoryTree = result.directoryTree;
                    document.unfilteredDirectoryTree = result.directoryTree;
                    document.directorySource = result.directorySource;
                    document.unfilteredDirectorySource = result.directorySource;
                    document.directorySourceFiltered = false;
                    document.visibleTreeNodeIds = null;
                    document.visibleTreeFileIndexes = null;
                    document.visibleTreeDirectoryIndexes = null;
                    document.visibleDirectoryFileCounts = null;
                    document.visibleDirectoryAggregateSizes = null;
                    document.visibleDirectoryChildCounts = null;
                    document.hasVisibleTreeMatches = false;
                }
                auto applyLoadedJsonFilter = !document.directorySourceRemote
                    && shouldApplyDocumentFilter(documentFilterHasCriteria(
                        document.filterQuery, document.filterVideo,
                        document.filterAudio, document.filterImage, document.filterText,
                        document.filterFileType, document.filterArchive,
                        document.filterTorrent), document.filterApplied,
                        prefAutoApplyFilter);
                if (applyLoadedJsonFilter)
                {
                    showFilteringTreePlaceholder(document);
                }
                else
                {
                    auto initialTreeFilter = document.directorySourceRemote
                        ? treeFilterForDocument(document, prefCaseSensitiveFilter) : FileFilter();
                    renderDirectoryTree(document, document.directorySource,
                        document.expandedDirectoryIds, initialTreeFilter,
                        document.treeSortOrder);
                    if (document.directorySourceRemote
                        && result.expandedDirectoryRows.length > 0)
                    {
                        foreach (directoryRows; result.expandedDirectoryRows)
                        {
                            TreeIter root;
                            TreeIter parent;
                            if (!findDirectoryTreeIter(document.directoryTreeStore,
                                    root, false, directoryRows.directoryId, parent))
                                continue;
                            populateDirectoryTreeRows(document.directoryTreeStore,
                                parent, directoryRows.directories,
                                directoryRows.filePage.files, true,
                                document.treeSortOrder,
                                directoryRows.filePage.hasMore,
                                directoryRows.filePage.nextCursor);
                        }
                        if (document.directorySourceFiltered)
                            updateTreeModelVisibility(document, initialTreeFilter);
                        else
                        {
                            TreeIter treeRoot;
                            if (document.directoryTreeStore.getIterFirst(treeRoot))
                                setTreeSubtreeVisible(document.directoryTreeStore,
                                    treeRoot, true);
                            document.directoryTreeFilterModel.refilter();
                        }
                        restoreExpandedDirectories(document.directoryTreeView,
                            document.expandedDirectoryIds);
                        selectPendingTreeFile(document);
                    }
                    else if (document.reconcileDirectoryLoads !is null)
                        new Idle({ document.reconcileDirectoryLoads(); return false; });
                    if (document.pendingTreeRevealFileId.length > 0 && revealTreeFile !is null)
                        revealTreeFile(document, document.pendingTreeRevealFileId);
                    selectPendingTreeFile(document);
                }
                document.loadedDataVersion = result.dataVersion;
                document.loadedRootShape = result.rootShape.length > 0 ? result.rootShape : "-";
                document.loadedRootKeysSummary = result.rootKeysSummary.length > 0 ? result.rootKeysSummary
                : "-";
                document.pageOffset = result.pageOffset;
                document.pageTotal = result.pageTotal;
                document.pageBar.setVisible(true);
                document.pageFirstButton.setSensitive(result.pageOffset > 0);
                document.pagePreviousButton.setSensitive(result.pageOffset > 0);
                document.pageNextButton.setSensitive(
                    !document.drainRepositoryPages
                    && result.pageOffset + result.allRows.length < result.pageTotal);
                document.pageLastButton.setSensitive(
                    !document.drainRepositoryPages
                    && result.pageOffset + result.allRows.length < result.pageTotal);
                if (result.pagedSource)
                {
                    if (document.drainRepositoryPages)
                        document.pageStatus.setText(format("%s matching rows", result.pageTotal));
                    else
                    {
                        auto first = result.pageTotal == 0 ? 0 : result.pageOffset + 1;
                        auto last = result.pageOffset + result.allRows.length;
                        document.pageStatus.setText(format("Rows %s-%s of %s", first, last,
                            result.pageTotal));
                    }
                }
                updateFileMetaStatus(document);
                document.lastLoadElapsedMs = result.elapsedMs;
                document.drainAfterRender = false;

                if (isRepositorySource(document.filePath))
                {
                    if (document.drainRepositoryPages)
                    {
                        auto tableQuery = sourceQueryForDocument(document,
                            prefCaseSensitiveFilter);
                        document.loadedRows = [];
                        document.visibleRows = [];
                        document.repositoryTableModel = new VirtualBlobTableModel(
                            document.filePath, tableQuery, document.pageSize, result.allRows,
                            result.pageTotal, result.nextBlobId, result.hasMore);
                        setBlobTableVirtualMode(document.tableView, true);
                        document.tableView.setModel(document.repositoryTableModel);
                        if (busyDocument is document)
                            setLoadingState(document, false);
                        document.status.setText(format(
                            "Showing %s matching blobs; more rows load while scrolling",
                            result.pageTotal));
                    }
                    else
                    {
                        document.tableView.setFixedHeightMode(false);
                        renderRows(document, filterRowsByText(document.loadedRows,
                            document.filterQuery, prefCaseSensitiveFilter));
                    }
                }
                else if (applyLoadedJsonFilter)
                {
                    // End the load request before starting the separate filter
                    // request; the filter worker uses the same global busy guard.
                    setLoadingState(document, false);
                    applyFilterForDocument(document);
                }
                else
                {
                    renderRows(document, document.loadedRows);
                }

                if (cli.selfTestMode)
                {
                    TreeModelIF model;
                    TreeIter firstRow;
                    auto selection = document.tableView.getSelection();
                    logLineVerbose("[self-test] selecting first row for ", document.filePath);
                    auto hasSelection = selection.getSelected(model, firstRow);
                    auto tableModel = document.tableView.getModel();
                    if (!hasSelection && tableModel !is null)
                    {
                        auto hasFirstRow = tableModel.getIterFirst(firstRow);
                        if (hasFirstRow)
                        {
                            selection.selectIter(firstRow);
                            logLineVerbose("[self-test] first row selected");
                        }
                    }
                }

                logLineVerbose("[load] queued render ", document.filePath,
                ": rows=", document.loadedRows.length,
                ", autoFilter=", prefAutoApplyFilter ? "yes" : "no");

                persistCurrentState(clearSavedWindowGeometryOnExit);
                if (pendingStartupPaths.length > 0 && !isLoading)
                {
                    new Idle({ loadNextPendingStartupPath(); return false; });
                }
                else if (cli.selfTestMode && pendingStartupPaths.length == 0 && !selfTestQuitScheduled)
                {
                    selfTestQuitScheduled = true;
                    logLine("[self-test] scheduling quit in ", cli.selfTestDelayMs, " ms");
                    selfTestQuitTimer = new Timeout(cli.selfTestDelayMs, {
                        logLine("[self-test] quitting after startup delay");
                        Main.quit();
                        return false;
                    });
                }
                return false;
            });
        });

        worker.start();
    };

    /** Cancel the currently active background request. */
    void cancelPendingLoad()
    {
        if (!isLoading || busyDocument is null)
        {
            auto document = currentDocument();
            if (document !is null)
            {
                document.status.setText("No load in progress.");
            }
            return;
        }

        auto cancelledDocument = busyDocument;
        auto restoreRowsAfterFilterCancel = cancelledDocument.filterRequest.invalidate();
        ++cancelledDocument.loadRequestId;
        ++cancelledDocument.renderRequestId;
        setLoadingState(cancelledDocument, false,
            "Operation cancelled. Background result will be discarded.");
        if (restoreRowsAfterFilterCancel)
            clearFilterForDocument(cancelledDocument);
    }

    fileOpenMenuItem.addOnActivate((MenuItem _) {
        chooseAndLoadPath(
            window,
            FileOpenDialogCallbacks(
                () { return isLoading; },
                () { return currentDocument(); },
                (string filePath, bool selectTab, bool addToRecent) { return openDocumentFromPath(filePath, selectTab, addToRecent); },
                (DocumentTab document, bool selectTab) { loadDocument(document, selectTab); }
            )
        );
    });

    fileOpenRepositoryMenuItem.addOnActivate((MenuItem _) {
        chooseAndLoadRepository(
            window,
            FileOpenDialogCallbacks(
                () { return isLoading; },
                () { return currentDocument(); },
                (string filePath, bool selectTab, bool addToRecent) { return openDocumentFromPath(filePath, selectTab, addToRecent); },
                (DocumentTab document, bool selectTab) { loadDocument(document, selectTab); }
            )
        );
    });

    fileExportCsvMenuItem.addOnActivate((MenuItem _) {
        exportFilteredRows(currentDocument(), false);
    });
    fileExportJsonMenuItem.addOnActivate((MenuItem _) {
        exportFilteredRows(currentDocument(), true);
    });

    fileReloadMenuItem.addOnActivate((MenuItem _) {
        reloadCurrentDocument(DocumentActionCallbacks(
            () { return currentDocument(); },
            () { return notebook.getCurrentPage(); },
            () { return cast(int) documents.length; },
            (int pageIndex) { return documents[pageIndex]; },
            (int pageIndex) { notebook.removePage(pageIndex); },
            () { syncToolbarFromCurrentDocument(); },
            (bool clearGeometry) { persistCurrentState(clearGeometry); },
            () { return isLoading; },
            () { return busyDocument; },
            () { return clearSavedWindowGeometryOnExit; },
            (DocumentTab document, bool fitHorizontalSplitAfterLoad) { loadDocument(document, fitHorizontalSplitAfterLoad); }
        ));
    });

    fileCloseMenuItem.addOnActivate((MenuItem _) {
        closeCurrentDocument(DocumentActionCallbacks(
            () { return currentDocument(); },
            () { return notebook.getCurrentPage(); },
            () { return cast(int) documents.length; },
            (int pageIndex) { return documents[pageIndex]; },
            (int pageIndex) { if (documents[pageIndex].directorySource !is null) documents[pageIndex].directorySource.close(); notebook.removePage(pageIndex); documents = documents[0 .. pageIndex] ~ documents[pageIndex + 1 .. $]; },
            () { syncToolbarFromCurrentDocument(); },
            (bool clearGeometry) { persistCurrentState(clearGeometry); },
            () { return isLoading; },
            () { return busyDocument; },
            () { return clearSavedWindowGeometryOnExit; },
            (DocumentTab document, bool fitHorizontalSplitAfterLoad) { loadDocument(document, fitHorizontalSplitAfterLoad); }
        ));
    });

    fileCancelOperationMenuItem.addOnActivate((MenuItem _) { cancelPendingLoad(); });

    fileQuitMenuItem.addOnActivate((MenuItem _) {
        persistCurrentState(clearSavedWindowGeometryOnExit);
        Main.quit();
    });

    editApplyFilterMenuItem.addOnActivate((MenuItem _) { applyFilterFromEntry(); });

    editClearFilterMenuItem.addOnActivate((MenuItem _) {
        clearCurrentFilter();
    });

    editPreferencesMenuItem.addOnActivate((MenuItem _) {
        showPreferencesDialog(
            window,
            prefAutoApplyFilter,
            prefCaseSensitiveFilter,
            prefDetailsBelow,
            prefRestoreOpenFiles,
            recentFileLimit,
            externalOpenProgram,
            clearSavedWindowGeometryOnExit,
            PreferencesDialogCallbacks(
                () { applyDetailsPanePreferenceToAll(); },
                (bool clearGeometry) { persistCurrentState(clearGeometry); },
                () { return currentDocument(); },
                () { clearRecentFiles(); }
            )
        );
    });

    editResetMetricsMenuItem.addOnActivate((MenuItem _) {
        auto document = currentDocument();
        if (document is null)
        {
            return;
        }
        resetPerfMetrics(document);
    });

    helpShortcutsMenuItem.addOnActivate((MenuItem _) { showShortcutsHelp(window); });
    helpAboutMenuItem.addOnActivate((MenuItem _) { showAbout(window); });

    attachMenuAccelerator(fileOpenMenuItem, 'o');
    attachMenuAccelerator(fileOpenRepositoryMenuItem, 'o',
        GdkModifierType.CONTROL_MASK | GdkModifierType.SHIFT_MASK);
    attachMenuAccelerator(fileReloadMenuItem, 'r');
    attachMenuAccelerator(fileCloseMenuItem, 'w');
    attachMenuAccelerator(fileCancelOperationMenuItem, 'k');
    attachMenuAccelerator(fileQuitMenuItem, 'q');
    attachMenuAccelerator(editApplyFilterMenuItem, 'f');
    attachMenuAccelerator(editClearFilterMenuItem, 'l');
    attachMenuAccelerator(editPreferencesMenuItem, ',', GdkModifierType.CONTROL_MASK);
    attachMenuAccelerator(editResetMetricsMenuItem, 'm');

    enforceRecentFileLimit();
    refreshRecentFilesMenu();

    // Apply persisted splitter orientation/position to any tabs created later.

    bindToolbarButtons(
        btnReload,
        btnRelayout,
        btnCancelLoad,
        ToolbarBindingsCallbacks(
            () {
                reloadCurrentDocument(DocumentActionCallbacks(
                    () { return currentDocument(); },
                    () { return notebook.getCurrentPage(); },
                    () { return cast(int) documents.length; },
                    (int pageIndex) { return documents[pageIndex]; },
                    (int pageIndex) { if (documents[pageIndex].directorySource !is null) documents[pageIndex].directorySource.close(); notebook.removePage(pageIndex); documents = documents[0 .. pageIndex] ~ documents[pageIndex + 1 .. $]; },
                    () { syncToolbarFromCurrentDocument(); },
                    (bool clearGeometry) { persistCurrentState(clearGeometry); },
                    () { return isLoading; },
                    () { return busyDocument; },
                    () { return clearSavedWindowGeometryOnExit; },
                    (DocumentTab document, bool fitHorizontalSplitAfterLoad) { loadDocument(document, fitHorizontalSplitAfterLoad); }
                ));
            },
            () { relayoutCurrentDocument(); },
            () { cancelPendingLoad(); },
            () { applyFilterFromEntry(); },
            () { clearCurrentFilter(); }
        )
    );

    bindWindowLifecycleSignals(
        notebook,
        window,
        WindowLifecycleCallbacks(
            (bool clearGeometry) { persistCurrentState(clearGeometry); },
            () { return clearSavedWindowGeometryOnExit; },
            (int width, int height) {
                if (width >= MIN_VALID_WINDOW_WIDTH && height >= MIN_VALID_WINDOW_HEIGHT)
                {
                    lastKnownWindowWidth = width;
                    lastKnownWindowHeight = height;
                }
            },
            () { return allowRuntimeStatePersistence; },
            (bool value) { allowRuntimeStatePersistence = value; },
            () { return windowSizePersistTimer; },
            (Timeout value) { windowSizePersistTimer = value; }
        )
    );

    window.showAll();

    if (loadedState.hasWindowSize)
    {
        auto restoredWidth = loadedState.windowWidth;
        auto restoredHeight = loadedState.windowHeight;

        if (restoredWidth < 640)
        {
            restoredWidth = 640;
        }
        if (restoredHeight < 400)
        {
            restoredHeight = 400;
        }

        // Initial apply right after widgets are visible.
        new Idle({
            window.setDefaultSize(restoredWidth, restoredHeight);
            window.resize(restoredWidth, restoredHeight);
            lastKnownWindowWidth = restoredWidth;
            lastKnownWindowHeight = restoredHeight;
            return false;
        });

        // XFCE can apply its own first configure cycle after map; enforce once more.
        new Timeout(120, {
            window.setDefaultSize(restoredWidth, restoredHeight);
            window.resize(restoredWidth, restoredHeight);
            lastKnownWindowWidth = restoredWidth;
            lastKnownWindowHeight = restoredHeight;
            return false;
        });

        // Second delayed pass to win late WM adjustments.
        new Timeout(320, {
            window.setDefaultSize(restoredWidth, restoredHeight);
            window.resize(restoredWidth, restoredHeight);
            lastKnownWindowWidth = restoredWidth;
            lastKnownWindowHeight = restoredHeight;
            return false;
        });

        // Some WMs settle size after initial composition; enforce a final pass.
        new Timeout(700, {
            window.setDefaultSize(restoredWidth, restoredHeight);
            window.resize(restoredWidth, restoredHeight);
            lastKnownWindowWidth = restoredWidth;
            lastKnownWindowHeight = restoredHeight;
            return false;
        });

        // Final late pass to override very late WM/session adjustments.
        new Timeout(1500, {
            window.setDefaultSize(restoredWidth, restoredHeight);
            window.resize(restoredWidth, restoredHeight);
            lastKnownWindowWidth = restoredWidth;
            lastKnownWindowHeight = restoredHeight;
            allowRuntimeStatePersistence = true;
            persistCurrentState(clearSavedWindowGeometryOnExit);
            return false;
        });
    }
    else
    {
        allowRuntimeStatePersistence = true;
    }

    syncToolbarFromCurrentDocument();

    previewVideoProgressTimer = startPreviewProgressTimer(
        PreviewProgressCallbacks(
            () { return currentDocument(); },
            (DocumentTab document) { syncVideoPreviewPosition(document); },
            (DocumentTab document) { syncVideoTrackSelectors(document); },
            (DocumentTab document, bool playing) { syncVideoPlaybackButton(document, playing); }
        )
    );

    startStartupWorkflow(
        pendingStartupPaths,
        pendingStartupSelectIndex,
        prefRestoreOpenFiles,
        loadedState.openFilePaths,
        cli.jsonPaths,
        loadedState.activeTabIndex,
        cli.selfTestMode,
        selfTestQuitScheduled,
        cli.selfTestDelayMs,
        selfTestQuitTimer,
        () { loadNextPendingStartupPath(); },
        () { Main.quit(); }
    );

    Main.run();
    return 0;
}

@("expanded directory refresh removes stale placeholders and upserts rows by ID")
unittest
{
    auto types = new GType[TREE_COL_PROJECTION_INDEX + 1];
    types[] = GType.STRING;
    types[TREE_COL_VISIBLE] = GType.BOOLEAN;
    auto store = new TreeStore(types);

    TreeIter root;
    store.append(root, null);
    store.setValue(root, 0, "root");
    store.setValue(root, 1, "Directory");
    store.setValue(root, 3, "root");
    store.setValue(root, TREE_COL_NODE_ID, "root");
    store.setValue(root, TREE_COL_PROJECTION_INDEX, "0");
    setTreeNodeVisible(store, root, true);

    TreeIter directory;
    store.append(directory, root);
    store.setValue(directory, 0, "music");
    store.setValue(directory, 1, "Directory");
    store.setValue(directory, 3, "directory:music");
    store.setValue(directory, TREE_COL_NODE_ID, "directory:music");
    store.setValue(directory, TREE_COL_PROJECTION_INDEX, "1");
    setTreeNodeVisible(store, directory, true);

    TreeIter placeholder;
    store.append(placeholder, directory);
    store.setValue(placeholder, 0, "Loading...");
    store.setValue(placeholder, 1, "Placeholder");
    store.setValue(placeholder, 3, "directory:music");
    store.setValue(placeholder, TREE_COL_NODE_ID, "Placeholder:directory:music");
    store.setValue(placeholder, TREE_COL_PROJECTION_INDEX, "1");
    setTreeNodeVisible(store, placeholder, true);

    FileNode file;
    file.id = "blob-1";
    file.cursorId = "file-ref-1";
    file.directoryId = "directory:music";
    file.name = "song.mkv";
    file.relativePath = "music/song.mkv";
    file.size = 123;
    populateDirectoryTreeRows(store, directory, [], [file], false);

    assert(store.iterNChildren(directory) == 1);
    TreeIter materialized;
    assert(store.iterChildren(materialized, directory));
    assert(store.getValueString(materialized, 1) == "File");
    assert(store.getValueString(materialized, TREE_COL_NODE_ID) == "file-ref-1");

    populateDirectoryTreeRows(store, directory, [], [file], false);
    assert(store.iterNChildren(directory) == 1);
}
