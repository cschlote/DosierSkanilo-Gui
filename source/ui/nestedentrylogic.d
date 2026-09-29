/** GTK-independent paging and activation rules for nested detail entries. */
module ui.nestedentrylogic;

import model.treeprojection : NestedFileNode;
import std.exception : enforce;
import std.format : format;

/** One visible nested-entry page and the continuation position after it. */
struct NestedEntryPage
{
    NestedFileNode[] entries;
    size_t nextOffset;
    bool hasMore;
}

/** Trim the look-ahead entry used to determine whether another page exists. */
NestedEntryPage prepareNestedEntryPage(const(NestedFileNode)[] fetched,
    size_t offset, size_t pageSize = 250)
{
    enforce(pageSize > 0, "Nested entry page size must be greater than zero.");
    NestedEntryPage page;
    auto visibleCount = fetched.length;
    if (visibleCount > pageSize)
    {
        visibleCount = pageSize;
        page.hasMore = true;
    }
    page.entries = fetched[0 .. visibleCount].dup;
    page.nextOffset = offset + visibleCount;
    return page;
}

/** Return the full nested path only for an activatable file row. */
bool nestedEntryCopyPath(string rowKind, string rowPath, out string fullPath)
{
    fullPath = "";
    if (rowKind != "File" || rowPath.length == 0)
        return false;
    fullPath = rowPath;
    return true;
}

@("nested detail paging retains continuation offset and complete copy path")
unittest
{
    NestedFileNode[] fetched;
    foreach (index; 0 .. 251)
    {
        auto path = format("torrent/folder/entry-%03d.txt", index);
        fetched ~= NestedFileNode(path, path, path, index, "");
    }

    auto firstPage = prepareNestedEntryPage(fetched, 0);
    assert(firstPage.entries.length == 250);
    assert(firstPage.hasMore);
    assert(firstPage.nextOffset == 250);

    auto laterPage = prepareNestedEntryPage(fetched[firstPage.nextOffset .. $],
        firstPage.nextOffset);
    assert(laterPage.entries.length == 1);
    assert(!laterPage.hasMore);
    assert(laterPage.nextOffset == 251);

    string copiedPath;
    auto laterPath = laterPage.entries[0].relativePath;
    assert(nestedEntryCopyPath("File", laterPath, copiedPath));
    assert(copiedPath == "torrent/folder/entry-250.txt");
    assert(!nestedEntryCopyPath("Directory", laterPath, copiedPath));
    assert(!nestedEntryCopyPath("File", "", copiedPath));
}
