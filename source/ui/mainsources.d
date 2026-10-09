/** Strong, explicit ownership for GLib main-loop sources with D callbacks. */
module ui.mainsources;

import core.sync.mutex : Mutex;
import glib.c.functions : g_idle_add_full, g_source_remove, g_timeout_add_full;
import glib.c.types : GDestroyNotify, GPriority, GSourceFunc;

private class UiSourceRegistry
{
    private UiMainSource[] sources;
    private Mutex gate;
    private bool shuttingDown;

    this()
    {
        gate = new Mutex();
    }

    bool retain(UiMainSource source)
    {
        gate.lock();
        scope (exit)
            gate.unlock();
        if (shuttingDown)
            return false;
        sources ~= source;
        return true;
    }

    void release(UiMainSource source)
    {
        gate.lock();
        scope (exit)
            gate.unlock();
        foreach (index, existing; sources)
        {
            if (existing is source)
            {
                sources = sources[0 .. index] ~ sources[index + 1 .. $];
                return;
            }
        }
    }

    UiMainSource[] beginShutdown()
    {
        gate.lock();
        scope (exit)
            gate.unlock();
        shuttingDown = true;
        return sources.dup;
    }
}

/** A GLib source whose callback data is retained until GLib destroys the source. */
final class UiMainSource
{
private:
    UiSourceRegistry registry;
    bool delegate() callback;
    Mutex gate;
    uint sourceId;
    bool ready;
    bool cancelled;
    bool destroyed;

    this(UiSourceRegistry registry, bool delegate() callback)
    {
        this.registry = registry;
        this.callback = callback;
        gate = new Mutex();
    }

    /** Set the source ID after GLib attaches it; return false if already cancelled. */
    bool attach(uint id)
    {
        gate.lock();
        scope (exit)
            gate.unlock();
        if (destroyed)
            return false;
        sourceId = id;
        ready = true;
        return !cancelled;
    }

    /** Dispatch on the GLib main context. */
    int dispatch()
    {
        bool delegate() callbackCopy;
        gate.lock();
        if (!ready || cancelled || destroyed)
        {
            gate.unlock();
            // Keep it attached until the scheduling/cancellation side removes it.
            return 1;
        }
        callbackCopy = callback;
        gate.unlock();
        return callbackCopy() ? 1 : 0;
    }

    /** Cancel on the GTK main thread; GLib releases this object's registry root. */
    void stop()
    {
        uint id;
        gate.lock();
        cancelled = true;
        ready = false;
        id = sourceId;
        gate.unlock();
        if (id > 0)
            g_source_remove(id);
    }

    /** Called only by GLib's GDestroyNotify after the source is actually removed. */
    void onDestroyed()
    {
        gate.lock();
        destroyed = true;
        cancelled = true;
        ready = false;
        sourceId = 0;
        callback = null;
        gate.unlock();
        registry.release(this);
    }
}

private __gshared UiSourceRegistry uiSourceRegistry;

shared static this()
{
    uiSourceRegistry = new UiSourceRegistry();
}

private extern(C) int dispatchUiSource(void* data)
{
    auto source = cast(UiMainSource) data;
    return source.dispatch();
}

private extern(C) void destroyUiSource(void* data)
{
    auto source = cast(UiMainSource) data;
    source.onDestroyed();
}

/** Schedule a repeating or one-shot timeout, retaining its D callback safely.
 *
 * Params:
 *     intervalMs = Timeout interval in milliseconds.
 *     callback = Return true to keep the source active; false to remove it.
 * Returns: A handle that can be stopped with stopUiSource.
 * Throws: None.
 */
UiMainSource scheduleUiTimeout(uint intervalMs, bool delegate() callback)
{
    auto source = new UiMainSource(uiSourceRegistry, callback);
    if (!uiSourceRegistry.retain(source))
        return null;

    auto sourceId = g_timeout_add_full(cast(int) GPriority.DEFAULT, intervalMs,
        cast(GSourceFunc) &dispatchUiSource, cast(void*) source,
        cast(GDestroyNotify) &destroyUiSource);
    if (sourceId == 0)
    {
        uiSourceRegistry.release(source);
        return null;
    }

    if (!source.attach(sourceId))
        g_source_remove(sourceId);
    return source;
}

/** Schedule an idle callback, retaining its D callback until source destruction.
 *
 * Params:
 *     callback = Return true to keep the source active; false to remove it.
 * Returns: A handle that can be stopped with stopUiSource.
 * Throws: None.
 */
UiMainSource scheduleUiIdle(bool delegate() callback)
{
    auto source = new UiMainSource(uiSourceRegistry, callback);
    if (!uiSourceRegistry.retain(source))
        return null;

    auto sourceId = g_idle_add_full(cast(int) GPriority.DEFAULT_IDLE,
        cast(GSourceFunc) &dispatchUiSource, cast(void*) source,
        cast(GDestroyNotify) &destroyUiSource);
    if (sourceId == 0)
    {
        uiSourceRegistry.release(source);
        return null;
    }

    if (!source.attach(sourceId))
        g_source_remove(sourceId);
    return source;
}

/** Stop a managed source on the GTK main thread. */
void stopUiSource(UiMainSource source)
{
    if (source !is null)
        source.stop();
}

/** Stop all managed sources during window teardown. */
void stopAllUiSources()
{
    foreach (source; uiSourceRegistry.beginShutdown())
        source.stop();
}

@("managed GLib sources survive garbage collection on a worker thread")
unittest
{
    import core.memory : GC;
    import core.thread : Thread;
    import glib.MainContext : MainContext;
    import glib.MainLoop : MainLoop;

    auto loop = new MainLoop(MainContext.default_(), false);
    bool timeoutFired;
    bool idleFired;
    scheduleUiIdle({
        idleFired = true;
        return false;
    });
    scheduleUiTimeout(10, {
        timeoutFired = true;
        loop.quit();
        return false;
    });
    bool cancelledSourceFired;
    auto cancelledSource = scheduleUiTimeout(500, {
        cancelledSourceFired = true;
        loop.quit();
        return false;
    });

    auto collector = new Thread({ GC.collect(); });
    collector.start();
    collector.join();

    loop.run();
    stopUiSource(cancelledSource);

    assert(idleFired);
    assert(timeoutFired);
    assert(!cancelledSourceFired);
}
