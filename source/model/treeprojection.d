/** GTK-independent directory tree projection for source adapters. */
module model.treeprojection;

import std.algorithm : any, canFind, filter, sort;
import std.array : array;
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
        auto allFiles = listFiles(directoryId, 0, size_t.max, filter);
        size_t offset;
        if (cursor.id.length > 0)
        {
            foreach (index, file; allFiles)
            {
                if (file.cursorId == cursor.id && file.relativePath == cursor.relativePath)
                {
                    offset = index + 1;
                    break;
                }
            }
        }
        FilePage page;
        auto end = offset + limit;
        if (end > allFiles.length)
            end = allFiles.length;
        page.files = allFiles[offset .. end].dup;
        page.hasMore = end < allFiles.length;
        if (page.hasMore && page.files.length > 0)
        {
            auto last = page.files[$ - 1];
            page.nextCursor = FileCursor(last.relativePath, last.cursorId, last.size);
        }
        return page;
    }

    override FilePage listFilteredFilesPage(string directoryId, FileCursor cursor = FileCursor(),
        size_t limit = 250, FileFilter filter = FileFilter(),
        FileSortOrder sortOrder = FileSortOrder.pathAscending)
    {
        FileNode[] allFiles;
        foreach (file; filesFor(directoryId))
            if (matchesFileFilter(file, filter))
                allFiles ~= file;
        sort!((a, b) {
            final switch (sortOrder)
            {
            case FileSortOrder.pathAscending:
                return a.relativePath < b.relativePath || (a.relativePath == b.relativePath && a.cursorId < b.cursorId);
            case FileSortOrder.pathDescending:
                return a.relativePath > b.relativePath || (a.relativePath == b.relativePath && a.cursorId > b.cursorId);
            case FileSortOrder.sizeAscending:
                return a.size < b.size || (a.size == b.size && a.relativePath < b.relativePath);
            case FileSortOrder.sizeDescending:
                return a.size > b.size || (a.size == b.size && a.relativePath < b.relativePath);
            }
        })(allFiles);
        size_t offset;
        if (cursor.id.length > 0)
            foreach (index, file; allFiles)
                if (file.cursorId == cursor.id && file.relativePath == cursor.relativePath) { offset = index + 1; break; }
        FilePage page;
        auto end = offset + limit;
        if (end > allFiles.length) end = allFiles.length;
        page.files = allFiles[offset .. end].dup;
        page.hasMore = end < allFiles.length;
        if (page.hasMore) { auto last = page.files[$ - 1]; page.nextCursor = FileCursor(last.relativePath, last.cursorId, last.size); }
        return page;
    }

    override FilePage listPreviousFilteredFilesPage(string directoryId, FileCursor cursor,
        size_t limit = 250, FileFilter filter = FileFilter(),
        FileSortOrder sortOrder = FileSortOrder.pathAscending)
    {
        FileNode[] allFiles;
        foreach (file; filesFor(directoryId))
            if (matchesFileFilter(file, filter))
                allFiles ~= file;
        sort!((a, b) {
            final switch (sortOrder)
            {
            case FileSortOrder.pathAscending: return a.relativePath < b.relativePath || (a.relativePath == b.relativePath && a.cursorId < b.cursorId);
            case FileSortOrder.pathDescending: return a.relativePath > b.relativePath || (a.relativePath == b.relativePath && a.cursorId > b.cursorId);
            case FileSortOrder.sizeAscending: return a.size < b.size || (a.size == b.size && a.relativePath < b.relativePath);
            case FileSortOrder.sizeDescending: return a.size > b.size || (a.size == b.size && a.relativePath < b.relativePath);
            }
        })(allFiles);
        size_t cursorIndex;
        foreach (index, file; allFiles)
            if (file.cursorId == cursor.id && file.relativePath == cursor.relativePath) { cursorIndex = index; break; }
        auto start = cursorIndex > limit ? cursorIndex - limit : 0;
        FilePage page;
        page.files = allFiles[start .. cursorIndex].dup;
        page.hasMore = start > 0;
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
        auto fileId = "file:" ~ index.to!string;
        FileNode file;
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
