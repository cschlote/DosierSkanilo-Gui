/** Entry module for DosierSkanilo GUI.
 *
 * Delegates startup and GTK main window orchestration to ui.mainwindow.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module app;

import cli.commandline;
import cli.logging;
import ui.mainwindow;

/** Start the DosierSkanilo GUI after parsing command-line options.
 *
 * Params:
 *     args = Process arguments, including the program name.
 * Returns: Process exit code; `0` when help was printed, otherwise the result
 *     of running the main window.
 * Throws: CLI parsing or main-window startup failures may propagate.
 */
int main(string[] args)
{
    logFLine("DosierSkanilo GUI starting up...");

    parseCliOptions(args);
    if (argsArray.showHelp)
    {
        logLine(cliUsageText);
        return 0;
    }
    logFLineVerbose("Command line arguments: %s", args);

    return runMainWindow(args, argsArray);
}
