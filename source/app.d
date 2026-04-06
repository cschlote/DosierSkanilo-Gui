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
    auto cli = parseCliOptions(args);
    if (cli.showHelp)
    {
        logLine(cliUsageText);
        return 0;
    }

    return runMainWindow(args, cli);
}
