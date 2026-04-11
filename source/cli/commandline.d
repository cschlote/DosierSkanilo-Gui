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

/** Parsed startup options from command-line arguments. */
struct CliOptions
{
    string[] jsonPaths;
    string filterOnStart;
    bool caseSensitiveFilter;
    bool disableAutoFilter;
    bool argVerboseOutputs;
    bool showHelp;
}

/** Return human-readable CLI usage text. */
immutable string cliUsageText = q"EOF
DosierSkanilo GUI

This is a graphical user interface for browsing precomputed DosierSkanilo JSON
output. Open files from the GUI File menu.

Startup options:

    <file.json>             Open JSON files on startup
    -q, --query <text>      Prefill the text filter
    -v, --verbose           Enable verbose logging
            --case-sensitive    Use case-sensitive text matching
            --no-auto-filter    Disable auto-apply after load/reload
    -h, --help              Print this help and exit

EOF";

CliOptions argsArray;

/** Parse CLI arguments into startup option flags.
 *
 * Params:
 *   args = command-line argument array (in/out for getopt)
 * Returns:
 *   Parsed options with defaults applied
 */
void parseCliOptions(ref string[] args)
{
    getopt(
        args,
        config.passThrough,
        "q|query", &argsArray.filterOnStart,
        "v|verbose", &argsArray.argVerboseOutputs,
        "case-sensitive", &argsArray.caseSensitiveFilter,
        "no-auto-filter", &argsArray.disableAutoFilter,
        "h|help", &argsArray.showHelp
    );

    argsArray.jsonPaths.length = 0;
    if (args.length > 1)
    {
        argsArray.jsonPaths = args[1 .. $].dup;
    }
}

@("CLI options parsing")
unittest
{
    string[] testArgs = [
        "appname", "-q", "test query", "--case-sensitive", "file1.json",
        "file2.json"
    ];
    parseCliOptions(testArgs);
    assert(argsArray.filterOnStart == "test query");
    assert(argsArray.caseSensitiveFilter == true);
    assert(argsArray.jsonPaths.length == 2);
    assert(argsArray.jsonPaths[0] == "file1.json");
    assert(argsArray.jsonPaths[1] == "file2.json");
}
