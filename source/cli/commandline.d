/** Command line options and parsing helpers for DosierSkanilo GUI.
 *
 * This module contains code to parse command-line arguments into a structured `CliOptions` type, as well
 * as a function to generate usage text for the user. The GUI entry point in `app.d` calls `parseCliOptions`
 * to determine startup behavior based on the provided arguments.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
 * License: CC-BY-NC-SA 4.0
 */
module cli.commandline;

import std.getopt : getopt, config;

enum string DEFAULT_JSON_PATH = "./.dosierskanilo.json";

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
immutable string cliUsageText = q{
DosierSkanilo GUI

This is a graphical user interface for the DosierSkanilo file scanner. It allows you to load and explore
JSON output from the command-line scanner in an interactive way.

};

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
