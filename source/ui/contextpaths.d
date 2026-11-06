/** Resolve projected file and directory paths for external context actions. */
module ui.contextpaths;

import std.path : buildNormalizedPath, dirName, isAbsolute;

import dosierarkivo.archive : parseArchiveVirtualPath;

/** Decode one canonical catalog reference path for filesystem access.
 *
 * Catalog reference paths escape literal exclamation marks as `!!` and use
 * `!/` between archive layers. Opening or previewing a physical file must undo
 * that encoding; otherwise a name such as `clip!.mp4` is probed as
 * `clip!!.mp4` and appears to be missing.
 */
string decodeCatalogReferencePath(string path)
{
    if (path.length == 0)
        return path;
    try
    {
        const auto parsed = parseArchiveVirtualPath(path);
        /* A virtual member has no standalone filesystem path. Keep the stored
         * identity for the existing archive-member preview paths. */
        return parsed.isVirtual ? path : parsed.physicalPath;
    }
    catch (Exception)
        return path;
}

/** Resolve a source-relative path against its JSON file or repository root. */
string resolveDocumentSourcePath(string documentPath, string sourcePath,
    string repositoryRoot = "")
{
    if (sourcePath.length == 0)
        return "";
    if (sourcePath.isAbsolute)
        return buildNormalizedPath(sourcePath);
    auto basePath = repositoryRoot.length > 0 ? repositoryRoot : dirName(documentPath);
    return basePath.length > 0 ? buildNormalizedPath(basePath, sourcePath) : sourcePath;
}

@("context paths resolve against JSON file and repository roots")
unittest
{
    assert(resolveDocumentSourcePath("/data/catalog.json", "media/track.mp3")
        == "/data/media/track.mp3");
    assert(resolveDocumentSourcePath("/data/library/nested", "media/track.mp3",
        "/data/library") == "/data/library/media/track.mp3");
    assert(resolveDocumentSourcePath("/data/catalog.json", "/shared/track.mp3")
        == "/shared/track.mp3");
    assert(resolveDocumentSourcePath("catalog.json", "track.mp3") == "track.mp3");
    assert(resolveDocumentSourcePath("catalog.json", "") == "");
}

@("catalog reference paths decode escaped exclamation marks")
unittest
{
    assert(decodeCatalogReferencePath("media/clip!!.mp4")
        == "media/clip!.mp4");
    assert(decodeCatalogReferencePath("media!!/clip.mp4")
        == "media!/clip.mp4");
    /* Legacy literal names stay untouched when the grammar does not parse. */
    assert(decodeCatalogReferencePath("media/literal!.mp4")
        == "media/literal!.mp4");
}
