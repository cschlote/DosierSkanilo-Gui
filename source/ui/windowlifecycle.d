/** UI helpers for notebook and window lifecycle signal wiring. */
module ui.windowlifecycle;

import gdk.c.types : GdkEventConfigure;
import gtk.Notebook;
import gtk.Widget;
import gtk.Main;
import gtk.Window;
import gtk.c.types : GtkAllocation;
import glib.Timeout;

/** Callbacks required by the lifecycle signal bindings. */
struct WindowLifecycleCallbacks
{
    void delegate(bool) persistCurrentState;
    bool delegate() clearSavedWindowGeometryOnExit;
    void delegate(int, int) setLastKnownWindowSize;
    bool delegate() allowRuntimeStatePersistence;
    void delegate(bool) setAllowRuntimeStatePersistence;
    Timeout delegate() windowSizePersistTimer;
    void delegate(Timeout) setWindowSizePersistTimer;
}

/** Bind notebook and window lifecycle handlers. */
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
                timer.stop();
                callbacks.setWindowSizePersistTimer(null);
            }
            callbacks.setWindowSizePersistTimer(new Timeout(350, {
                callbacks.persistCurrentState(callbacks.clearSavedWindowGeometryOnExit());
                callbacks.setWindowSizePersistTimer(null);
                return false;
            }));
        }
    });
}