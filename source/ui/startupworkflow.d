/** UI helpers for startup restoration and self-test shutdown scheduling. */
module ui.startupworkflow;

import glib.Timeout;

import cli.logging;

/** Schedule the self-test shutdown timer once startup work is complete.
 *
 * Params:
 *     selfTestMode = True when the application should quit automatically after
 *         startup.
 *     selfTestQuitScheduled = Tracks whether the shutdown timer has already
 *         been created.
 *     selfTestDelayMs = Delay before quitting in milliseconds.
 *     selfTestQuitTimer = Timer slot used to keep the scheduled quit alive.
 *     quitApplication = Callback that terminates the application.
 * Returns: Nothing.
 * Throws: Timer creation or logging failures may propagate.
 */
void scheduleSelfTestQuit(
    bool selfTestMode,
    ref bool selfTestQuitScheduled,
    int selfTestDelayMs,
    ref Timeout selfTestQuitTimer,
    void delegate() quitApplication
)
{
    if (!selfTestMode || selfTestQuitScheduled)
    {
        return;
    }

    selfTestQuitScheduled = true;
    logLine("[self-test] scheduling quit in ", selfTestDelayMs, " ms");
    selfTestQuitTimer = new Timeout(selfTestDelayMs, {
        logLine("[self-test] quitting after startup delay");
        quitApplication();
        return false;
    });
}

/** Append startup file paths, restore the requested tab, and kick off startup loading.
 *
 * Params:
 *     pendingStartupPaths = Queue of paths that still need to be opened.
 *     pendingStartupSelectIndex = Index of the tab that should be selected
 *         after restoring startup files.
 *     prefRestoreOpenFiles = Preference that controls restoration of saved
 *         open documents.
 *     savedOpenFilePaths = Persisted document paths from the previous session.
 *     cliJsonPaths = Additional JSON paths supplied on the command line.
 *     restoredActiveTabIndex = Tab index stored in the persisted state.
 *     selfTestMode = True when the application should quit after startup.
 *     selfTestQuitScheduled = Tracks whether the shutdown timer has already
 *         been created.
 *     selfTestDelayMs = Delay before quitting in milliseconds.
 *     selfTestQuitTimer = Timer slot used to keep the scheduled quit alive.
 *     loadNextPendingStartupPath = Callback that opens the next queued path.
 *     quitApplication = Callback that terminates the application.
 * Returns: Nothing.
 * Throws: Timer creation, logging, or callback failures may propagate.
 */
void startStartupWorkflow(
    ref string[] pendingStartupPaths,
    ref int pendingStartupSelectIndex,
    bool prefRestoreOpenFiles,
    string[] savedOpenFilePaths,
    string[] cliJsonPaths,
    int restoredActiveTabIndex,
    bool selfTestMode,
    ref bool selfTestQuitScheduled,
    int selfTestDelayMs,
    ref Timeout selfTestQuitTimer,
    void delegate() loadNextPendingStartupPath,
    void delegate() quitApplication
)
{
    foreach (savedPath; savedOpenFilePaths)
    {
        pendingStartupPaths ~= savedPath;
    }
    foreach (startupPath; cliJsonPaths)
    {
        pendingStartupPaths ~= startupPath;
    }

    if (pendingStartupPaths.length > 0)
    {
        if (prefRestoreOpenFiles && savedOpenFilePaths.length > 0)
        {
            pendingStartupSelectIndex = restoredActiveTabIndex;
        }
        loadNextPendingStartupPath();
        return;
    }

    scheduleSelfTestQuit(selfTestMode, selfTestQuitScheduled, selfTestDelayMs, selfTestQuitTimer, quitApplication);
}