/** Command line options and parsing helpers for DosierSkanilo GUI. */
module cli.commandline;

import std.getopt : getopt, config;

enum string DEFAULT_JSON_PATH = "./.filescanner.json";

/** Parsed startup options from command-line arguments. */
struct CliOptions
{
    string jsonPath = DEFAULT_JSON_PATH;
    bool jsonPathProvided;
    bool loadOnStart;
    string filterOnStart;
    bool caseSensitiveFilter;
    bool disableAutoFilter;
    bool showHelp;
}

/** Return human-readable CLI usage text. */
string cliUsageText()
{
    return "DosierSkanilo GUI\n" ~
        "\n" ~
        "Usage:\n" ~
        "  dosierskanilo-gui [options]\n" ~
        "\n" ~
        "Options:\n" ~
        "  -j, --json <file>         JSON file to open\n" ~
        "  -l, --load                Load on startup\n" ~
        "  -q, --query <text>        Apply initial text filter\n" ~
        "      --case-sensitive      Use case-sensitive text filtering\n" ~
        "      --no-auto-filter      Disable auto filter after load\n" ~
        "  -h, --help                Show this help text\n";
}

/** Parse CLI arguments into startup option flags.
 *
 * Params:
 *   args = command-line argument array (in/out for getopt)
 * Returns:
 *   Parsed options with defaults applied
 */
CliOptions parseCliOptions(ref string[] args)
{
    CliOptions opts;

    getopt(
        args,
        config.passThrough,
        "j|json", &opts.jsonPath,
        "l|load", &opts.loadOnStart,
        "q|query", &opts.filterOnStart,
        "case-sensitive", &opts.caseSensitiveFilter,
        "no-auto-filter", &opts.disableAutoFilter,
        "h|help", &opts.showHelp
    );

    opts.jsonPathProvided = opts.jsonPath != DEFAULT_JSON_PATH;
    if (opts.jsonPathProvided)
    {
        opts.loadOnStart = true;
    }

    return opts;
}
