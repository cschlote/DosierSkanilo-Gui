module ui.appstate;

import std.array : appender;
import std.file : exists, readText, write, mkdirRecurse;
import std.format : format;
import std.json : parseJSON, JSONType, JSONValue;
import std.path : buildPath;
import std.process : environment;

/** Persisted UI state stored below the user's config directory. */
struct AppState
{
    bool prefAutoApplyFilter = true;
    bool prefCaseSensitiveFilter;
    bool prefDetailsBelow;
    bool prefRestoreOpenFiles = true;

    int splitPositionHorizontal = 720;
    int splitPositionVertical = 420;

    bool hasWindowGeometry;
    int windowX;
    int windowY;
    bool hasWindowSize;
    int windowWidth = 960;
    int windowHeight = 640;
    int windowMonitorIndex = -1;
    string[] openFilePaths;
    int activeTabIndex;
}

enum string CONFIG_DIR_NAME = ".config/dosierskanilo-gui";
enum string CONFIG_FILE_NAME = "state.json";

/** Resolve the application config directory. */
string configDirPath()
{
    auto home = environment.get("HOME", "");
    if (home.length == 0)
    {
        return "./" ~ CONFIG_DIR_NAME;
    }
    return buildPath(home, CONFIG_DIR_NAME);
}

/** Resolve the JSON state file path. */
string configFilePath()
{
    return buildPath(configDirPath(), CONFIG_FILE_NAME);
}

/** Convert a JSON scalar into a bool with fallback semantics. */
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

/** Convert a JSON scalar into an int with fallback semantics. */
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

/** Convert a JSON array of strings into a D string array. */
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

/** Escape a string for manual JSON serialization. */
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

/** Load persisted preferences, splitter state, and window geometry hints. */
AppState loadAppState()
{
    AppState state;
    auto path = configFilePath();
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

/** Write the current application state to the JSON config file. */
void saveAppState(const(AppState) state)
{
    auto dirPath = configDirPath();
    auto filePath = configFilePath();
    mkdirRecurse(dirPath);
    auto openFileJson = appender!string();
    openFileJson.put("[");
    foreach (idx, filePathValue; state.openFilePaths)
    {
        if (idx > 0)
        {
            openFileJson.put(", ");
        }
        openFileJson.put("\"");
        openFileJson.put(jsonEscapeString(filePathValue));
        openFileJson.put("\"");
    }
    openFileJson.put("]");

    auto payload = format(
        "{\n" ~
            "  \"prefAutoApplyFilter\": %s,\n" ~
            "  \"prefCaseSensitiveFilter\": %s,\n" ~
            "  \"prefDetailsBelow\": %s,\n" ~
            "  \"prefRestoreOpenFiles\": %s,\n" ~
            "  \"splitPositionHorizontal\": %s,\n" ~
            "  \"splitPositionVertical\": %s,\n" ~
            "  \"hasWindowGeometry\": %s,\n" ~
            "  \"windowX\": %s,\n" ~
            "  \"windowY\": %s,\n" ~
            "  \"hasWindowSize\": %s,\n" ~
            "  \"windowWidth\": %s,\n" ~
            "  \"windowHeight\": %s,\n" ~
            "  \"windowMonitorIndex\": %s,\n" ~
            "  \"openFilePaths\": %s,\n" ~
            "  \"activeTabIndex\": %s\n" ~
            "}\n",
        state.prefAutoApplyFilter ? "true" : "false",
        state.prefCaseSensitiveFilter ? "true" : "false",
        state.prefDetailsBelow ? "true" : "false",
        state.prefRestoreOpenFiles ? "true" : "false",
        state.splitPositionHorizontal,
        state.splitPositionVertical,
        state.hasWindowGeometry ? "true" : "false",
        state.windowX,
        state.windowY,
        state.hasWindowSize ? "true" : "false",
        state.windowWidth,
        state.windowHeight,
        state.windowMonitorIndex,
        openFileJson.data,
        state.activeTabIndex
    );

    write(filePath, payload);
}
