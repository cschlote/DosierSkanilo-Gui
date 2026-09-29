/** Resolve projected file and directory paths for external context actions. */
module ui.contextpaths;

import std.path : buildNormalizedPath, dirName, isAbsolute;

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
