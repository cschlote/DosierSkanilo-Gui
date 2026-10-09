/** UI helpers for startup restoration and self-test shutdown scheduling. */
module ui.startupworkflow;

import cli.logging;
import ui.mainsources : UiMainSource, scheduleUiTimeout;

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
    ref UiMainSource selfTestQuitTimer,
    void delegate() quitApplication
)
{
    if (!selfTestMode || selfTestQuitScheduled)
    {
        return;
    }

    selfTestQuitScheduled = true;
    logLine("[self-test] scheduling quit in ", selfTestDelayMs, " ms");
    selfTestQuitTimer = scheduleUiTimeout(cast(uint) selfTestDelayMs, {
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
    ref UiMainSource selfTestQuitTimer,
    void delegate() loadNextPendingStartupPath,
    void delegate() quitApplication
)
{
    if (prefRestoreOpenFiles)
    {
        foreach (savedPath; savedOpenFilePaths)
        {
            pendingStartupPaths ~= savedPath;
        }
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

@("startup restoration respects the open-files preference")
unittest
{
    string[] pending;
    int loadCalls;
    int selectedIndex = -1;
    bool scheduled;
    UiMainSource timer;

    startStartupWorkflow(pending, selectedIndex, false,
        ["one.json", "two.json"], [], 1, false, scheduled, 1, timer,
        { ++loadCalls; }, {});
    assert(pending.length == 0);
    assert(loadCalls == 0);

    pending = [];
    startStartupWorkflow(pending, selectedIndex, true,
        ["one.json", "two.json"], [], 1, false, scheduled, 1, timer,
        { ++loadCalls; }, {});
    assert(pending == ["one.json", "two.json"]);
    assert(loadCalls == 1);
    assert(selectedIndex == 1);
}
