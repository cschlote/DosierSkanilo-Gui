/** GTK-independent directory tree projection for source adapters. */
module model.treeprojection;

import std.algorithm : any, canFind, filter, sort;
import std.array : appender, array;
import std.conv : to;
import std.path : baseName, dirName, buildNormalizedPath;
import std.string : toLower;

/** Read-only directory node exposed to the GUI. */
struct DirectoryNode
{
    string id;
    string parentId;
    string name;
    string relativePath;
    size_t childDirectoryCount;
    size_t fileCount;
    ulong aggregateSize;
    /// Dense index in its owning DirectoryTree projection.
    size_t sourceIndex;
    /// Parent position in the same projection; root points to itself.
    size_t parentIndex;
}

/** Read-only file node exposed to the GUI. */
struct FileNode
{
    string id;
    string cursorId;
    string directoryId;
    string name;
    string relativePath;
    ulong size;
    bool hasFileType;
    bool hasMedia;
    bool hasVideo;
    bool hasAudio;
    bool hasImage;
    bool hasText;
    bool hasArchive;
    bool hasTorrent;
    /// Dense index in its owning DirectoryTree projection.
    size_t sourceIndex;
    /// Parent directory position in the same projection.
    size_t parentIndex;
}

/** Lazy nested entry projection used by archive and torrent detail trees. */
struct NestedFileNode
{
    string id;
    string name;
    string relativePath;
    ulong size;
    string modifiedAt;
}

struct FileCursor
{
    string relativePath;
    string id;
    ulong size;
}

enum FileSortOrder : int
{
    pathAscending = 0,
    pathDescending = 1,
    sizeAscending = 2,
    sizeDescending = 3,
}

struct FilePage
{
    FileNode[] files;
    FileCursor nextCursor;
    bool hasMore;
}

struct FileFilter
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
    DirectoryNode[] directories;
    FileNode[] files;

    @property ref const(DirectoryNode) root() const
    {
        return directories[0];
    }

    const(DirectoryNode)[] listDirectories(string parentId) const
    {
        auto result = directories.filter!(node => node.parentId == parentId).array;
        return result;
    }

    const(FileNode)[] listFiles(string directoryId) const
    {
        auto result = files.filter!(node => node.directoryId == directoryId).array;
        return result;
    }
}

/** Read-only source API consumed by the directory tree view. */
interface DirectorySource
{
    DirectoryNode root();
    DirectoryNode[] listDirectories(string parentId, FileFilter filter = FileFilter());
    bool hasMatchingFileInDirectory(string directoryId, FileFilter filter = FileFilter());
    FileNode[] listFiles(string directoryId, size_t offset = 0, size_t limit = 250,
        string filter = "");
    FilePage listFilesPage(string directoryId, FileCursor cursor = FileCursor(),
        size_t limit = 250, string filter = "");
    FilePage listFilteredFilesPage(string directoryId, FileCursor cursor = FileCursor(),
        size_t limit = 250, FileFilter filter = FileFilter(),
        FileSortOrder sortOrder = FileSortOrder.pathAscending);
    FilePage listPreviousFilteredFilesPage(string directoryId, FileCursor cursor,
        size_t limit = 250, FileFilter filter = FileFilter(),
        FileSortOrder sortOrder = FileSortOrder.pathAscending);
    void close();
}

/** Source adapter used until the repository backend exposes directory queries. */
final class ProjectedDirectorySource : DirectorySource
{
    private DirectoryTree tree;
    private DirectoryNode[][string] childDirectories;
    private FileNode[][string] filesByDirectory;

    this(DirectoryTree tree)
    {
        this.tree = tree;
        foreach (directory; tree.directories)
            childDirectories[directory.parentId] ~= directory;
        foreach (file; tree.files)
            filesByDirectory[file.directoryId] ~= file;
    }

    override DirectoryNode root() { return tree.root; }

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

    override bool hasMatchingFileInDirectory(string directoryId,
        FileFilter filter = FileFilter())
    {
        foreach (file; filesFor(directoryId))
            if (matchesFileFilter(file, filter))
                return true;
        return false;
    }

    private bool hasMatchingFile(string directoryId, FileFilter filter)
    {
        if (filesFor(directoryId).any!(file => matchesFileFilter(file, filter)))
            return true;
        foreach (child; directoriesFor(directoryId))
            if (hasMatchingFile(child.id, filter))
                return true;
        return false;
    }

    private const(DirectoryNode)[] directoriesFor(string parentId)
    {
        if (auto directories = parentId in childDirectories)
            return *directories;
        return [];
    }

    private const(FileNode)[] filesFor(string directoryId)
    {
        if (auto files = directoryId in filesByDirectory)
            return *files;
        return [];
    }

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

    private FileNode cursorNode(FileCursor cursor)
    {
        FileNode file;
        file.relativePath = cursor.relativePath;
        file.cursorId = cursor.id;
        file.size = cursor.size;
        return file;
    }

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

    override FilePage listFilesPage(string directoryId, FileCursor cursor = FileCursor(),
        size_t limit = 250, string filter = "")
    {
        FileFilter query;
        query.text = filter;
        return listFilteredFilesPage(directoryId, cursor, limit, query,
            FileSortOrder.pathAscending);
    }

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

    override void close() {}
}

/** Build a deterministic tree from source file paths and payload sizes. */
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
    string path;
    ulong size;
    bool hasFileType;
    bool hasMedia;
    bool hasVideo;
    bool hasAudio;
    bool hasImage;
    bool hasText;
    bool hasArchive;
    bool hasTorrent;
    /// Stable source-reference identity; falls back to the input ordinal.
    string id;
}

/** Stable identity for one JSON file reference, independent of filtered order. */
string jsonFileNodeId(size_t sourceOrdinal, size_t referenceOrdinal)
{
    return "file:json:" ~ sourceOrdinal.to!string ~ ":" ~ referenceOrdinal.to!string;
}

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
