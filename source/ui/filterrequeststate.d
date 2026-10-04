/** GTK-independent generation and pending state for asynchronous filters. */
module ui.filterrequeststate;

/** Tracks one latest-wins asynchronous request and rejects stale replies. */
struct FilterRequestState
{
    private ulong generation;
    private bool hasPendingRequest;

    /** Start a new request, invalidating any older request token. */
    ulong begin()
    {
        ++generation;
        if (generation == 0)
            ++generation;
        hasPendingRequest = true;
        return generation;
    }

    /** Return whether `requestId` is the current, still-pending request. */
    bool isCurrent(ulong requestId) const
    {
        return hasPendingRequest && requestId != 0 && requestId == generation;
    }

    /** Complete only the matching pending request. */
    bool complete(ulong requestId)
    {
        if (!isCurrent(requestId))
            return false;
        hasPendingRequest = false;
        return true;
    }

    /** Invalidate the current request and report whether one was pending. */
    bool invalidate()
    {
        auto wasPending = hasPendingRequest;
        ++generation;
        if (generation == 0)
            ++generation;
        hasPendingRequest = false;
        return wasPending;
    }

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
