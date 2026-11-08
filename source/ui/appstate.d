/** UI state persistence for filters, layout, and startup preferences.
 *
 * This module stores and restores the desktop frontend state in the user's
 * configuration directory so the application can reopen with the last-used
 * layout, document list, and preview settings.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.appstate;

import std.array : appender;
import std.file : exists, readText, write, mkdirRecurse;
import std.format : format;
import std.json : parseJSON, JSONType, JSONValue;
import std.path : buildPath, dirName;
import std.process : environment;

/** Persisted source cursor for a document's selected TreeView file. */
struct TreeCursorState
{
    /// Document tab path that owns this cursor.
    string documentPath;
    /// Directory ID of the tree node that contains the selected file.
    string directoryId;
    /// File path relative to the document root.
    string relativePath;
    /// Opaque file cursor ID returned by the directory source.
    string cursorId;
    /// Size of the selected file in bytes.
    ulong size;
}

/** Persisted filter state for one document tab. */
struct DocumentFilterState
{
    /// Document tab path this filter state belongs to.
    string documentPath;
    /// Whether the filter was applied when the state was saved.
    bool applied;
    /// Case-insensitive or case-sensitive path text filter.
    string text;
    /// Whether video files are selected.
    bool video;
    /// Whether audio files are selected.
    bool audio;
    /// Whether image files are selected.
    bool image;
    /// Whether text/subtitle streams are selected.
    bool textStream;
    /// Invert the combined media selection.
    bool mediaNegated;
    /// Whether file type metadata is required.
    bool fileType;
    /// Whether archive metadata is required.
    bool archive;
    /// Whether torrent metadata is required.
    bool torrent;
}

/** Persisted GtkTreeSortable state for a document's Blob table. */
struct TableSortState
{
    /// Document tab path this table sort state belongs to.
    string documentPath;
    /// Whether table sorting is active.
    bool sorted;
    /// Identifier of the sorted table column.
    int columnId;
    /// GTK sort order value (ascending or descending).
    int order;
}

/** Persisted UI state stored below the user's config directory. */
struct AppState
{
    /// Whether filters are applied automatically without pressing Apply.
    bool prefAutoApplyFilter = true;
    /// Whether filter text matching is case sensitive.
    bool prefCaseSensitiveFilter;
    /// Whether the details pane is placed below rather than beside the list.
    bool prefDetailsBelow = true;
    /// Whether previously open document tabs are restored at startup.
    bool prefRestoreOpenFiles = true;

    /// Pixel position of the main horizontal splitter.
    int splitPositionHorizontal = 720;
    /// Pixel position of the main vertical splitter used when details are below.
    int splitPositionVertical = 420;
    /// Pixel position of the preview/details splitter.
    int splitPositionPreview = 320;
    /// Whether `splitPositionPreview` contains a saved position.
    bool hasSplitPositionPreview;
    /// Integer value of the persisted preview scale mode.
    int previewScaleMode;
    /// Command used to open files in an external application.
    string externalOpenProgram = "xdg-open";
    /// Whether preview videos start playing automatically.
    bool previewVideoAutostart;
    /// Preview video volume as a fraction between 0.0 and 1.0.
    double previewVideoVolume = 0.5;
    /// Archive member cache root; empty selects the system temporary directory.
    string archiveCacheDirectory;
    /// Archive member cache size limit in mebibytes.
    int archiveCacheSizeMiB = 1024;

    /// Most-recently-used document paths, newest first.
    string[] recentFilePaths;
    /// Maximum number of entries kept in `recentFilePaths`.
    int maxRecentFileCount = 10;

    /// Whether `windowX` and `windowY` contain a saved position.
    bool hasWindowGeometry;
    /// Saved window X coordinate in screen pixels.
    int windowX;
    /// Saved window Y coordinate in screen pixels.
    int windowY;
    /// Whether `windowWidth` and `windowHeight` contain a saved size.
    bool hasWindowSize;
    /// Saved window width in pixels.
    int windowWidth = 960;
    /// Saved window height in pixels.
    int windowHeight = 640;
    /// Saved monitor index, or `-1` when no monitor preference is stored.
    int windowMonitorIndex = -1;
    /// Paths of document tabs that were open when the state was saved.
    string[] openFilePaths;
    /// Encoded expanded tree entries as `documentPath\tdirectoryId`.
    string[] expandedTreeStates;
    /// Encoded selected tree entries as `documentPath\tfileId`.
    string[] selectedTreeStates;
    /// Encoded tree sort entries as `documentPath\tsortOrder`.
    string[] treeSortStates;
    /// Legacy JSON key; values are now selected Directory/Blob notebook pages.
    string[] viewModeStates;
    /// Per-document table sort states.
    TableSortState[] tableSortStates;
    /// Per-document tree cursor states.
    TreeCursorState[] treeCursorStates;
    /// Per-document filter states.
    DocumentFilterState[] documentFilterStates;
    /// Index of the selected document notebook page.
    int activeTabIndex;
}

/** Relative directory below $HOME that stores the persisted UI state. */
enum string CONFIG_DIR_NAME = ".config/dosierskanilo-gui";
/** File name used for the persisted UI state JSON document. */
enum string CONFIG_FILE_NAME = "state.json";

/** Resolve the application config directory.
 *
 * Returns: Absolute config directory path when $HOME is available, or a
 *     relative fallback below the current working directory otherwise.
 * Throws: None.
 */
string configDirPath()
{
    return resolveConfigDirPath(environment.get("HOME", ""));
}

/** Resolve the config directory from an explicit home directory.
 *
 * Params:
 *     home = Home directory path; empty selects a working-directory fallback.
 * Returns: `$HOME`-based config directory, or `./.config/...` when `home` is
 *     empty.
 */
private string resolveConfigDirPath(string home)
{
    if (home.length == 0)
    {
        return "./" ~ CONFIG_DIR_NAME;
    }
    return buildPath(home, CONFIG_DIR_NAME);
}

/** Resolve the JSON state file path.
 *
 * Returns: Full path to the JSON state file inside the application config
 *     directory.
 * Throws: None.
 */
string configFilePath()
{
    return resolveConfigFilePath(environment.get("HOME", ""));
}

/** Resolve the JSON state file path from an explicit home directory.
 *
 * Params:
 *     home = Home directory path; empty selects a working-directory fallback.
 * Returns: Path to `state.json` inside the resolved config directory.
 */
private string resolveConfigFilePath(string home)
{
    return buildPath(resolveConfigDirPath(home), CONFIG_FILE_NAME);
}

/** Convert a JSON scalar into a bool with fallback semantics.
 *
 * Params:
 *     value = JSON scalar to read.
 *     fallback = Value to return when the JSON node is not a supported
 *         boolean-like scalar.
 * Returns: Parsed boolean value or the provided fallback.
 * Throws: None.
 */
bool jsonToBool(JSONValue value, bool fallback = false)
{
    switch (value.type)
    {
    case JSONType.true_:
        return true;
    case JSONType.false_:
        return false;
    case JSONType.integer:
        return value.integer != 0;
    case JSONType.uinteger:
        return value.uinteger != 0;
    default:
        return fallback;
    }
}

/** Convert a JSON scalar into an int with fallback semantics.
 *
 * Params:
 *     value = JSON scalar to read.
 *     fallback = Value to return when the JSON node is not a supported
 *         integer-like scalar.
 * Returns: Parsed integer value or the provided fallback.
 * Throws: None.
 */
int jsonToInt(JSONValue value, int fallback = 0)
{
    switch (value.type)
    {
    case JSONType.integer:
        return cast(int) value.integer;
    case JSONType.uinteger:
        return cast(int) value.uinteger;
    case JSONType.float_:
        return cast(int) value.floating;
    default:
        return fallback;
    }
}

/** Convert a JSON array of strings into a D string array.
 *
 * Params:
 *     value = JSON node to read.
 * Returns: All string entries stored in the array, or an empty array when the
 *     value is not a JSON array.
 * Throws: None.
 */
string[] jsonToStringArray(JSONValue value)
{
    string[] result;
    if (value.type != JSONType.array)
    {
        return result;
    }

    foreach (entry; value.array)
    {
        if (entry.type == JSONType.string)
        {
            result ~= entry.str;
        }
    }
    return result;
}

/** Read one string property from a JSON object.
 *
 * Params:
 *     value = JSON node expected to be an object.
 *     key = Property name to read.
 * Returns: The string value, or an empty string when `value` is not an object,
 *     the key is absent, or the property is not a string.
 */
private string jsonObjectString(JSONValue value, string key)
{
    if (value.type != JSONType.object)
        return "";
    if (auto field = key in value.object)
        return field.type == JSONType.string ? field.str : "";
    return "";
}

/** Convert a JSON non-negative integer into a `ulong`.
 *
 * Params:
 *     value = JSON scalar to read.
 * Returns: The stored unsigned value, a non-negative signed value, or `0` for
 *     negative integers and non-integer nodes.
 */
private ulong jsonToUlong(JSONValue value)
{
    if (value.type == JSONType.uinteger)
        return value.uinteger;
    if (value.type == JSONType.integer && value.integer >= 0)
        return cast(ulong) value.integer;
    return 0;
}

/** Parse persisted tree cursor entries from a JSON array.
 *
 * Entries are skipped when they are not objects or when either their document
 * path or their cursor ID is empty.
 *
 * Params:
 *     value = JSON node expected to be an array of cursor objects.
 * Returns: One state per valid entry, or an empty array when `value` is not an
 *     array.
 */
private TreeCursorState[] jsonToTreeCursorStates(JSONValue value)
{
    TreeCursorState[] result;
    if (value.type != JSONType.array)
        return result;
    foreach (entry; value.array)
    {
        if (entry.type != JSONType.object)
            continue;
        TreeCursorState state;
        state.documentPath = jsonObjectString(entry, "documentPath");
        state.directoryId = jsonObjectString(entry, "directoryId");
        state.relativePath = jsonObjectString(entry, "relativePath");
        state.cursorId = jsonObjectString(entry, "cursorId");
        if (auto size = "size" in entry.object)
            state.size = jsonToUlong(*size);
        if (state.documentPath.length > 0 && state.cursorId.length > 0)
            result ~= state;
    }
    return result;
}

/** Parse persisted document filter entries from a JSON array.
 *
 * Entries are skipped when they are not objects or have an empty document
 * path. Missing properties keep their default (false/empty) values.
 *
 * Params:
 *     value = JSON node expected to be an array of filter objects.
 * Returns: One state per valid entry, or an empty array when `value` is not an
 *     array.
 */
private DocumentFilterState[] jsonToDocumentFilterStates(JSONValue value)
{
    DocumentFilterState[] result;
    if (value.type != JSONType.array)
        return result;
    foreach (entry; value.array)
    {
        if (entry.type != JSONType.object)
            continue;
        DocumentFilterState state;
        state.documentPath = jsonObjectString(entry, "documentPath");
        if (auto field = "applied" in entry.object) state.applied = jsonToBool(*field);
        state.text = jsonObjectString(entry, "text");
        if (auto field = "video" in entry.object) state.video = jsonToBool(*field);
        if (auto field = "audio" in entry.object) state.audio = jsonToBool(*field);
        if (auto field = "image" in entry.object) state.image = jsonToBool(*field);
        if (auto field = "textStream" in entry.object) state.textStream = jsonToBool(*field);
        if (auto field = "mediaNegated" in entry.object) state.mediaNegated = jsonToBool(*field);
        if (auto field = "fileType" in entry.object) state.fileType = jsonToBool(*field);
        if (auto field = "archive" in entry.object) state.archive = jsonToBool(*field);
        if (auto field = "torrent" in entry.object) state.torrent = jsonToBool(*field);
        if (state.documentPath.length > 0)
            result ~= state;
    }
    return result;
}

/** Parse persisted table sort entries from a JSON array.
 *
 * Entries are skipped when they are not objects or have an empty document
 * path. Invalid `columnId` values fall back to `-1`.
 *
 * Params:
 *     value = JSON node expected to be an array of table sort objects.
 * Returns: One state per valid entry, or an empty array when `value` is not an
 *     array.
 */
private TableSortState[] jsonToTableSortStates(JSONValue value)
{
    TableSortState[] result;
    if (value.type != JSONType.array)
        return result;
    foreach (entry; value.array)
    {
        if (entry.type != JSONType.object)
            continue;
        TableSortState state;
        state.documentPath = jsonObjectString(entry, "documentPath");
        if (auto field = "sorted" in entry.object) state.sorted = jsonToBool(*field);
        if (auto field = "columnId" in entry.object) state.columnId = jsonToInt(*field, -1);
        if (auto field = "order" in entry.object) state.order = jsonToInt(*field);
        if (state.documentPath.length > 0)
            result ~= state;
    }
    return result;
}

/** Serialize tree cursor states as a compact JSON array string.
 *
 * Params:
 *     states = Cursor states to encode.
 * Returns: JSON array text containing all fields of every state.
 */
private string jsonTreeCursorStates(const(TreeCursorState)[] states)
{
    JSONValue[] entries;
    foreach (state; states)
    {
        JSONValue[string] entry;
        entry["documentPath"] = JSONValue(state.documentPath);
        entry["directoryId"] = JSONValue(state.directoryId);
        entry["relativePath"] = JSONValue(state.relativePath);
        entry["cursorId"] = JSONValue(state.cursorId);
        entry["size"] = JSONValue(state.size);
        entries ~= JSONValue(entry);
    }
    return JSONValue(entries).toString;
}

/** Serialize document filter states as a compact JSON array string.
 *
 * Params:
 *     states = Filter states to encode.
 * Returns: JSON array text containing all fields of every state.
 */
private string jsonDocumentFilterStates(const(DocumentFilterState)[] states)
{
    JSONValue[] entries;
    foreach (state; states)
    {
        JSONValue[string] entry;
        entry["documentPath"] = JSONValue(state.documentPath);
        entry["applied"] = JSONValue(state.applied);
        entry["text"] = JSONValue(state.text);
        entry["video"] = JSONValue(state.video);
        entry["audio"] = JSONValue(state.audio);
        entry["image"] = JSONValue(state.image);
        entry["textStream"] = JSONValue(state.textStream);
        entry["mediaNegated"] = JSONValue(state.mediaNegated);
        entry["fileType"] = JSONValue(state.fileType);
        entry["archive"] = JSONValue(state.archive);
        entry["torrent"] = JSONValue(state.torrent);
        entries ~= JSONValue(entry);
    }
    return JSONValue(entries).toString;
}

/** Serialize table sort states as a compact JSON array string.
 *
 * Params:
 *     states = Table sort states to encode.
 * Returns: JSON array text containing all fields of every state.
 */
private string jsonTableSortStates(const(TableSortState)[] states)
{
    JSONValue[] entries;
    foreach (state; states)
    {
        JSONValue[string] entry;
        entry["documentPath"] = JSONValue(state.documentPath);
        entry["sorted"] = JSONValue(state.sorted);
        entry["columnId"] = JSONValue(state.columnId);
        entry["order"] = JSONValue(state.order);
        entries ~= JSONValue(entry);
    }
    return JSONValue(entries).toString;
}

/** Escape and serialize a string array as JSON.
 *
 * Params:
 *     values = Strings to encode.
 * Returns: JSON array text with quoted and escaped entries; an empty input
 *     yields `[]`.
 */
string jsonStringArray(const(string)[] values)
{
    auto result = appender!string();
    result.put("[");
    foreach (idx, value; values)
    {
        if (idx > 0)
        {
            result.put(", ");
        }
        result.put("\"");
        result.put(jsonEscapeString(value));
        result.put("\"");
    }
    result.put("]");
    return result.data;
}

/** Escape a string for manual JSON serialization.
 *
 * Params:
 *     value = Raw text to encode for JSON output.
 * Returns: JSON-safe string content without surrounding quotes.
 * Throws: None.
 */
string jsonEscapeString(string value)
{
    auto escaped = appender!string();
    foreach (ch; value)
    {
        switch (ch)
        {
        case '"':
            escaped.put("\\\"");
            break;
        case '\\':
            escaped.put("\\\\");
            break;
        case '\b':
            escaped.put("\\b");
            break;
        case '\f':
            escaped.put("\\f");
            break;
        case '\n':
            escaped.put("\\n");
            break;
        case '\r':
            escaped.put("\\r");
            break;
        case '\t':
            escaped.put("\\t");
            break;
        default:
            if (ch < 0x20)
            {
                escaped.put(format("\\u%04x", ch));
            }
            else
            {
                escaped.put(cast(char) ch);
            }
            break;
        }
    }
    return escaped.data;
}

/** Load persisted preferences, splitter state, and window geometry hints.
 *
 * Params:
 *     path = JSON state file to read; a missing file yields defaults.
 * Returns: The stored UI state, or the default state when no readable state
 *     file is available.
 * Throws: Invalid, unreadable, or malformed state files are swallowed and
 *     replaced with defaults; only unexpected runtime failures may escape.
 */
private AppState loadAppStateFromPath(string path)
{
    AppState state;
    if (!exists(path))
    {
        return state;
    }

    try
    {
        auto parsed = parseJSON(readText(path));
        if (parsed.type != JSONType.object)
        {
            return state;
        }

        auto root = parsed.object;
        if (auto value = "prefAutoApplyFilter" in root)
        {
            state.prefAutoApplyFilter = jsonToBool(*value, state.prefAutoApplyFilter);
        }
        if (auto value = "prefCaseSensitiveFilter" in root)
        {
            state.prefCaseSensitiveFilter = jsonToBool(*value, state.prefCaseSensitiveFilter);
        }
        if (auto value = "prefDetailsBelow" in root)
        {
            state.prefDetailsBelow = jsonToBool(*value, state.prefDetailsBelow);
        }
        if (auto value = "prefRestoreOpenFiles" in root)
        {
            state.prefRestoreOpenFiles = jsonToBool(*value, state.prefRestoreOpenFiles);
        }

        if (auto value = "splitPositionHorizontal" in root)
        {
            state.splitPositionHorizontal = jsonToInt(*value, state.splitPositionHorizontal);
        }
        if (auto value = "splitPositionVertical" in root)
        {
            state.splitPositionVertical = jsonToInt(*value, state.splitPositionVertical);
        }
        if (auto value = "splitPositionPreview" in root)
        {
            state.splitPositionPreview = jsonToInt(*value, state.splitPositionPreview);
            state.hasSplitPositionPreview = true;
        }
        if (auto value = "previewScaleMode" in root)
        {
            state.previewScaleMode = jsonToInt(*value, state.previewScaleMode);
        }
        if (auto value = "externalOpenProgram" in root)
        {
            if (value.type == JSONType.string)
            {
                state.externalOpenProgram = value.str;
            }
        }
        if (auto value = "archiveCacheDirectory" in root)
        {
            if (value.type == JSONType.string)
            {
                state.archiveCacheDirectory = value.str;
            }
        }
        if (auto value = "archiveCacheSizeMiB" in root)
        {
            state.archiveCacheSizeMiB = jsonToInt(*value,
                state.archiveCacheSizeMiB);
        }
        if (auto value = "previewVideoAutostart" in root)
        {
            state.previewVideoAutostart = jsonToBool(*value, state.previewVideoAutostart);
        }
        if (auto value = "previewVideoVolume" in root)
        {
            if (value.type == JSONType.float_ || value.type == JSONType.integer || value.type == JSONType.uinteger)
            {
                state.previewVideoVolume = value.type == JSONType.float_ ? value.floating : cast(double) jsonToInt(*value, cast(int) (state.previewVideoVolume * 1000)) / 1000.0;
            }
        }
        if (auto value = "recentFilePaths" in root)
        {
            state.recentFilePaths = jsonToStringArray(*value);
        }
        if (auto value = "maxRecentFileCount" in root)
        {
            state.maxRecentFileCount = jsonToInt(*value, state.maxRecentFileCount);
        }

        if (auto value = "hasWindowGeometry" in root)
        {
            state.hasWindowGeometry = jsonToBool(*value, state.hasWindowGeometry);
        }
        if (auto value = "windowX" in root)
        {
            state.windowX = jsonToInt(*value, state.windowX);
        }
        if (auto value = "windowY" in root)
        {
            state.windowY = jsonToInt(*value, state.windowY);
        }
        if (auto value = "windowWidth" in root)
        {
            state.windowWidth = jsonToInt(*value, state.windowWidth);
        }
        if (auto value = "windowHeight" in root)
        {
            state.windowHeight = jsonToInt(*value, state.windowHeight);
        }
        if (auto value = "hasWindowSize" in root)
        {
            state.hasWindowSize = jsonToBool(*value, state.hasWindowSize);
        }
        if (auto value = "windowMonitorIndex" in root)
        {
            state.windowMonitorIndex = jsonToInt(*value, state.windowMonitorIndex);
        }
        if (auto value = "openFilePaths" in root)
        {
            state.openFilePaths = jsonToStringArray(*value);
        }
        if (auto value = "expandedTreeStates" in root)
        {
            state.expandedTreeStates = jsonToStringArray(*value);
        }
        if (auto value = "selectedTreeStates" in root)
        {
            state.selectedTreeStates = jsonToStringArray(*value);
        }
        if (auto value = "treeSortStates" in root)
        {
            state.treeSortStates = jsonToStringArray(*value);
        }
        if (auto value = "viewModeStates" in root)
        {
            state.viewModeStates = jsonToStringArray(*value);
        }
        if (auto value = "tableSortStates" in root)
            state.tableSortStates = jsonToTableSortStates(*value);
        if (auto value = "treeCursorStates" in root)
        {
            state.treeCursorStates = jsonToTreeCursorStates(*value);
        }
        if (auto value = "documentFilterStates" in root)
        {
            state.documentFilterStates = jsonToDocumentFilterStates(*value);
        }
        if (auto value = "activeTabIndex" in root)
        {
            state.activeTabIndex = jsonToInt(*value, state.activeTabIndex);
        }
    }
    catch (Exception)
    {
        // Keep defaults on invalid state file.
    }

    return state;
}

/** Load the persisted UI state from the default config file.
 *
 * Returns: The stored state, or a default-initialized `AppState` when the file
 *     is missing, unreadable, or malformed.
 * Throws: Only unexpected runtime failures may escape; parse and file-read
 *     errors are swallowed.
 */
AppState loadAppState()
{
    return loadAppStateFromPath(configFilePath());
}

/** Write an application state snapshot to a JSON file.
 *
 * Params:
 *     state = UI state snapshot to persist.
 *     path = Destination JSON file; its parent directory is created when
 *         needed.
 * Returns: Nothing.
 * Throws: File system errors from directory creation or writing are propagated.
 */
private void saveAppStateToPath(const(AppState) state, string path)
{
    auto dirPath = dirName(path);
    mkdirRecurse(dirPath);
    auto openFileJson = jsonStringArray(state.openFilePaths);
    auto recentFileJson = jsonStringArray(state.recentFilePaths);

    auto payload = format(
        "{\n" ~
            "  \"prefAutoApplyFilter\": %s,\n" ~
            "  \"prefCaseSensitiveFilter\": %s,\n" ~
            "  \"prefDetailsBelow\": %s,\n" ~
            "  \"prefRestoreOpenFiles\": %s,\n" ~
            "  \"splitPositionHorizontal\": %s,\n" ~
            "  \"splitPositionVertical\": %s,\n" ~
            "  \"splitPositionPreview\": %s,\n" ~
            "  \"hasSplitPositionPreview\": %s,\n" ~
            "  \"previewScaleMode\": %s,\n" ~
            "  \"externalOpenProgram\": \"%s\",\n" ~
            "  \"previewVideoAutostart\": %s,\n" ~
            "  \"previewVideoVolume\": %s,\n" ~
            "  \"archiveCacheDirectory\": \"%s\",\n" ~
            "  \"archiveCacheSizeMiB\": %s,\n" ~
            "  \"recentFilePaths\": %s,\n" ~
            "  \"maxRecentFileCount\": %s,\n" ~
            "  \"hasWindowGeometry\": %s,\n" ~
            "  \"windowX\": %s,\n" ~
            "  \"windowY\": %s,\n" ~
            "  \"hasWindowSize\": %s,\n" ~
            "  \"windowWidth\": %s,\n" ~
            "  \"windowHeight\": %s,\n" ~
            "  \"windowMonitorIndex\": %s,\n" ~
            "  \"openFilePaths\": %s,\n" ~
            "  \"expandedTreeStates\": %s,\n" ~
            "  \"selectedTreeStates\": %s,\n" ~
            "  \"treeSortStates\": %s,\n" ~
            "  \"viewModeStates\": %s,\n" ~
            "  \"tableSortStates\": %s,\n" ~
            "  \"treeCursorStates\": %s,\n" ~
            "  \"documentFilterStates\": %s,\n" ~
            "  \"activeTabIndex\": %s\n" ~
            "}\n",
        state.prefAutoApplyFilter ? "true" : "false",
        state.prefCaseSensitiveFilter ? "true" : "false",
        state.prefDetailsBelow ? "true" : "false",
        state.prefRestoreOpenFiles ? "true" : "false",
        state.splitPositionHorizontal,
        state.splitPositionVertical,
        state.splitPositionPreview,
        state.hasSplitPositionPreview ? "true" : "false",
        state.previewScaleMode,
        jsonEscapeString(state.externalOpenProgram),
        state.previewVideoAutostart ? "true" : "false",
        state.previewVideoVolume,
        jsonEscapeString(state.archiveCacheDirectory),
        state.archiveCacheSizeMiB,
        recentFileJson,
        state.maxRecentFileCount,
        state.hasWindowGeometry ? "true" : "false",
        state.windowX,
        state.windowY,
        state.hasWindowSize ? "true" : "false",
        state.windowWidth,
        state.windowHeight,
        state.windowMonitorIndex,
        openFileJson,
        jsonStringArray(state.expandedTreeStates),
        jsonStringArray(state.selectedTreeStates),
        jsonStringArray(state.treeSortStates),
        jsonStringArray(state.viewModeStates),
        jsonTableSortStates(state.tableSortStates),
        jsonTreeCursorStates(state.treeCursorStates),
        jsonDocumentFilterStates(state.documentFilterStates),
        state.activeTabIndex
    );

    write(path, payload);
}

/** Save the current UI state to the default config file.
 *
 * Params:
 *     state = UI state snapshot to persist.
 * Throws: File system errors from directory creation or writing are
 *     propagated.
 */
void saveAppState(const(AppState) state)
{
    saveAppStateToPath(state, configFilePath());
}

@("AppState JSON conversion helpers")
unittest
{
    assert(jsonToBool(JSONValue(true)));
    assert(!jsonToBool(JSONValue(false)));
    assert(jsonToBool(JSONValue(1)));
    assert(!jsonToBool(JSONValue(0)));
    assert(jsonToBool(JSONValue(7u)));
    assert(jsonToBool(JSONValue("ignored"), true));

    assert(jsonToInt(JSONValue(12)) == 12);
    assert(jsonToInt(JSONValue(12u)) == 12);
    assert(jsonToInt(JSONValue(12.75)) == 12);
    assert(jsonToInt(JSONValue("ignored"), 99) == 99);

    auto strings = JSONValue([JSONValue("alpha"), JSONValue(1), JSONValue("beta")]);
    auto stringArray = jsonToStringArray(strings);
    assert(stringArray == ["alpha", "beta"]);
    assert(jsonToStringArray(JSONValue(1)).length == 0);

    assert(jsonEscapeString("a\"b\\c\n") == "a\\\"b\\\\c\\n");
    assert(AppState.init.prefDetailsBelow);
    assert(resolveConfigDirPath("") == "./" ~ CONFIG_DIR_NAME);
    assert(resolveConfigDirPath("/tmp/dosierskanilo-gui-ui-tests")
        == buildPath("/tmp/dosierskanilo-gui-ui-tests", CONFIG_DIR_NAME));
    assert(resolveConfigFilePath("/tmp/dosierskanilo-gui-ui-tests")
        == buildPath("/tmp/dosierskanilo-gui-ui-tests", CONFIG_DIR_NAME, CONFIG_FILE_NAME));
}

@("AppState save/load roundtrip")
unittest
{
    auto testStateFile = "/tmp/dosierskanilo-gui-ui-tests-roundtrip/.config/dosierskanilo-gui/state.json";
    mkdirRecurse(dirName(testStateFile));

    AppState expected;
    expected.prefAutoApplyFilter = false;
    expected.prefCaseSensitiveFilter = true;
    expected.prefDetailsBelow = true;
    expected.prefRestoreOpenFiles = false;
    expected.splitPositionHorizontal = 111;
    expected.splitPositionVertical = 222;
    expected.splitPositionPreview = 333;
    expected.hasSplitPositionPreview = true;
    expected.previewScaleMode = 4;
    expected.externalOpenProgram = "custom tool";
    expected.previewVideoAutostart = true;
    expected.previewVideoVolume = 0.75;
    expected.archiveCacheDirectory = "/tmp/archive cache";
    expected.archiveCacheSizeMiB = 512;
    expected.recentFilePaths = ["/tmp/one.json", "/tmp/two path.json"];
    expected.maxRecentFileCount = 12;
    expected.hasWindowGeometry = true;
    expected.windowX = 12;
    expected.windowY = 34;
    expected.hasWindowSize = true;
    expected.windowWidth = 800;
    expected.windowHeight = 600;
    expected.windowMonitorIndex = 2;
    expected.openFilePaths = ["one.json", "two path.json"];
    expected.expandedTreeStates = ["one.json\troot", "one.json\tdirectory:music"];
    expected.selectedTreeStates = ["one.json\tfile:7"];
    expected.treeSortStates = ["one.json\t2"];
    expected.viewModeStates = ["one.json\t1"];
    expected.tableSortStates = [TableSortState("one.json", true, 8, 1)];
    expected.treeCursorStates = [TreeCursorState("one\tpath.json", "directory:audio",
        "audio/track.flac", "file-ref-17", 123_456_789)];
    expected.documentFilterStates = [DocumentFilterState("one\tpath.json",
        true, "audio/track", true, false, true, true, true, false, true, false)];
    expected.activeTabIndex = 7;

    saveAppStateToPath(expected, testStateFile);
    auto loaded = loadAppStateFromPath(testStateFile);

    assert(loaded.prefAutoApplyFilter == expected.prefAutoApplyFilter);
    assert(loaded.prefCaseSensitiveFilter == expected.prefCaseSensitiveFilter);
    assert(loaded.prefDetailsBelow == expected.prefDetailsBelow);
    assert(loaded.prefRestoreOpenFiles == expected.prefRestoreOpenFiles);
    assert(loaded.splitPositionHorizontal == expected.splitPositionHorizontal);
    assert(loaded.splitPositionVertical == expected.splitPositionVertical);
    assert(loaded.splitPositionPreview == expected.splitPositionPreview);
    assert(loaded.hasSplitPositionPreview == expected.hasSplitPositionPreview);
    assert(loaded.previewScaleMode == expected.previewScaleMode);
    assert(loaded.externalOpenProgram == expected.externalOpenProgram);
    assert(loaded.previewVideoAutostart == expected.previewVideoAutostart);
    assert(loaded.previewVideoVolume == expected.previewVideoVolume);
    assert(loaded.archiveCacheDirectory == expected.archiveCacheDirectory);
    assert(loaded.archiveCacheSizeMiB == expected.archiveCacheSizeMiB);
    assert(loaded.recentFilePaths == expected.recentFilePaths);
    assert(loaded.maxRecentFileCount == expected.maxRecentFileCount);
    assert(loaded.hasWindowGeometry == expected.hasWindowGeometry);
    assert(loaded.windowX == expected.windowX);
    assert(loaded.windowY == expected.windowY);
    assert(loaded.hasWindowSize == expected.hasWindowSize);
    assert(loaded.windowWidth == expected.windowWidth);
    assert(loaded.windowHeight == expected.windowHeight);
    assert(loaded.windowMonitorIndex == expected.windowMonitorIndex);
    assert(loaded.openFilePaths == expected.openFilePaths);
    assert(loaded.expandedTreeStates == expected.expandedTreeStates);
    assert(loaded.selectedTreeStates == expected.selectedTreeStates);
    assert(loaded.treeSortStates == expected.treeSortStates);
    assert(loaded.viewModeStates == expected.viewModeStates);
    assert(loaded.tableSortStates.length == 1);
    assert(loaded.tableSortStates[0].documentPath == "one.json");
    assert(loaded.tableSortStates[0].sorted);
    assert(loaded.tableSortStates[0].columnId == 8);
    assert(loaded.tableSortStates[0].order == 1);
    assert(loaded.treeCursorStates.length == 1);
    assert(loaded.treeCursorStates[0].documentPath == "one\tpath.json");
    assert(loaded.treeCursorStates[0].directoryId == "directory:audio");
    assert(loaded.treeCursorStates[0].relativePath == "audio/track.flac");
    assert(loaded.treeCursorStates[0].cursorId == "file-ref-17");
    assert(loaded.treeCursorStates[0].size == 123_456_789);
    assert(loaded.documentFilterStates.length == 1);
    assert(loaded.documentFilterStates[0].documentPath == "one\tpath.json");
    assert(loaded.documentFilterStates[0].applied);
    assert(loaded.documentFilterStates[0].text == "audio/track");
    assert(loaded.documentFilterStates[0].video);
    assert(!loaded.documentFilterStates[0].audio);
    assert(loaded.documentFilterStates[0].image);
    assert(loaded.documentFilterStates[0].textStream);
    assert(loaded.documentFilterStates[0].mediaNegated);
    assert(!loaded.documentFilterStates[0].fileType);
    assert(loaded.documentFilterStates[0].archive);
    assert(!loaded.documentFilterStates[0].torrent);
    assert(loaded.activeTabIndex == expected.activeTabIndex);
}
