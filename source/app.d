/** Entry module for DosierSkanilo GUI.
 *
 * Delegates startup and GTK main window orchestration to ui.mainwindow.
 */
module app;

import cli.commandline;
import cli.logging;
import ui.mainwindow;

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
