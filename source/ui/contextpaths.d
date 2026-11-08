/** Resolve projected file and directory paths for external context actions.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.contextpaths;

import std.path : buildNormalizedPath, dirName, isAbsolute;

import dosierarkivo.archive : parseArchiveVirtualPath;

/** Decode one canonical catalog reference path for filesystem access.
 *
 * Catalog reference paths escape literal exclamation marks as `!!` and use
 * `!/` between archive layers. Opening or previewing a physical file must undo
 * that encoding; otherwise a name such as `clip!.mp4` is probed as
 * `clip!!.mp4` and appears to be missing.
 *
 * Params:
 *     path = Canonical catalog reference path to decode.
 * Returns: The physical filesystem path for a regular entry; the original
 *     `path` for a virtual archive member, an empty string, or a path that
 *     cannot be parsed as an archive virtual path.
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

/** Resolve a source-relative path against its JSON file or repository root.
 *
 * Params:
 *     documentPath = Path of the JSON catalog document that owns the entry.
 *     sourcePath = Source path to resolve; absolute paths are normalized and
 *         returned unchanged in meaning, an empty path stays empty.
 *     repositoryRoot = Optional repository root used instead of the JSON file's
 *         directory as the base for relative paths.
 * Returns: The normalized absolute path when a base is available, otherwise
 *     `sourcePath` unchanged for a relative path with no usable base, or `""`
 *     when `sourcePath` is empty.
 */
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
