/** GTK-independent generation and pending state for asynchronous filters.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.filterrequeststate;

/** Tracks one latest-wins asynchronous request and rejects stale replies. */
struct FilterRequestState
{
    /// Current request generation token, advanced on begin/invalidate and never zero.
    private ulong generation;
    /// Whether a request has been started and not yet completed or invalidated.
    private bool hasPendingRequest;

    /** Start a new request, invalidating any older request token.
     *
     * Returns: The new non-zero request token to pass back on completion.
     */
    ulong begin()
    {
        ++generation;
        if (generation == 0)
            ++generation;
        hasPendingRequest = true;
        return generation;
    }

    /** Return whether `requestId` is the current, still-pending request.
     *
     * Params:
     *     requestId = Token returned by `begin`.
     * Returns: `true` only when a request is pending and `requestId` matches
     *     its generation.
     */
    bool isCurrent(ulong requestId) const
    {
        return hasPendingRequest && requestId != 0 && requestId == generation;
    }

    /** Complete only the matching pending request.
     *
     * Params:
     *     requestId = Token returned by `begin`.
     * Returns: `true` when the token was current and the pending state was
     *     cleared; `false` for stale or already completed tokens.
     */
    bool complete(ulong requestId)
    {
        if (!isCurrent(requestId))
            return false;
        hasPendingRequest = false;
        return true;
    }

    /** Invalidate the current request and report whether one was pending.
     *
     * Returns: `true` when a request was pending before invalidation.
     */
    bool invalidate()
    {
        auto wasPending = hasPendingRequest;
        ++generation;
        if (generation == 0)
            ++generation;
        hasPendingRequest = false;
        return wasPending;
    }

    /** Whether a request is currently pending.
     *
     * Returns: `true` while a request started by `begin` has not been completed
     *     or invalidated.
     */
    @property bool pending() const
    {
        return hasPendingRequest;
    }
}

@("filter request state rejects stale, cancelled, and superseded replies")
unittest
{
    FilterRequestState state;
    auto first = state.begin();
    assert(state.pending);
    assert(state.isCurrent(first));

    FilterRequestState otherDocumentState;
    auto otherDocumentRequest = otherDocumentState.begin();
    assert(otherDocumentState.complete(otherDocumentRequest));
    assert(state.isCurrent(first),
        "completing work in another tab must not invalidate this document");

    assert(state.invalidate());
    assert(!state.pending);
    assert(!state.isCurrent(first));
    assert(!state.complete(first));

    auto second = state.begin();
    auto third = state.begin();
    assert(second != first);
    assert(third != second);
    assert(!state.isCurrent(second));
    assert(!state.complete(second));
    assert(state.pending, "completing a stale request must not clear newer state");
    assert(state.isCurrent(third));
    assert(state.complete(third));
    assert(!state.pending);
    assert(!state.isCurrent(third));
}
