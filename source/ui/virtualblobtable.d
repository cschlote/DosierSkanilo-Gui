/** Bounded-cache GtkTreeModel for cursor-backed repository blob summaries. */
module ui.virtualblobtable;

import core.thread : Thread;
import gobject.Value;
import gtk.TreeIter;
import gtk.TreeModel;
import gtk.TreePath;
import gtk.c.types : GType, GtkTreeModelFlags;

import std.algorithm : min;
import std.conv : to;
import std.format : format;

import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob;
import dosierskanilo.repository.types : RepositoryBlobFlags;
import model.blobrow : BlobRow, extractRowsFromBlobs;
import model.datasource : SourceQuery, SourcePage, loadDocumentCursorPage;
import ui.mainsources : scheduleUiIdle;
import ui.documenttab : COL_CHECKSUM_SET, COL_FILE_SIZE, COL_FILE_SIZE_SORT,
    COL_FILE_TYPE, COL_HAS_ARCHIVE, COL_HAS_TORRENT, COL_INDEX, COL_INDEX_SORT,
    COL_MEDIA_INFO, COL_SOURCE_ID, COL_HAS_FILE_TYPE_FLAG, COL_HAS_MEDIA_FLAG,
    COL_HAS_VIDEO_FLAG, COL_HAS_AUDIO_FLAG, COL_HAS_IMAGE_FLAG, COL_HAS_TEXT_FLAG,
    COL_HAS_ARCHIVE_FLAG, COL_HAS_TORRENT_FLAG;

/**
 * The model reports the filtered row count immediately but only caches a small
 * number of summary chunks. Rows outside the cache display a loading placeholder
 * while their cursor chunk is fetched on a worker.
 */
final class VirtualBlobTableModel : TreeModel
{
private:
    enum int iteratorStamp = 0x44534B47;
    enum size_t maxCachedChunks = 4;

    string sourcePath;
    SourceQuery query;
    size_t chunkSize;
    size_t rowCount;
    size_t loadedChunkCount = 1;
    long[] chunkCursors;
    BlobRow[][size_t] chunks;
    size_t[] cacheOrder;
    bool requestActive;
    size_t requestedTargetChunk;
    size_t activeChunkIndex;
    bool hasRequestedTargetChunk;
    string loadError;

public:
    this(string sourcePath, SourceQuery query, size_t chunkSize, BlobRow[] firstChunk,
        size_t totalRows, long nextBlobId, bool hasMore)
    {
        super();
        this.sourcePath = sourcePath;
        this.query = query;
        this.chunkSize = chunkSize > 0 ? chunkSize : 250;
        this.rowCount = totalRows;
        this.chunks[0] = firstChunk.dup;
        this.cacheOrder ~= 0;
        this.chunkCursors ~= 0;
        if (hasMore)
            this.chunkCursors ~= nextBlobId;
    }

    override GtkTreeModelFlags getFlags() const
    {
        return cast(GtkTreeModelFlags) 0;
    }

    override int getNColumns() const { return 18; }

    override GType getColumnType(int column)
    {
        return column >= 0 && column < getNColumns() ? GType.STRING : GType.INVALID;
    }

    override int getIter(TreeIter iter, TreePath path)
    {
        if (iter is null || path is null)
            return 0;
        auto indices = path.getIndices();
        if (indices.length != 1 || indices[0] < 0 || cast(size_t) indices[0] >= rowCount)
            return 0;
        setIter(iter, cast(size_t) indices[0]);
        return 1;
    }

    override TreePath getPath(TreeIter iter)
    {
        size_t index;
        if (!getIndex(iter, index))
            return null;
        auto path = new TreePath();
        path.appendIndex(cast(int) index);
        return path;
    }

    override Value getValue(TreeIter iter, int column, Value value = null)
    {
        if (value is null)
            value = new Value();
        value.init(GType.STRING);
        size_t index;
        if (column < 0 || column >= getNColumns() || !getIndex(iter, index))
        {
            value.setString("");
            return value;
        }
        auto chunkIndex = index / chunkSize;
        if (auto chunk = chunkIndex in chunks)
        {
            auto localIndex = index - chunkIndex * chunkSize;
            if (localIndex < chunk.length)
            {
                value.setString(columnText((*chunk)[localIndex], column, index));
                auto prefetchAt = chunk.length > 20 ? chunk.length - 20 : 0;
                if (!requestActive && localIndex >= prefetchAt
                    && chunkIndex + 1 < chunkCursors.length)
                    requestChunk(chunkIndex + 1);
            }
            else
                value.setString("");
        }
        else
        {
            value.setString(column == COL_INDEX ? loadError.length > 0
                ? "Load failed" : "Loading..." : "");
            requestChunk(chunkIndex);
        }
        return value;
    }

    override bool iterNext(TreeIter iter)
    {
        size_t index;
        if (!getIndex(iter, index) || index + 1 >= rowCount)
            return false;
        setIter(iter, index + 1);
        return true;
    }

    override bool iterChildren(out TreeIter iter, TreeIter parent)
    {
        if (parent !is null || rowCount == 0)
        {
            iter = new TreeIter();
            iter.setModel(this);
            return false;
        }
        iter = new TreeIter();
        iter.setModel(this);
        setIter(iter, 0);
        return true;
    }

    override bool iterHasChild(TreeIter iter) { return iter is null && rowCount > 0; }

    override int iterNChildren(TreeIter iter)
    {
        return iter is null ? cast(int) min(rowCount, cast(size_t) int.max) : 0;
    }

    override bool iterNthChild(out TreeIter iter, TreeIter parent, int n)
    {
        if (parent !is null || n < 0 || cast(size_t) n >= rowCount)
        {
            iter = new TreeIter();
            iter.setModel(this);
            return false;
        }
        iter = new TreeIter();
        iter.setModel(this);
        setIter(iter, cast(size_t) n);
        return true;
    }

    override bool iterParent(out TreeIter iter, TreeIter child)
    {
        iter = new TreeIter();
        iter.setModel(this);
        return false;
    }

private:
    void setIter(TreeIter iter, size_t index)
    {
        auto raw = iter.getTreeIterStruct();
        raw.stamp = iteratorStamp;
        raw.userData = cast(void*) (index + 1);
        raw.userData2 = null;
        raw.userData3 = null;
        iter.setModel(this);
    }

    bool getIndex(TreeIter iter, out size_t index) const
    {
        if (iter is null)
            return false;
        auto raw = iter.getTreeIterStruct();
        if (raw.stamp != iteratorStamp || raw.userData is null)
            return false;
        index = cast(size_t) raw.userData - 1;
        return index < rowCount;
    }

    string columnText(const(BlobRow) row, int column, size_t index) const
    {
        final switch (column)
        {
        case COL_INDEX: return (index + 1).to!string;
        case COL_FILE_SIZE: return row.fileSize.to!string;
        case COL_CHECKSUM_SET: return row.md5.length + row.sha1.length + row.xxh64.length == 0
            ? "none" : row.md5.length > 0 && row.sha1.length > 0 && row.xxh64.length > 0
                ? "full" : "partial";
        case COL_FILE_TYPE: return row.hasFileType ? "✓" : "—";
        case COL_MEDIA_INFO:
            string media;
            if (row.hasVideo) media ~= "V";
            if (row.hasAudio) media ~= "A";
            if (row.hasImage) media ~= "I";
            if (row.hasText) media ~= "T";
            return media.length > 0 ? media : row.hasMedia ? "yes" : "—";
        case COL_HAS_ARCHIVE: return row.hasArchive ? "✓" : "—";
        case COL_HAS_TORRENT: return row.hasTorrent ? "✓" : "—";
        case COL_INDEX_SORT: return format("%020d", index + 1);
        case COL_FILE_SIZE_SORT: return format("%020d", row.fileSize);
        case COL_SOURCE_ID: return row.sourceId >= 0 ? row.sourceId.to!string : "";
        case COL_HAS_FILE_TYPE_FLAG: return row.hasFileType ? "1" : "0";
        case COL_HAS_MEDIA_FLAG: return row.hasMedia ? "1" : "0";
        case COL_HAS_VIDEO_FLAG: return row.hasVideo ? "1" : "0";
        case COL_HAS_AUDIO_FLAG: return row.hasAudio ? "1" : "0";
        case COL_HAS_IMAGE_FLAG: return row.hasImage ? "1" : "0";
        case COL_HAS_TEXT_FLAG: return row.hasText ? "1" : "0";
        case COL_HAS_ARCHIVE_FLAG: return row.hasArchive ? "1" : "0";
        case COL_HAS_TORRENT_FLAG: return row.hasTorrent ? "1" : "0";
        }
    }

    void requestChunk(size_t wantedChunk)
    {
        if (wantedChunk * chunkSize >= rowCount || wantedChunk in chunks)
            return;
        if (requestActive)
        {
            if (wantedChunk != activeChunkIndex)
            {
                requestedTargetChunk = wantedChunk;
                hasRequestedTargetChunk = true;
            }
            return;
        }
        if (chunkCursors.length == 0)
            return;
        auto chunkIndex = wantedChunk < chunkCursors.length
            ? wantedChunk : chunkCursors.length - 1;
        if (wantedChunk > chunkIndex)
        {
            requestedTargetChunk = wantedChunk;
            hasRequestedTargetChunk = true;
        }
        auto afterBlobId = chunkCursors[chunkIndex];
        auto path = sourcePath;
        auto queryCopy = query;
        auto size = chunkSize;
        activeChunkIndex = chunkIndex;
        requestActive = true;
        new Thread({
            SourcePage page;
            string error;
            try
                page = loadDocumentCursorPage(path, afterBlobId, size, queryCopy);
            catch (Exception ex)
                error = ex.msg;
            scheduleUiIdle({
                requestActive = false;
                if (error.length > 0)
                {
                    loadError = error;
                    auto first = chunkIndex * chunkSize;
                    auto last = min(rowCount, first + chunkSize);
                    foreach (rowIndex; first .. last)
                    {
                        auto iter = new TreeIter();
                        iter.setModel(this);
                        setIter(iter, rowIndex);
                        rowChanged(getPath(iter), iter);
                    }
                }
                else
                {
                    auto rows = projectRows(page.blobs, page.blobIds, page.flags);
                    chunks[chunkIndex] = rows;
                    if (chunkIndex == chunkCursors.length - 1 && page.hasMore)
                        chunkCursors ~= page.nextBlobId;
                    cacheOrder ~= chunkIndex;
                    while (cacheOrder.length > maxCachedChunks)
                    {
                        auto expired = cacheOrder[0];
                        cacheOrder = cacheOrder[1 .. $];
                        if (expired != chunkIndex)
                            chunks.remove(expired);
                    }
                    foreach (rowOffset; 0 .. rows.length)
                    {
                        auto iter = new TreeIter();
                        iter.setModel(this);
                        setIter(iter, chunkIndex * chunkSize + rowOffset);
                        rowChanged(getPath(iter), iter);
                    }
                }
                if (error.length == 0 && hasRequestedTargetChunk)
                {
                    auto target = requestedTargetChunk;
                    if (target == chunkIndex || target in chunks || !page.hasMore)
                    {
                        hasRequestedTargetChunk = false;
                    }
                    else
                    {
                        requestChunk(target);
                    }
                }
                return false;
            });
        }).start();
    }

    BlobRow[] projectRows(NamedBinaryBlob[] blobs, long[] blobIds,
        RepositoryBlobFlags[] flags)
    {
        auto rows = extractRowsFromBlobs(blobs);
        foreach (index, ref row; rows)
        {
            if (index < blobIds.length)
            {
                row.sourceId = blobIds[index];
                row.detailsLoaded = false;
            }
            if (index < flags.length)
            {
                auto summary = flags[index];
                row.hasSummaryFlags = true;
                row.summaryHasMedia = summary.hasMedia;
                row.summaryHasVideo = summary.hasVideo;
                row.summaryHasAudio = summary.hasAudio;
                row.summaryHasImage = summary.hasImage;
                row.summaryHasText = summary.hasText;
                row.summaryHasFileType = summary.hasFileType;
                row.summaryHasArchive = summary.hasArchive;
                row.summaryHasTorrent = summary.hasTorrent;
            }
            row.sourceBlob = null;
        }
        return rows;
    }
}

@("Virtual blob model value access supports direct string lookup")
unittest
{
    BlobRow row;
    row.sourceId = 17;
    row.fileSize = 123;
    auto model = new VirtualBlobTableModel("", SourceQuery(), 10,
        [row], 1, 0, false);
    TreeIter iter;
    assert(model.iterNthChild(iter, null, 0));
    assert(model.getValueString(iter, COL_SOURCE_ID) == "17");
    assert(model.getValueString(iter, COL_FILE_SIZE) == "123");
}

@("Virtual blob model scrolls through evicted chunks in both directions")
unittest
{
    import core.thread : Thread;
    import core.time : dur;
    import dosierskanilo.repository.repository : Repository;
    import gtk.CellRendererText;
    import gtk.Main : Main;
    import gtk.TreePath;
    import gtk.TreeView;
    import gtk.TreeViewColumn;
    import gtk.Window;
    import glib.MainContext;
    import model.datasource : SourceQuery, loadDocumentCursorPage;
    import std.file : exists, mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.format : format;
    import std.path : buildPath;
    import std.process : environment;
    import std.uuid : randomUUID;

    auto root = buildPath(tempDir(), "virtual-blob-model-" ~ randomUUID().toString());
    mkdirRecurse(root);
    auto catalogPath = buildPath(root, "catalog.json");
    enum size_t rowCount = 1_000;
    enum size_t chunkSize = 50;
    string catalog = `{"dataVersion":3,"dataArray":[`;
    foreach (index; 0 .. rowCount)
    {
        if (index > 0)
            catalog ~= ",";
        catalog ~= format(
            `{"fileName":"virtual-%04d.bin","fileSize":%d,"checkSums":{"md5sum_b64":"digest-%04d"}}`,
            index, index + 1, index);
    }
    catalog ~= "]}";
    write(catalogPath, catalog);

    auto repository = Repository.initialize(root);
    scope (exit)
    {
        repository.close();
        if (exists(root))
            rmdirRecurse(root);
    }
    repository.importJson(catalogPath);
    assert(repository.blobCount == rowCount);

    auto firstPage = loadDocumentCursorPage(root, 0, chunkSize, SourceQuery());
    auto firstRows = extractRowsFromBlobs(firstPage.blobs);
    foreach (index, ref row; firstRows)
    {
        row.sourceId = firstPage.blobIds[index];
        row.detailsLoaded = false;
    }
    auto firstBlobId = firstPage.blobIds[0];
    auto model = new VirtualBlobTableModel(root, SourceQuery(), chunkSize, firstRows,
        firstPage.total, firstPage.nextBlobId, firstPage.hasMore);

    auto context = MainContext.default_();
    string sourceIdAt(size_t rowIndex)
    {
        TreeIter iter;
        assert(model.iterNthChild(iter, null, cast(int) rowIndex));
        auto sourceId = model.getValueString(iter, COL_SOURCE_ID);
        size_t waitedMs;
        while (sourceId.length == 0 && waitedMs < 10_000)
        {
            context.iteration(false);
            Thread.sleep(dur!"msecs"(2));
            waitedMs += 2;
            sourceId = model.getValueString(iter, COL_SOURCE_ID);
        }
        assert(sourceId.length > 0,
            format("The model did not load row %s from its cursor chunk.", rowIndex));
        assert(model.chunks.length <= 4,
            "The virtual table retained more than four summary chunks.");
        return sourceId;
    }

    auto distantRowIndex = chunkSize * 15;
    auto distantBlobId = sourceIdAt(distantRowIndex);
    assert(distantBlobId.length > 0);

    // Queue a request for the evicted first chunk while the next chunk is in flight.
    TreeIter queuedForwardRow;
    TreeIter firstRow;
    assert(model.iterNthChild(queuedForwardRow, null, cast(int) (chunkSize * 16)));
    assert(model.getValueString(queuedForwardRow, COL_SOURCE_ID) == "");
    assert(model.requestActive);
    assert(model.iterNthChild(firstRow, null, 0));
    assert(model.getValueString(firstRow, COL_SOURCE_ID) == "");
    assert(model.hasRequestedTargetChunk && model.requestedTargetChunk == 0);
    assert(sourceIdAt(0) == firstBlobId.to!string);

    auto observedIds = new string[rowCount];
    foreach (rowIndex; 0 .. rowCount)
    {
        observedIds[rowIndex] = sourceIdAt(rowIndex);
    }
    assert(observedIds[0] == firstBlobId.to!string);
    assert(observedIds[distantRowIndex] == distantBlobId);
    assert(model.chunks.length <= 4);

    foreach_reverse (rowIndex; 0 .. rowCount)
        assert(sourceIdAt(rowIndex) == observedIds[rowIndex],
            format("Cursor reload changed the blob ID at row %s.", rowIndex));
    assert(model.chunks.length <= 4);

    if (environment.get("DOSIER_GUI_TABLE_SCROLL_TEST", "") == "1")
    {
        string[] args = ["dosierskanilo-gui-tests"];
        assert(Main.initCheck(args), "GTK table scroll test requires a usable display.");
        auto treeView = new TreeView(model);
        auto renderer = new CellRendererText();
        auto column = new TreeViewColumn();
        column.packStart(renderer, true);
        column.addAttribute(renderer, "text", COL_INDEX);
        treeView.appendColumn(column);
        auto window = new Window("Virtual blob table scroll test");
        window.setDefaultSize(800, 400);
        window.add(treeView);
        window.showAll();
        scope (exit)
            window.destroy();

        size_t[] visibleTargets = [0, 249, 499, 749, 999, 749, 499, 249, 0];
        foreach (rowIndex; visibleTargets)
        {
            auto path = new TreePath();
            path.appendIndex(cast(int) rowIndex);
            treeView.scrollToCell(path, null, true, 0.5f, 0.0f);
            treeView.setCursor(path, null, false);
            assert(sourceIdAt(rowIndex) == observedIds[rowIndex]);
            context.iteration(false);
            assert(model.chunks.length <= 4);
        }
    }
}
