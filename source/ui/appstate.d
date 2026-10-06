/** UI state persistence for filters, layout, and startup preferences.
 *
 * This module stores and restores the desktop frontend state in the user's
 * configuration directory so the application can reopen with the last-used
 * layout, document list, and preview settings.
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
    string documentPath;
    string directoryId;
    string relativePath;
    string cursorId;
    ulong size;
}

/** Persisted filter state for one document tab. */
struct DocumentFilterState
{
    string documentPath;
    bool applied;
    string text;
    bool video;
    bool audio;
    bool image;
    bool textStream;
    bool mediaNegated;
    bool fileType;
    bool archive;
    bool torrent;
}

/** Persisted GtkTreeSortable state for a document's Blob table. */
struct TableSortState
{
    string documentPath;
    bool sorted;
    int columnId;
    int order;
}

/** Persisted UI state stored below the user's config directory. */
struct AppState
{
    bool prefAutoApplyFilter = true;
    bool prefCaseSensitiveFilter;
    bool prefDetailsBelow = true;
    bool prefRestoreOpenFiles = true;

    int splitPositionHorizontal = 720;
    int splitPositionVertical = 420;
    int splitPositionPreview = 320;
    bool hasSplitPositionPreview;
    int previewScaleMode;
    string externalOpenProgram = "xdg-open";
    bool previewVideoAutostart;
    double previewVideoVolume = 0.5;

    string[] recentFilePaths;
    int maxRecentFileCount = 10;

    bool hasWindowGeometry;
    int windowX;
    int windowY;
    bool hasWindowSize;
    int windowWidth = 960;
    int windowHeight = 640;
    int windowMonitorIndex = -1;
    string[] openFilePaths;
    string[] expandedTreeStates;
    string[] selectedTreeStates;
    string[] treeSortStates;
    /// Legacy JSON key; values are now selected Directory/Blob notebook pages.
    string[] viewModeStates;
    TableSortState[] tableSortStates;
    TreeCursorState[] treeCursorStates;
    DocumentFilterState[] documentFilterStates;
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

private string jsonObjectString(JSONValue value, string key)
{
    if (value.type != JSONType.object)
        return "";
    if (auto field = key in value.object)
        return field.type == JSONType.string ? field.str : "";
    return "";
}

private ulong jsonToUlong(JSONValue value)
{
    if (value.type == JSONType.uinteger)
        return value.uinteger;
    if (value.type == JSONType.integer && value.integer >= 0)
        return cast(ulong) value.integer;
    return 0;
}

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

/** Escape and serialize a string array as JSON. */
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

AppState loadAppState()
{
    return loadAppStateFromPath(configFilePath());
}

/** Write the current application state to the JSON config file.
 *
 * Params:
 *     state = UI state snapshot to persist.
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
