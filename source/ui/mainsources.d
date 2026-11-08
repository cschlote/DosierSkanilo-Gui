/** Strong, explicit ownership for GLib main-loop sources with D callbacks.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.mainsources;

import core.sync.mutex : Mutex;
import glib.c.functions : g_idle_add_full, g_source_remove, g_timeout_add_full;
import glib.c.types : GDestroyNotify, GPriority, GSourceFunc;

/// Process-wide registry that keeps live GLib sources reachable from D.
private class UiSourceRegistry
{
    /// Sources retained by the registry; guarded by `gate`.
    private UiMainSource[] sources;
    /// Mutex guarding `sources` and `shuttingDown`.
    private Mutex gate;
    /// Whether shutdown has begun, after which new sources are rejected.
    private bool shuttingDown;

    /// Create an empty registry with a fresh mutex.
    this()
    {
        gate = new Mutex();
    }

    /** Add a source to the registry.
     *
     * Params:
     *     source = Source to retain.
     * Returns: `true` when the source was added, or `false` when shutdown has
     *     already begun.
     */
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

    /** Remove a source from the registry if present.
     *
     * Params:
     *     source = Source to release; unknown sources are ignored.
     */
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

    /** Mark the registry as shutting down and snapshot its sources.
     *
     * Returns: A copy of the sources retained at the time of the call; the
     *     registry itself is not cleared.
     */
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
    /// Registry that keeps this object alive until GLib destroys the source.
    UiSourceRegistry registry;
    /// User callback invoked on dispatch; cleared when the source is destroyed.
    bool delegate() callback;
    /// Mutex guarding all mutable state of this source.
    Mutex gate;
    /// GLib source identifier; zero while unattached or after destruction.
    uint sourceId;
    /// Whether the source ID has been attached and dispatch may run.
    bool ready;
    /// Whether `stop` was called; dispatch then declines to invoke the callback.
    bool cancelled;
    /// Whether GLib's destroy notify has run and the registry entry was released.
    bool destroyed;

    /** Create a source handle before it is attached to a GLib context.
     *
     * Params:
     *     registry = Registry that owns the strong reference.
     *     callback = Callback invoked on each dispatch; return true to keep the
     *         source active.
     */
    this(UiSourceRegistry registry, bool delegate() callback)
    {
        this.registry = registry;
        this.callback = callback;
        gate = new Mutex();
    }

    /** Set the source ID after GLib attaches it; return false if already cancelled.
     *
     * Params:
     *     id = GLib source identifier returned by the attach call.
     * Returns: `true` when the source was recorded and is not cancelled,
     *     otherwise `false`; a destroyed source rejects the ID outright.
     */
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

    /** Dispatch on the GLib main context.
     *
     * Returns: `1` to keep the source active, `0` when the callback asks for
     *     removal. Cancelled or not-yet-attached sources return `1` without
     *     invoking the callback.
     */
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

/// Registry shared by all sources scheduled through this module.
private __gshared UiSourceRegistry uiSourceRegistry;

/// Allocate the process-wide source registry.
shared static this()
{
    uiSourceRegistry = new UiSourceRegistry();
}

/** GLib source callback that forwards dispatch to the managed D object.
 *
 * Params:
 *     data = `UiMainSource` passed as user data by the scheduler.
 * Returns: `1` to keep the source active, `0` to remove it.
 */
private extern(C) int dispatchUiSource(void* data)
{
    auto source = cast(UiMainSource) data;
    return source.dispatch();
}

/** GLib destroy notify that releases the managed D object.
 *
 * Params:
 *     data = `UiMainSource` passed as user data by the scheduler.
 */
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

/** Stop a managed source on the GTK main thread.
 *
 * Params:
 *     source = Handle returned by a schedule function; null is ignored.
 */
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
    scheduleUiTimeout(50, {
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
