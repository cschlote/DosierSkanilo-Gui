/** Bounded-cache GtkTreeModel for cursor-backed repository blob summaries.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
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

import dosierskanilo.catalogbackend : CatalogBackend, CatalogPageCursor;
import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob;
import dosierskanilo.repository.types : RepositoryBlobFlags;
import model.blobrow : BlobRow, extractRowsFromBlobs;
import model.datasource : CatalogRowPage, SourceQuery, loadCatalogRowPage;
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
    /// Magic stamp stored in every `TreeIter` issued by this model.
    enum int iteratorStamp = 0x44534B47;
    /// Maximum number of row chunks retained in `chunks` before the oldest is evicted.
    enum size_t maxCachedChunks = 4;

    /// Source path identifying the catalog displayed by this model.
    string sourcePath;
    /// Catalog backend used to load chunks on worker threads.
    CatalogBackend backend;
    /// Filter query forwarded unchanged with every chunk load request.
    SourceQuery query;
    /// Number of rows per chunk; the constructor substitutes 250 for zero.
    size_t chunkSize;
    /// Total number of rows exposed by the model, including rows not yet loaded.
    size_t rowCount;
    /// Number of chunks initially considered loaded; the constructor supplies the first one.
    size_t loadedChunkCount = 1;
    /// Cursor used to load each chunk by index; element zero is `CatalogPageCursor.init`.
    CatalogPageCursor[] chunkCursors;
    /// Loaded row chunks keyed by chunk index; entries are evicted in cache order.
    BlobRow[][size_t] chunks;
    /// Chunk indexes in the order they were loaded, oldest first.
    size_t[] cacheOrder;
    /// True while a background chunk load is in flight; at most one runs at a time.
    bool requestActive;
    /// Chunk index to load once the active request finishes, when queued.
    size_t requestedTargetChunk;
    /// Index of the chunk currently being loaded; meaningful while `requestActive` is true.
    size_t activeChunkIndex;
    /// Whether `requestedTargetChunk` holds a pending follow-up request.
    bool hasRequestedTargetChunk;
    /// Message from the most recent failed chunk load; empty when no error occurred.
    string loadError;

public:
    /** Construct a model over the first chunk of a cursor-backed row set.
     *
     * The first chunk is copied and shown immediately; later chunks are fetched
     * lazily. Iterators handed out by this model remain valid only while the
     * model lives.
     *
     * Params:
     *     sourcePath = Source path used for subsequent chunk loads.
     *     backend = Catalog backend used for subsequent chunk loads.
     *     query = Filter query applied to every chunk load.
     *     chunkSize = Rows per chunk; zero selects the default of 250.
     *     firstChunk = Already loaded rows for chunk zero.
     *     totalRows = Total row count reported to the view.
     *     nextCursor = Cursor for the second chunk, used only when `hasMore`
     *         is true.
     *     hasMore = Whether the source has rows beyond the first chunk.
     */
    this(string sourcePath, CatalogBackend backend, SourceQuery query,
        size_t chunkSize, BlobRow[] firstChunk, size_t totalRows,
        CatalogPageCursor nextCursor, bool hasMore)
    {
        super();
        this.sourcePath = sourcePath;
        this.backend = backend;
        this.query = query;
        this.chunkSize = chunkSize > 0 ? chunkSize : 250;
        this.rowCount = totalRows;
        this.chunks[0] = firstChunk.dup;
        this.cacheOrder ~= 0;
        this.chunkCursors ~= CatalogPageCursor.init;
        if (hasMore)
            this.chunkCursors ~= nextCursor;
    }

    /** Return the model flags.
     *
     * Returns: Zero; the model exposes a flat list rather than persistent
     *     iterators.
     */
    override GtkTreeModelFlags getFlags() const
    {
        return cast(GtkTreeModelFlags) 0;
    }

    /** Return the number of columns exposed by the model.
     *
     * Returns: The fixed column count, 18.
     */
    override int getNColumns() const { return 18; }

    /** Return the data type of a column.
     *
     * Params:
     *     column = Zero-based column index.
     * Returns: `GType.STRING` for a valid column, otherwise `GType.INVALID`.
     */
    override GType getColumnType(int column)
    {
        return column >= 0 && column < getNColumns() ? GType.STRING : GType.INVALID;
    }

    /** Fill `iter` from a tree path.
     *
     * Only single-index paths into the flat row list are accepted.
     *
     * Params:
     *     iter = Iterator to initialize.
     *     path = Path whose first index is the row number.
     * Returns: `1` on success, `0` when the iterator or path is null or the
     *     index is out of range.
     */
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

    /** Build a tree path for an iterator.
     *
     * Params:
     *     iter = Iterator previously issued by this model.
     * Returns: A new path containing the row index, or `null` when the
     *     iterator is not valid for this model.
     */
    override TreePath getPath(TreeIter iter)
    {
        size_t index;
        if (!getIndex(iter, index))
            return null;
        auto path = new TreePath();
        path.appendIndex(cast(int) index);
        return path;
    }

    /** Return the cell value for a row and column.
     *
     * Uncached rows yield an empty value for most columns and a `Loading...`
     * or `Load failed` placeholder for the index column. Requesting a value
     * may start a background chunk load or prefetch the next chunk.
     *
     * Params:
     *     iter = Iterator previously issued by this model.
     *     column = Zero-based column index.
     *     value = Optional value object to reuse; a new one is allocated when
     *         null.
     * Returns: The value object with a string payload; invalid iterators and
     *     columns produce an empty string.
     */
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

    /** Advance an iterator to the next row.
     *
     * Params:
     *     iter = Iterator to advance in place.
     * Returns: `true` if a next row existed, `false` at the end or for an
     *     invalid iterator.
     */
    override bool iterNext(TreeIter iter)
    {
        size_t index;
        if (!getIndex(iter, index) || index + 1 >= rowCount)
            return false;
        setIter(iter, index + 1);
        return true;
    }

    /** Return the first child of the root (or invalidate the iterator).
     *
     * Params:
     *     iter = Output iterator set to the first row.
     *     parent = Parent iterator; must be null for the flat list.
     * Returns: `true` when a first row exists, otherwise `false` with `iter`
     *     bound to this model but unusable.
     */
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

    /** Report whether the node behind an iterator has children.
     *
     * Params:
     *     iter = Iterator to inspect; null denotes the root.
     * Returns: `true` only for the root when the model has rows.
     */
    override bool iterHasChild(TreeIter iter) { return iter is null && rowCount > 0; }

    /** Return the number of children of a node.
     *
     * Params:
     *     iter = Iterator to inspect; null denotes the root.
     * Returns: The row count for the root, otherwise zero. Values above
     *     `int.max` saturate.
     */
    override int iterNChildren(TreeIter iter)
    {
        return iter is null ? cast(int) min(rowCount, cast(size_t) int.max) : 0;
    }

    /** Return the indexed child of a node.
     *
     * Params:
     *     iter = Output iterator for the requested row.
     *     parent = Parent iterator; must be null for the flat list.
     *     n = Zero-based child index.
     * Returns: `true` when the index is a valid row, otherwise `false` with
     *     `iter` bound to this model but unusable.
     */
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

    /** Return the parent of a node.
     *
     * The model is a flat list, so no node has a parent.
     *
     * Params:
     *     iter = Output iterator; always initialized and bound to this model.
     *     child = Child whose parent is requested.
     * Returns: Always `false`.
     */
    override bool iterParent(out TreeIter iter, TreeIter child)
    {
        iter = new TreeIter();
        iter.setModel(this);
        return false;
    }

private:
    /** Store a row index in a `TreeIter`.
     *
     * The index is encoded as `index + 1` so that row zero has non-null user
     * data, distinguishing it from an uninitialized iterator.
     *
     * Params:
     *     iter = Iterator to initialize.
     *     index = Zero-based row index to store.
     */
    void setIter(TreeIter iter, size_t index)
    {
        auto raw = iter.getTreeIterStruct();
        raw.stamp = iteratorStamp;
        raw.userData = cast(void*) (index + 1);
        raw.userData2 = null;
        raw.userData3 = null;
        iter.setModel(this);
    }

    /** Decode and validate a row index stored in a `TreeIter`.
     *
     * Params:
     *     iter = Iterator to inspect.
     *     index = Receives the zero-based row index.
     * Returns: `true` when the stamp matches and the index is within
     *     `rowCount`; `false` for null, stale, or out-of-range iterators.
     */
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

    /** Render one cell of a loaded row as display text.
     *
     * Params:
     *     row = Row supplying the cell data.
     *     column = Zero-based column index.
     *     index = Zero-based row index, used for index and sort columns.
     * Returns: Human-readable text; the index column is one-based and missing
     *     flags are shown as an em dash.
     */
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
        case COL_SOURCE_ID: return row.sourceKey.length > 0 ? row.sourceKey
            : row.sourceId >= 0 ? row.sourceId.to!string : "";
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

    /** Ensure a chunk is loaded, queueing or starting a background request.
     *
     * The call is a no-op when the chunk is already cached or lies beyond
     * `rowCount`; when another load is active the request is remembered as the
     * follow-up target. Progress is reported through `rowChanged` on the UI
     * thread, and failures are stored in `loadError`.
     *
     * Params:
     *     wantedChunk = Zero-based chunk index to load.
     */
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
        while (chunkIndex < chunkCursors.length && chunkIndex in chunks)
            ++chunkIndex;
        if (chunkIndex >= chunkCursors.length)
            return;
        if (wantedChunk > chunkIndex)
        {
            requestedTargetChunk = wantedChunk;
            hasRequestedTargetChunk = true;
        }
        auto cursor = chunkCursors[chunkIndex];
        auto path = sourcePath;
        auto queryCopy = query;
        auto size = chunkSize;
        activeChunkIndex = chunkIndex;
        requestActive = true;
        new Thread({
            CatalogRowPage page;
            string error;
            try
                page = loadCatalogRowPage(backend, cursor, size, queryCopy);
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
                    auto rows = page.rows;
                    chunks[chunkIndex] = rows;
                    if (chunkIndex == chunkCursors.length - 1 && page.hasMore)
                        chunkCursors ~= page.nextCursor;
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

    /** Convert loaded blobs into table rows with IDs and summary flags.
     *
     * The returned rows are detached from their source blobs; only scalar
     * summary data is retained.
     *
     * Params:
     *     blobs = Blobs to project, in display order.
     *     blobIds = Repository IDs aligned with `blobs`; missing entries leave
     *         the row ID unchanged.
     *     flags = Summary flags aligned with `blobs`; missing entries leave the
     *         row without summary flags.
     * Returns: One row per input blob, with `detailsLoaded` cleared where a
     *     repository ID is available.
     */
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
    auto model = new VirtualBlobTableModel("", null, SourceQuery(), 10,
        [row], 1, CatalogPageCursor.init, false);
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
    import model.catalogsource : openCatalogBackend;
    import model.datasource : SourceQuery, loadCatalogRowPage;
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

    auto backend = openCatalogBackend(root);
    scope (exit)
        backend.close();
    auto firstPage = loadCatalogRowPage(backend, CatalogPageCursor.init, chunkSize,
        SourceQuery());
    auto firstRows = firstPage.rows;
    auto firstBlobId = firstRows[0].sourceKey;
    auto model = new VirtualBlobTableModel(root, backend, SourceQuery(), chunkSize,
        firstRows, firstPage.total, firstPage.nextCursor, firstPage.hasMore);

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
            format("The model did not load row %s from its cursor chunk (cursors=%s chunks=%s active=%s target=%s pending=%s error=%s).",
                rowIndex, model.chunkCursors.length, model.chunks.length,
                model.requestActive, model.requestedTargetChunk,
                model.hasRequestedTargetChunk, model.loadError));
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
    assert(sourceIdAt(0) == firstBlobId);

    auto observedIds = new string[rowCount];
    foreach (rowIndex; 0 .. rowCount)
    {
        observedIds[rowIndex] = sourceIdAt(rowIndex);
    }
    assert(observedIds[0] == firstBlobId);
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

    /* Let any in-flight chunk load finish before the backend is closed. */
    size_t drainMs;
    while (model.requestActive && drainMs < 10_000)
    {
        context.iteration(false);
        Thread.sleep(dur!"msecs"(2));
        drainMs += 2;
    }
    assert(!model.requestActive, "A chunk load outlived the scroll test.");
}
