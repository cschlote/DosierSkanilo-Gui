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
    string filterOnStart;
    bool caseSensitiveFilter;
    bool disableAutoFilter;
    bool showHelp;
}

/** Return human-readable CLI usage text. */
immutable string cliUsageText = q"EOF
DosierSkanilo GUI

This is a graphical user interface for browsing precomputed DosierSkanilo JSON
output. Open files from the GUI File menu.

Startup options:

    -q, --query <text>      Prefill the text filter
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
        "case-sensitive", &argsArray.caseSensitiveFilter,
        "no-auto-filter", &argsArray.disableAutoFilter,
        "h|help", &argsArray.showHelp
    );
}
