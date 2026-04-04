/** Entry module for DosierSkanilo GUI.
 *
 * Delegates startup and GTK main window orchestration to ui.mainwindow.
 */
module app;

import ui.mainwindow : runMainWindow;

int main(string[] args)
{
    return runMainWindow(args);
}
