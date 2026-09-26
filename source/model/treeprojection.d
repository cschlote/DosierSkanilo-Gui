/** GTK-independent directory tree projection for source adapters. */
module model.treeprojection;

import std.algorithm : canFind, count, countUntil, filter;
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
}

struct FilePage
{
    FileNode[] files;
    FileCursor nextCursor;
    bool hasMore;
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
    DirectoryNode[] listDirectories(string parentId);
    FileNode[] listFiles(string directoryId, size_t offset = 0, size_t limit = 250,
        string filter = "");
    FilePage listFilesPage(string directoryId, FileCursor cursor = FileCursor(),
        size_t limit = 250, string filter = "");
    void close();
}

/** Source adapter used until the repository backend exposes directory queries. */
final class ProjectedDirectorySource : DirectorySource
{
    private DirectoryTree tree;

    this(DirectoryTree tree)
    {
        this.tree = tree;
    }

    override DirectoryNode root() { return tree.root; }

    override DirectoryNode[] listDirectories(string parentId)
    {
        return tree.listDirectories(parentId).dup;
    }

    override FileNode[] listFiles(string directoryId, size_t offset = 0, size_t limit = 250,
        string filter = "")
    {
        auto allFiles = tree.listFiles(directoryId);
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
                if (file.id == cursor.id && file.relativePath == cursor.relativePath)
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
            page.nextCursor = FileCursor(last.relativePath, last.id);
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

    foreach (index, input; inputs)
    {
        auto normalized = buildNormalizedPath(input.path);
        auto directoryPath = dirName(normalized);
        if (directoryPath == ".")
            directoryPath = "";

        auto directoryId = ensureDirectory(tree, directoryPath);
        auto fileId = "file:" ~ index.to!string;
        tree.files ~= FileNode(fileId, directoryId, baseName(normalized),
            normalized, input.size);
        addFileToDirectory(tree, directoryId, input.size);
    }

    foreach (ref directory; tree.directories)
    {
        directory.childDirectoryCount = tree.directories.count!(node => node.parentId == directory.id);
        directory.fileCount = tree.files.count!(fileNode => fileNode.directoryId == directory.id);
    }
    return tree;
}

/** Minimal adapter input, intentionally independent from Jsonizer and GTK. */
struct FileInput
{
    string path;
    ulong size;
}

private string ensureDirectory(ref DirectoryTree tree, string path)
{
    if (path.length == 0)
        return "root";

    auto existing = tree.directories.countUntil!(node => node.relativePath == path);
    if (existing >= 0)
        return tree.directories[existing].id;

    auto parentPath = dirName(path);
    if (parentPath == "." || parentPath == path)
        parentPath = "";
    auto parentId = ensureDirectory(tree, parentPath);
    auto id = "directory:" ~ path;
    tree.directories ~= DirectoryNode(id, parentId, baseName(path), path, 0, 0, 0);
    return id;
}

private void addFileToDirectory(ref DirectoryTree tree, string directoryId, ulong size)
{
    auto currentId = directoryId;
    while (currentId.length > 0)
    {
        foreach (ref directory; tree.directories)
        {
            if (directory.id == currentId)
            {
                directory.aggregateSize += size;
                currentId = directory.parentId;
                break;
            }
        }
    }
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
    auto firstPage = source.listFilesPage(album[0].id, FileCursor(), 1);
    assert(firstPage.files.length == 1);
    assert(firstPage.hasMore);
    auto secondPage = source.listFilesPage(album[0].id, firstPage.nextCursor, 1);
    assert(secondPage.files.length == 1);
    assert(!secondPage.hasMore);
}
