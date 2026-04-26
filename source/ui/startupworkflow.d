/** UI helpers for startup restoration and self-test shutdown scheduling. */
module ui.startupworkflow;

import glib.Timeout;

import cli.logging;

/** Schedule the self-test shutdown timer once startup work is complete. */
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

/** Append startup file paths, restore the requested tab, and kick off startup loading. */
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