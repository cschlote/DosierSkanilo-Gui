/** GTK-independent directory tree projection for source adapters.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module model.treeprojection;

import std.algorithm : any, canFind, filter, sort;
import std.array : appender, array;
import std.conv : to;
import std.path : baseName, dirName, buildNormalizedPath;
import std.path : extension;
import std.string : toLower;

/** Read-only directory node exposed to the GUI. */
struct DirectoryNode
{
    /// Stable projection identity; the root node uses `"root"`.
    string id;
    /// Identity of the parent directory, or the empty string for the root.
    string parentId;
    /// Display name of the directory without its parent path.
    string name;
    /// Slash-separated path relative to the source root; empty for the root.
    string relativePath;
    /// Number of immediate child directories.
    size_t childDirectoryCount;
    /// Number of files directly contained in this directory.
    size_t fileCount;
    /// Total size in bytes of all files in this directory and its descendants.
    ulong aggregateSize;
    /// Dense index in its owning DirectoryTree projection.
    size_t sourceIndex;
    /// Parent position in the same projection; root points to itself.
    size_t parentIndex;
}

/** Read-only file node exposed to the GUI. */
struct FileNode
{
    /// Stable identity of the file in its source.
    string id;
    /// Identity used as the sort/cursor tie-breaker; may differ from `id`.
    string cursorId;
    /// Identity of the directory containing this file.
    string directoryId;
    /// Display name of the file without its directory path.
    string name;
    /// Slash-separated path relative to the source root.
    string relativePath;
    /// Size of the file payload in bytes.
    ulong size;
    /// Whether the file has a resolved file type.
    bool hasFileType;
    /// Whether the file has any recognized media stream.
    bool hasMedia;
    /// Whether the file has a recognized video stream.
    bool hasVideo;
    /// Whether the file has a recognized audio stream.
    bool hasAudio;
    /// Whether the file has a recognized image stream.
    bool hasImage;
    /// Whether the file has a recognized text stream.
    bool hasText;
    /// Whether the file is or contains an archive.
    bool hasArchive;
    /// Whether the file is or contains a torrent.
    bool hasTorrent;
    /// Dense index in its owning DirectoryTree projection.
    size_t sourceIndex;
    /// Parent directory position in the same projection.
    size_t parentIndex;
}

/** Lazy nested entry projection used by archive and torrent detail trees. */
struct NestedFileNode
{
    /// Virtual or nested identity used to resolve the entry, or empty when
    /// the entry has no safe addressable path.
    string id;
    /// Display name of the nested entry.
    string name;
    /// Path of the entry relative to its containing archive or torrent.
    string relativePath;
    /// Uncompressed size of the entry in bytes.
    ulong size;
    /// Backend-provided modification timestamp, or empty when unknown.
    string modifiedAt;
}

/** Opaque position for resuming a sorted file listing. */
struct FileCursor
{
    /// Relative path of the last returned file.
    string relativePath;
    /// Identity of the last returned file, used as a tie-breaker.
    string id;
    /// Size of the last returned file, used by size-ordered listings.
    ulong size;
}

/** Sort orders supported by filtered file listings. */
enum FileSortOrder : int
{
    /// Sort by relative path in ascending order.
    pathAscending = 0,
    /// Sort by relative path in descending order.
    pathDescending = 1,
    /// Sort by size ascending, then by relative path ascending.
    sizeAscending = 2,
    /// Sort by size descending, then by relative path ascending.
    sizeDescending = 3,
}

/** One bounded page of file nodes plus its continuation state. */
struct FilePage
{
    /// Files included in this page, in the requested sort order.
    FileNode[] files;
    /// Position after the last returned file; meaningful only when `hasMore`.
    FileCursor nextCursor;
    /// Whether more files exist after this page.
    bool hasMore;
}

/** Combined text and type-presence filter for file and directory listings. */
struct FileFilter
{
    /// Text searched in the file name and relative path; empty disables it.
    string text;
    /// Whether the text search is case sensitive.
    bool caseSensitive;
    /// Whether only files with a video stream match.
    bool video;
    /// Whether only files with an audio stream match.
    bool audio;
    /// Whether only files with an image stream match.
    bool image;
    /// Whether only files with a text stream match.
    bool textStream;
    /// Inverts the media-stream match: media files are excluded instead.
    bool mediaNegated;
    /// Whether only files with a resolved file type match.
    bool fileType;
    /// Whether only files with archive content match.
    bool archive;
    /// Whether only files with torrent content match.
    bool torrent;
}

/** Test whether one file satisfies every active clause of `filter`.
 *
 * Clauses that are not enabled are ignored. Media-stream clauses are ORed
 * together and, when `mediaNegated` is set, files matching any of them are
 * rejected instead. Type-presence clauses are also ORed together.
 *
 * Params:
 *     file = File node to test.
 *     filter = Filter whose enabled clauses must all accept the file.
 * Returns: `true` when the file matches the active filter clauses.
 */
private bool matchesFileFilter(const FileNode file, FileFilter filter)
{
    if (filter.text.length > 0)
    {
        auto name = filter.caseSensitive ? file.name : file.name.toLower;
        auto path = filter.caseSensitive ? file.relativePath : file.relativePath.toLower;
        auto query = filter.caseSensitive ? filter.text : filter.text.toLower;
        if (!name.canFind(query) && !path.canFind(query))
            return false;
    }
    auto hasMediaFilter = filter.video || filter.audio || filter.image || filter.textStream;
    auto matchesMedia = (filter.video && file.hasVideo) || (filter.audio && file.hasAudio)
        || (filter.image && file.hasImage) || (filter.textStream && file.hasText);
    if (hasMediaFilter && (filter.mediaNegated ? matchesMedia : !matchesMedia))
        return false;
    auto hasOtherFilter = filter.fileType || filter.archive || filter.torrent;
    auto matchesOther = (filter.fileType && file.hasFileType)
        || (filter.archive && file.hasArchive) || (filter.torrent && file.hasTorrent);
    if (hasOtherFilter && !matchesOther)
        return false;
    return true;
}

/** In-memory directory projection shared by JSON and repository adapters. */
struct DirectoryTree
{
    /// Directories in projection order; index 0 is the root node.
    DirectoryNode[] directories;
    /// Files in projection order, each linked to a directory by identity.
    FileNode[] files;

    /** Root directory node of the projection.
     *
     * Returns: The node stored at index 0.
     */
    @property ref const(DirectoryNode) root() const
    {
        return directories[0];
    }

    /** List the immediate child directories of one parent.
     *
     * Params:
     *     parentId = Identity of the parent directory.
     * Returns: Matching child directories, in projection order; empty when the
     *     parent has no children or is unknown.
     */
    const(DirectoryNode)[] listDirectories(string parentId) const
    {
        auto result = directories.filter!(node => node.parentId == parentId).array;
        return result;
    }

    /** List the files directly contained in one directory.
     *
     * Params:
     *     directoryId = Identity of the containing directory.
     * Returns: Matching files, in projection order; empty when the directory
     *     has no files or is unknown.
     */
    const(FileNode)[] listFiles(string directoryId) const
    {
        auto result = files.filter!(node => node.directoryId == directoryId).array;
        return result;
    }
}

/** Read-only source API consumed by the directory tree view. */
interface DirectorySource
{
    /** Return the root directory node of this source.
     *
     * Returns: The root node of the source projection.
     */
    DirectoryNode root();
    /** List child directories that contain at least one file matching `filter`.
     *
     * Params:
     *     parentId = Identity of the parent directory.
     *     filter = Optional filter; an inactive filter returns all children.
     * Returns: Visible child directories, in source order.
     */
    DirectoryNode[] listDirectories(string parentId, FileFilter filter = FileFilter());
    /** Test whether a directory or any descendant contains a matching file.
     *
     * Params:
     *     directoryId = Identity of the directory to search.
     *     filter = Filter applied to candidate files.
     * Returns: `true` when at least one file in the subtree matches.
     */
    bool hasMatchingFileInDirectory(string directoryId, FileFilter filter = FileFilter());
    /** List files in a directory using offset-based paging.
     *
     * Params:
     *     directoryId = Identity of the containing directory.
     *     offset = Zero-based index of the first file to return.
     *     limit = Maximum number of files to return; `size_t.max` means all.
     *     filter = Case-insensitive text matched against name and path.
     * Returns: A copy of the requested file slice; empty when out of range.
     */
    FileNode[] listFiles(string directoryId, size_t offset = 0, size_t limit = 250,
        string filter = "");
    /** List one file page using cursor-based paging.
     *
     * Params:
     *     directoryId = Identity of the containing directory.
     *     cursor = Position returned by a previous call, or `FileCursor.init`.
     *     limit = Maximum number of files to return.
     *     filter = Case-insensitive text matched against name and path.
     * Returns: The requested page and the cursor for the next page.
     */
    FilePage listFilesPage(string directoryId, FileCursor cursor = FileCursor(),
        size_t limit = 250, string filter = "");
    /** List one filtered, sorted file page using cursor-based paging.
     *
     * Params:
     *     directoryId = Identity of the containing directory.
     *     cursor = Position returned by a previous call, or `FileCursor.init`.
     *     limit = Maximum number of files to return.
     *     filter = Text and type-presence filter.
     *     sortOrder = Ordering applied before paging.
     * Returns: The requested page and the cursor for the next page.
     */
    FilePage listFilteredFilesPage(string directoryId, FileCursor cursor = FileCursor(),
        size_t limit = 250, FileFilter filter = FileFilter(),
        FileSortOrder sortOrder = FileSortOrder.pathAscending);
    /** List the page immediately preceding `cursor` in the same ordering.
     *
     * Params:
     *     directoryId = Identity of the containing directory.
     *     cursor = Position of the first file of the following page.
     *     limit = Maximum number of files to return.
     *     filter = Text and type-presence filter.
     *     sortOrder = Ordering used to locate the preceding files.
     * Returns: Up to `limit` files before the cursor, in the requested order.
     */
    FilePage listPreviousFilteredFilesPage(string directoryId, FileCursor cursor,
        size_t limit = 250, FileFilter filter = FileFilter(),
        FileSortOrder sortOrder = FileSortOrder.pathAscending);
    /// Release resources owned by this source.
    void close();
}

/** Legacy in-memory directory source for JSON projections, fallback paths, and
 * tests. Normal catalog-backed tabs use `CatalogDirectorySource`. */
final class ProjectedDirectorySource : DirectorySource
{
    /// Projection served by this source; retained for the lifetime of the object.
    private DirectoryTree tree;
    /// Child directories indexed by their parent identity.
    private DirectoryNode[][string] childDirectories;
    /// Files indexed by their containing directory identity.
    private FileNode[][string] filesByDirectory;

    /** Build a source and index the supplied projection by parent identity.
     *
     * Params:
     *     tree = Projection to expose; it is copied into the new instance.
     */
    this(DirectoryTree tree)
    {
        this.tree = tree;
        foreach (directory; tree.directories)
            childDirectories[directory.parentId] ~= directory;
        foreach (file; tree.files)
            filesByDirectory[file.directoryId] ~= file;
    }

    /** Return the root node of the indexed projection.
     *
     * Returns: The root node of the served projection.
     */
    override DirectoryNode root() { return tree.root; }

    /** List child directories, optionally restricted to subtrees with matches.
     *
     * Params:
     *     parentId = Identity of the parent directory.
     *     filter = Optional filter; an inactive filter returns all children.
     * Returns: Visible child directories, in projection order.
     */
    override DirectoryNode[] listDirectories(string parentId, FileFilter filter = FileFilter())
    {
        auto children = directoriesFor(parentId);
        auto hasActiveFilter = filter.text.length > 0 || filter.video || filter.audio
            || filter.image || filter.textStream || filter.fileType || filter.archive
            || filter.torrent;
        if (!hasActiveFilter)
            return children.dup;

        DirectoryNode[] result;
        foreach (directory; children)
        {
            if (hasMatchingFile(directory.id, filter))
                result ~= directory;
        }
        return result;
    }

    /** Test whether a directory directly contains a matching file.
     *
     * Params:
     *     directoryId = Identity of the directory to inspect.
     *     filter = Filter applied to the directory's files.
     * Returns: `true` when at least one direct file matches.
     */
    override bool hasMatchingFileInDirectory(string directoryId,
        FileFilter filter = FileFilter())
    {
        foreach (file; filesFor(directoryId))
            if (matchesFileFilter(file, filter))
                return true;
        return false;
    }

    /** Test recursively whether a directory subtree contains a matching file.
     *
     * Params:
     *     directoryId = Identity of the subtree root.
     *     filter = Filter applied to candidate files.
     * Returns: `true` when any file in the subtree matches.
     */
    private bool hasMatchingFile(string directoryId, FileFilter filter)
    {
        if (filesFor(directoryId).any!(file => matchesFileFilter(file, filter)))
            return true;
        foreach (child; directoriesFor(directoryId))
            if (hasMatchingFile(child.id, filter))
                return true;
        return false;
    }

    /** Look up the indexed children of one parent directory.
     *
     * Params:
     *     parentId = Identity of the parent directory.
     * Returns: The indexed children, or an empty slice when the parent is
     *     unknown.
     */
    private const(DirectoryNode)[] directoriesFor(string parentId)
    {
        if (auto directories = parentId in childDirectories)
            return *directories;
        return [];
    }

    /** Look up the indexed files of one directory.
     *
     * Params:
     *     directoryId = Identity of the containing directory.
     * Returns: The indexed files, or an empty slice when the directory is
     *     unknown.
     */
    private const(FileNode)[] filesFor(string directoryId)
    {
        if (auto files = directoryId in filesByDirectory)
            return *files;
        return [];
    }

    /** Compare two files under one sort order.
     *
     * The cursor identity breaks ties after path and size comparisons so that
     * paging remains stable and total.
     *
     * Params:
     *     left = First file to compare.
     *     right = Second file to compare.
     *     order = Ordering that defines the comparison.
     * Returns: A negative number when `left` sorts first, zero when both are
     *     equivalent, and a positive number otherwise.
     */
    private int compareFiles(FileNode left, FileNode right, FileSortOrder order)
    {
        final switch (order)
        {
        case FileSortOrder.pathAscending:
            if (left.relativePath != right.relativePath)
                return left.relativePath < right.relativePath ? -1 : 1;
            break;
        case FileSortOrder.pathDescending:
            if (left.relativePath != right.relativePath)
                return left.relativePath > right.relativePath ? -1 : 1;
            break;
        case FileSortOrder.sizeAscending:
            if (left.size != right.size)
                return left.size < right.size ? -1 : 1;
            if (left.relativePath != right.relativePath)
                return left.relativePath < right.relativePath ? -1 : 1;
            break;
        case FileSortOrder.sizeDescending:
            if (left.size != right.size)
                return left.size > right.size ? -1 : 1;
            if (left.relativePath != right.relativePath)
                return left.relativePath < right.relativePath ? -1 : 1;
            break;
        }
        if (left.cursorId == right.cursorId)
            return 0;
        auto descendingPath = order == FileSortOrder.pathDescending;
        return descendingPath
            ? (left.cursorId > right.cursorId ? -1 : 1)
            : (left.cursorId < right.cursorId ? -1 : 1);
    }

    /** Insert a file into a bounded, sorted candidate buffer.
     *
     * The buffer is kept sorted according to `order` and never grows beyond
     * `capacity`. By default the smallest candidates are retained, which suits
     * a forward page; `keepLargest` retains the greatest candidates instead for
     * a backward page.
     *
     * Params:
     *     candidates = Sorted buffer updated in place.
     *     file = File to insert.
     *     capacity = Maximum number of entries retained; zero is a no-op.
     *     order = Ordering that defines the buffer order.
     *     keepLargest = Keep the greatest candidates rather than the smallest.
     */
    private void insertFileCandidate(ref FileNode[] candidates, FileNode file,
        size_t capacity, FileSortOrder order, bool keepLargest = false)
    {
        if (capacity == 0)
            return;
        size_t low;
        auto high = candidates.length;
        while (low < high)
        {
            auto middle = low + (high - low) / 2;
            if (compareFiles(candidates[middle], file, order) < 0)
                low = middle + 1;
            else
                high = middle;
        }
        auto position = low;
        if (candidates.length < capacity)
        {
            auto oldLength = candidates.length;
            candidates.length = oldLength + 1;
            foreach_reverse (index; position .. oldLength)
                candidates[index + 1] = candidates[index];
            candidates[position] = file;
            return;
        }
        if (!keepLargest)
        {
            if (position >= capacity)
                return;
            foreach_reverse (index; position .. capacity - 1)
                candidates[index + 1] = candidates[index];
            candidates[position] = file;
            return;
        }
        if (position == 0)
            return;
        foreach (index; 1 .. capacity)
            candidates[index - 1] = candidates[index];
        auto insertAt = position - 1;
        foreach_reverse (index; insertAt .. capacity - 1)
            candidates[index + 1] = candidates[index];
        candidates[insertAt] = file;
    }

    /** Build the comparison key node represented by a cursor.
     *
     * Params:
     *     cursor = Cursor position to convert.
     * Returns: A partial file node carrying only the cursor's sort fields.
     */
    private FileNode cursorNode(FileCursor cursor)
    {
        FileNode file;
        file.relativePath = cursor.relativePath;
        file.cursorId = cursor.id;
        file.size = cursor.size;
        return file;
    }

    /** List files in a directory using offset-based paging.
     *
     * Params:
     *     directoryId = Identity of the containing directory.
     *     offset = Zero-based index of the first file to return.
     *     limit = Maximum number of files to return; `size_t.max` means all.
     *     filter = Case-insensitive text matched against name and path.
     * Returns: A copy of the requested file slice; empty when out of range.
     */
    override FileNode[] listFiles(string directoryId, size_t offset = 0, size_t limit = 250,
        string filter = "")
    {
        auto allFiles = filesFor(directoryId);
        if (filter.length > 0)
        {
            auto query = filter.toLower;
            allFiles = allFiles.filter!(file => file.name.toLower.canFind(query)
                || file.relativePath.toLower.canFind(query)).array;
        }
        if (offset >= allFiles.length)
            return [];
        auto end = limit == size_t.max ? allFiles.length : offset + limit;
        if (end > allFiles.length)
            end = allFiles.length;
        return allFiles[offset .. end].dup;
    }

    /** List one file page using a case-insensitive text filter.
     *
     * Params:
     *     directoryId = Identity of the containing directory.
     *     cursor = Position returned by a previous call, or `FileCursor.init`.
     *     limit = Maximum number of files to return.
     *     filter = Case-insensitive text matched against name and path.
     * Returns: The requested page, sorted by ascending relative path.
     */
    override FilePage listFilesPage(string directoryId, FileCursor cursor = FileCursor(),
        size_t limit = 250, string filter = "")
    {
        FileFilter query;
        query.text = filter;
        return listFilteredFilesPage(directoryId, cursor, limit, query,
            FileSortOrder.pathAscending);
    }

    /** List one filtered, sorted file page using cursor-based paging.
     *
     * Files strictly after `cursor` in `sortOrder` are considered. When
     * `limit` is `size_t.max`, all remaining matches are returned and
     * `hasMore` stays `false`.
     *
     * Params:
     *     directoryId = Identity of the containing directory.
     *     cursor = Position returned by a previous call, or `FileCursor.init`.
     *     limit = Maximum number of files to return.
     *     filter = Text and type-presence filter.
     *     sortOrder = Ordering applied before paging.
     * Returns: The requested page and the cursor for the next page.
     */
    override FilePage listFilteredFilesPage(string directoryId, FileCursor cursor = FileCursor(),
        size_t limit = 250, FileFilter filter = FileFilter(),
        FileSortOrder sortOrder = FileSortOrder.pathAscending)
    {
        FilePage page;
        auto files = filesFor(directoryId);
        auto hasCursor = cursor.id.length > 0 || cursor.relativePath.length > 0;
        auto cursorFile = cursorNode(cursor);
        if (limit == size_t.max)
        {
            foreach (file; files)
                if (matchesFileFilter(file, filter)
                    && (!hasCursor || compareFiles(file, cursorFile, sortOrder) > 0))
                    page.files ~= file;
            sort!((a, b) => compareFiles(a, b, sortOrder) < 0)(page.files);
            return page;
        }

        auto capacity = limit + 1;
        FileNode[] candidates;
        foreach (file; filesFor(directoryId))
        {
            if (!matchesFileFilter(file, filter)
                || (hasCursor && compareFiles(file, cursorFile, sortOrder) <= 0))
                continue;
            insertFileCandidate(candidates, file, capacity, sortOrder);
        }
        page.hasMore = candidates.length > limit;
        auto visibleCount = page.hasMore ? limit : candidates.length;
        page.files = candidates[0 .. visibleCount].dup;
        if (page.files.length > 0)
        {
            auto last = page.files[$ - 1];
            page.nextCursor = FileCursor(last.relativePath, last.cursorId, last.size);
        }
        return page;
    }

    /** List the page immediately preceding a cursor in the same ordering.
     *
     * An empty cursor yields an empty page. The returned files are ordered as
     * requested; when `hasMore` is true, `nextCursor` addresses the first
     * returned file so that callers can continue paging backwards.
     *
     * Params:
     *     directoryId = Identity of the containing directory.
     *     cursor = Position of the first file of the following page.
     *     limit = Maximum number of files to return.
     *     filter = Text and type-presence filter.
     *     sortOrder = Ordering used to locate the preceding files.
     * Returns: Up to `limit` files before the cursor, in the requested order.
     */
    override FilePage listPreviousFilteredFilesPage(string directoryId, FileCursor cursor,
        size_t limit = 250, FileFilter filter = FileFilter(),
        FileSortOrder sortOrder = FileSortOrder.pathAscending)
    {
        FilePage page;
        if (cursor.id.length == 0 && cursor.relativePath.length == 0)
            return page;
        auto cursorFile = cursorNode(cursor);
        FileNode[] candidates;
        size_t matchCount;
        foreach (file; filesFor(directoryId))
        {
            if (!matchesFileFilter(file, filter)
                || compareFiles(file, cursorFile, sortOrder) >= 0)
                continue;
            ++matchCount;
            insertFileCandidate(candidates, file, limit, sortOrder, true);
        }
        page.files = candidates;
        page.hasMore = matchCount > limit;
        if (page.hasMore && page.files.length > 0)
        {
            auto first = page.files[0];
            page.nextCursor = FileCursor(first.relativePath, first.cursorId, first.size);
        }
        return page;
    }

    /// Release the in-memory projection. The source holds no external resources.
    override void close() {}
}

/** Build a deterministic tree from source file paths and payload sizes.
 *
 * Directories are synthesized on demand, the root is always index 0, and file
 * order follows the input order. Aggregate sizes are propagated to every
 * ancestor directory.
 *
 * Params:
 *     inputs = Source files to project; each path is normalized.
 * Returns: A root-inclusive projection with files linked to their directories.
 */
DirectoryTree buildDirectoryTree(const(FileInput)[] inputs)
{
    DirectoryTree tree;
    tree.directories ~= DirectoryNode("root", "", "", "", 0, 0, 0);
    tree.directories[0].sourceIndex = 0;
    tree.directories[0].parentIndex = 0;
    size_t[string] directoryIndexes;
    directoryIndexes[""] = 0;
    size_t[] parentIndexes = [0];

    foreach (index, input; inputs)
    {
        auto normalized = buildNormalizedPath(input.path);
        auto directoryPath = dirName(normalized);
        if (directoryPath == ".")
            directoryPath = "";

        auto directoryIndex = ensureDirectory(tree, directoryPath, directoryIndexes,
            parentIndexes);
        auto directoryId = tree.directories[directoryIndex].id;
        auto fileId = input.id.length > 0 ? input.id : "file:" ~ index.to!string;
        FileNode file;
        file.sourceIndex = tree.files.length;
        file.parentIndex = directoryIndex;
        file.id = fileId;
        file.cursorId = fileId;
        file.directoryId = directoryId;
        file.name = baseName(normalized);
        file.relativePath = normalized;
        file.size = input.size;
        file.hasFileType = input.hasFileType;
        file.hasMedia = input.hasMedia;
        file.hasVideo = input.hasVideo;
        file.hasAudio = input.hasAudio;
        file.hasImage = input.hasImage;
        file.hasText = input.hasText;
        file.hasArchive = input.hasArchive;
        file.hasTorrent = input.hasTorrent;
        tree.files ~= file;
        ++tree.directories[directoryIndex].fileCount;
        auto aggregateIndex = directoryIndex;
        while (true)
        {
            tree.directories[aggregateIndex].aggregateSize += input.size;
            if (aggregateIndex == 0)
                break;
            aggregateIndex = parentIndexes[aggregateIndex];
        }
    }
    return tree;
}

/** Minimal adapter input, intentionally independent from Jsonizer and GTK. */
struct FileInput
{
    /// Slash-separated file path as reported by the source.
    string path;
    /// Size of the file payload in bytes.
    ulong size;
    /// Whether the file has a resolved file type.
    bool hasFileType;
    /// Whether the file has any recognized media stream.
    bool hasMedia;
    /// Whether the file has a recognized video stream.
    bool hasVideo;
    /// Whether the file has a recognized audio stream.
    bool hasAudio;
    /// Whether the file has a recognized image stream.
    bool hasImage;
    /// Whether the file has a recognized text stream.
    bool hasText;
    /// Whether the file is or contains an archive.
    bool hasArchive;
    /// Whether the file is or contains a torrent.
    bool hasTorrent;
    /// Stable source-reference identity; falls back to the input ordinal.
    string id;
}

/** Whether a filename commonly denotes an archive supported by DosierArkivo.
 *
 * Params:
 *     path = File path or name whose extension is examined case-insensitively.
 * Returns: `true` when the extension is one of the recognized archive
 *     container extensions.
 */
bool isArchivePathCandidate(string path)
{
    switch (extension(path.toLower))
    {
    case ".zip", ".rar", ".7z", ".tar", ".gz", ".bz2", ".xz", ".tgz",
            ".tbz", ".tbz2", ".txz", ".lz", ".lzma", ".zst", ".cab",
            ".cpio", ".jar", ".war", ".ear", ".apk":
        return true;
    default:
        return false;
    }
}

@("archive path candidates cover the supported container extensions")
unittest
{
    assert(isArchivePathCandidate("bundle.zip"));
    assert(isArchivePathCandidate("nested/archive.tar.gz"));
    assert(!isArchivePathCandidate("notes.txt"));
}

/** Stable identity for one JSON file reference, independent of filtered order.
 *
 * Params:
 *     sourceOrdinal = Zero-based index of the source blob in the catalog.
 *     referenceOrdinal = Zero-based index of the file reference within it.
 * Returns: A `file:json:` identity string derived from both ordinals.
 */
string jsonFileNodeId(size_t sourceOrdinal, size_t referenceOrdinal)
{
    return "file:json:" ~ sourceOrdinal.to!string ~ ":" ~ referenceOrdinal.to!string;
}

/** Ensure a directory and all its ancestors exist in a projection.
 *
 * The root is index 0. Intermediate directories are created on demand and the
 * identity/index maps are updated consistently.
 *
 * Params:
 *     tree = Projection receiving new directory nodes.
 *     path = Slash-separated directory path; empty addresses the root.
 *     directoryIndexes = Map from directory path to projection index.
 *     parentIndexes = Parent index for each directory, in projection order.
 * Returns: Projection index of the requested directory.
 */
private size_t ensureDirectory(ref DirectoryTree tree, string path,
    ref size_t[string] directoryIndexes, ref size_t[] parentIndexes)
{
    if (path.length == 0)
        return 0;

    if (auto existing = path in directoryIndexes)
        return *existing;

    auto parentPath = dirName(path);
    if (parentPath == "." || parentPath == path)
        parentPath = "";
    auto parentIndex = ensureDirectory(tree, parentPath, directoryIndexes,
        parentIndexes);
    auto directoryIndex = tree.directories.length;
    auto id = "directory:" ~ path;
    tree.directories ~= DirectoryNode(id, tree.directories[parentIndex].id,
        baseName(path), path, 0, 0, 0);
    tree.directories[directoryIndex].sourceIndex = directoryIndex;
    tree.directories[directoryIndex].parentIndex = parentIndex;
    parentIndexes ~= parentIndex;
    directoryIndexes[path] = directoryIndex;
    ++tree.directories[parentIndex].childDirectoryCount;
    return directoryIndex;
}

unittest
{
    auto tree = buildDirectoryTree([
        FileInput("music/album/song.flac", 100),
        FileInput("music/album/cover.jpg", 20),
        FileInput("readme.txt", 5),
    ]);

    assert(tree.root.id == "root");
    assert(tree.root.fileCount == 1);
    assert(tree.root.aggregateSize == 125);
    assert(tree.listDirectories("root").length == 1);

    auto album = tree.listDirectories("directory:music");
    assert(album.length == 1);
    assert(album[0].relativePath == "music/album");
    assert(album[0].fileCount == 2);
    assert(album[0].aggregateSize == 120);
    assert(tree.listFiles(album[0].id).length == 2);

    DirectorySource source = new ProjectedDirectorySource(tree);
    assert(source.root.id == "root");
    assert(source.listDirectories("directory:music").length == 1);
    assert(source.listFiles(album[0].id).length == 2);
    assert(source.listFiles("root", 0, 250, "readme").length == 1);
    FileFilter nestedFileFilter;
    nestedFileFilter.text = "song.flac";
    auto visibleRootDirectories = source.listDirectories("root", nestedFileFilter);
    assert(visibleRootDirectories.length == 1);
    assert(visibleRootDirectories[0].name == "music");
    nestedFileFilter.text = "not-present";
    assert(source.listDirectories("root", nestedFileFilter).length == 0);
    nestedFileFilter.text = "SONG.FLAC";
    assert(source.listDirectories("root", nestedFileFilter).length == 1);
    nestedFileFilter.caseSensitive = true;
    assert(source.listDirectories("root", nestedFileFilter).length == 0);
    auto firstPage = source.listFilesPage(album[0].id, FileCursor(), 1);
    assert(firstPage.files.length == 1);
    assert(firstPage.hasMore);
    auto secondPage = source.listFilesPage(album[0].id, firstPage.nextCursor, 1);
    assert(secondPage.files.length == 1);
    assert(!secondPage.hasMore);
}

@("in-memory directory pages retain sort/cursor parity with bounded results")
unittest
{
    import std.format : format;

    FileInput[] inputs;
    foreach (index; 0 .. 2_000)
        inputs ~= FileInput(format("files/file-%04d.dat", index), index + 1);
    DirectorySource source = new ProjectedDirectorySource(buildDirectoryTree(inputs));

    auto firstPage = source.listFilteredFilesPage("directory:files", FileCursor(),
        31, FileFilter(), FileSortOrder.pathAscending);
    assert(firstPage.files.length == 31);
    assert(firstPage.hasMore);
    assert(firstPage.files[0].name == "file-0000.dat");
    assert(firstPage.files[$ - 1].name == "file-0030.dat");

    auto secondPage = source.listFilteredFilesPage("directory:files",
        firstPage.nextCursor, 31, FileFilter(), FileSortOrder.pathAscending);
    assert(secondPage.files.length == 31);
    assert(secondPage.files[0].name == "file-0031.dat");
    assert(secondPage.files[$ - 1].id != firstPage.files[$ - 1].id);

    auto reversePage = source.listFilteredFilesPage("directory:files", FileCursor(),
        31, FileFilter(), FileSortOrder.pathDescending);
    assert(reversePage.files.length == 31);
    assert(reversePage.files[0].name == "file-1999.dat");
    assert(reversePage.files[$ - 1].name == "file-1969.dat");
}

@("JSON directory source applies typed presence filters")
unittest
{
    auto tree = buildDirectoryTree([
        FileInput("album/song.mp3", 10, true, true, false, true, false, false, false, false),
        FileInput("album/cover.jpg", 5, true, true, false, false, true, false, false, false),
        FileInput("album/archive.zip", 20, true, false, false, false, false, false, true, false),
    ]);
    auto source = new ProjectedDirectorySource(tree);
    auto album = source.listDirectories("root")[0];

    FileFilter audioFilter;
    audioFilter.audio = true;
    auto audioPage = source.listFilteredFilesPage(album.id, FileCursor(), 20, audioFilter);
    assert(audioPage.files.length == 1);
    assert(audioPage.files[0].name == "song.mp3");

    FileFilter notAudio;
    notAudio.audio = true;
    notAudio.mediaNegated = true;
    auto notAudioPage = source.listFilteredFilesPage(album.id, FileCursor(), 20, notAudio);
    assert(notAudioPage.files.length == 2);

    FileFilter eitherType;
    eitherType.fileType = true;
    eitherType.archive = true;
    auto eitherPage = source.listFilteredFilesPage(album.id, FileCursor(), 20, eitherType);
    assert(eitherPage.files.length == 3);

    auto smallestPage = source.listFilteredFilesPage(album.id, FileCursor(), 1,
        FileFilter(), FileSortOrder.sizeAscending);
    assert(smallestPage.files.length == 1);
    assert(smallestPage.files[0].name == "cover.jpg");
    assert(smallestPage.nextCursor.size == smallestPage.files[0].size);
    auto nextSizePage = source.listFilteredFilesPage(album.id,
        smallestPage.nextCursor, 1, FileFilter(), FileSortOrder.sizeAscending);
    assert(nextSizePage.files.length == 1);
    assert(nextSizePage.files[0].size >= smallestPage.files[0].size);
    auto previousSizePage = source.listPreviousFilteredFilesPage(album.id,
        FileCursor(nextSizePage.files[0].relativePath, nextSizePage.files[0].id,
            nextSizePage.files[0].size), 1, FileFilter(), FileSortOrder.sizeAscending);
    assert(previousSizePage.files.length == 1);
    assert(previousSizePage.files[0].id == smallestPage.files[0].id);
}

@("directory tree projection scales across many distinct directories")
unittest
{
    import std.format : format;

    FileInput[] inputs;
    foreach (index; 0 .. 10_000)
        inputs ~= FileInput(format("folder-%05d/file.bin", index), 1);

    auto tree = buildDirectoryTree(inputs);
    auto source = new ProjectedDirectorySource(tree);
    assert(source.listDirectories("root").length == 10_000);
    FileFilter pathFilter;
    pathFilter.text = "file.bin";
    assert(source.listDirectories("root", pathFilter).length == 10_000);
    assert(tree.root.childDirectoryCount == 10_000);
    assert(tree.root.fileCount == 0);
    assert(tree.root.aggregateSize == 10_000);
    assert(tree.directories.length == 10_001);
    assert(tree.files.length == 10_000);
    auto lastDirectory = tree.directories[$ - 1];
    assert(lastDirectory.id == "directory:folder-09999");
    assert(lastDirectory.fileCount == 1);
    assert(lastDirectory.aggregateSize == 1);
}
