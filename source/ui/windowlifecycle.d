/** UI helpers for notebook and window lifecycle signal wiring. */
module ui.windowlifecycle;

import gdk.c.types : GdkEventConfigure;
import gtk.Notebook;
import gtk.Widget;
import gtk.Main;
import gtk.Window;
import gtk.c.types : GtkAllocation;
import ui.mainsources : UiMainSource, scheduleUiTimeout, stopUiSource;

/** Callbacks required by the lifecycle signal bindings. */
struct WindowLifecycleCallbacks
{
    void delegate(bool) persistCurrentState;
    bool delegate() clearSavedWindowGeometryOnExit;
    void delegate(int, int) setLastKnownWindowSize;
    bool delegate() allowRuntimeStatePersistence;
    void delegate(bool) setAllowRuntimeStatePersistence;
    UiMainSource delegate() windowSizePersistTimer;
    void delegate(UiMainSource) setWindowSizePersistTimer;
    void delegate() stopAllUiSources;
}

/** Bind notebook and window lifecycle handlers.
 *
 * Params:
 *     notebook = Notebook that raises page-switch events.
 *     window = Main application window that raises destroy and resize events.
 *     callbacks = State persistence hooks used by the lifecycle handlers.
 * Returns: Nothing.
 * Throws: None.
 */
void bindWindowLifecycleSignals(
    Notebook notebook,
    Window window,
    WindowLifecycleCallbacks callbacks
)
{
    notebook.addOnSwitchPage((Widget pageWidget, uint pageNum, Notebook tabNotebook) {
        callbacks.persistCurrentState(callbacks.clearSavedWindowGeometryOnExit());
    });

    window.addOnDestroy((Widget _) {
        callbacks.persistCurrentState(callbacks.clearSavedWindowGeometryOnExit());
        callbacks.stopAllUiSources();
        Main.quit();
    });

    window.addOnConfigure((GdkEventConfigure* event, Widget _) {
        if (event !is null)
        {
            callbacks.setLastKnownWindowSize(event.width, event.height);
        }
        return false;
    });

    window.addOnSizeAllocate((GtkAllocation* allocation, Widget _) {
        if (allocation.width <= 0 || allocation.height <= 0)
        {
            return;
        }

        callbacks.setLastKnownWindowSize(allocation.width, allocation.height);

        if (callbacks.allowRuntimeStatePersistence())
        {
            if (callbacks.windowSizePersistTimer() !is null)
            {
                auto timer = callbacks.windowSizePersistTimer();
                stopUiSource(timer);
                callbacks.setWindowSizePersistTimer(null);
            }
            callbacks.setWindowSizePersistTimer(scheduleUiTimeout(350, {
                callbacks.persistCurrentState(callbacks.clearSavedWindowGeometryOnExit());
                callbacks.setWindowSizePersistTimer(null);
                return false;
            }));
        }
    });
}
