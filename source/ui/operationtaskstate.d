/** GTK-independent lifecycle state for one document's backend operation.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.operationtaskstate;

import dosierskanilo.operations : OperationKind, OperationProgress, OperationResult,
    OperationPhase, OperationState, validOperationStateTransition;

/** Mutable state reduced from value progress/result events for one operation. */
struct OperationTaskState
{
    /// Identifier of the backend operation currently tracked by this state.
    ulong operationId;
    /// Kind of backend operation currently tracked by this state.
    OperationKind operation;
    /// Latest acknowledged lifecycle state, starting at `OperationState.queued`.
    OperationState state = OperationState.queued;
    /// Whether the task is still live and therefore accepts progress and result events.
    bool running;
    /// Whether the backend reports that pausing is currently possible.
    bool pauseAvailable;
    /// Whether the task is in the acknowledged paused state.
    bool paused;

    /** Reset the state to track a newly started operation.
     *
     * Clears pause flags and marks the task running again, so any events from a
     * previous operation are ignored.
     *
     * Params:
     *     id = Identifier of the new backend operation.
     *     kind = Kind of the new backend operation.
     */
    void begin(ulong id, OperationKind kind)
    {
        operationId = id;
        operation = kind;
        state = OperationState.queued;
        running = true;
        pauseAvailable = false;
        paused = false;
    }

    /** Apply an event only when it belongs to this live task and has a valid transition.
     *
     * Params:
     *     event = Progress event to apply.
     * Returns: `true` when the event was accepted, `false` for events from a
     *     different or finished operation and for invalid state transitions.
     */
    bool apply(OperationProgress event)
    {
        if (!running || event.operationId != operationId || event.operation != operation)
            return false;
        if (event.state != state && !validOperationStateTransition(state, event.state))
            return false;
        state = event.state;
        pauseAvailable = event.pauseAvailable;
        paused = state == OperationState.paused;
        return true;
    }

    /** Apply the terminal result and reject any later progress for this operation.
     *
     * Params:
     *     result = Terminal result to apply.
     * Returns: `true` when the result belonged to this operation and was
     *     applied; `false` for results from another or already finished task.
     */
    bool complete(OperationResult result)
    {
        if (!running || result.operationId != operationId || result.operation != operation)
            return false;
        state = result.state;
        running = false;
        pauseAvailable = false;
        paused = false;
        return true;
    }
}

/** Whether a terminal result may have changed persisted source state.
 *
 * Params:
 *     result = Terminal operation result to inspect.
 * Returns: `true` when the operation completed or explicitly committed
 *     changes; otherwise `false`.
 */
bool operationResultMayHaveChangedSource(OperationResult result)
{
    if (result.state == OperationState.completed)
        return true;
    return result.changesCommitted;
}

@("operation task state rejects stale progress and follows acknowledged pause transitions")
unittest
{
    OperationTaskState task;
    task.begin(10, OperationKind.scan);
    OperationProgress progress;
    progress.operationId = 10;
    progress.operation = OperationKind.scan;
    progress.state = OperationState.running;
    progress.phase = OperationPhase.discovering;
    progress.pauseAvailable = true;
    assert(task.apply(progress));
    assert(task.running && task.pauseAvailable && !task.paused);

    progress.state = OperationState.pausing;
    assert(task.apply(progress));
    progress.state = OperationState.paused;
    progress.pauseAvailable = false;
    assert(task.apply(progress));
    assert(task.paused && !task.pauseAvailable);

    progress.state = OperationState.running;
    assert(task.apply(progress));
    assert(!task.paused);
    progress.operationId = 9;
    assert(!task.apply(progress), "late events from an older operation are ignored");

    OperationResult result;
    result.operationId = 10;
    result.operation = OperationKind.scan;
    result.state = OperationState.completed;
    assert(task.complete(result));
    assert(!task.running);
    assert(!task.apply(progress), "terminal tasks reject later progress");
}

@("operation task state ignores foreign events and invalid transitions")
unittest
{
    OperationTaskState task;
    task.begin(1, OperationKind.metadata);
    OperationProgress progress;
    progress.operationId = 1;
    progress.operation = OperationKind.scan;
    progress.state = OperationState.running;
    assert(!task.apply(progress), "progress for another operation kind is ignored");
    progress.operation = OperationKind.metadata;
    progress.operationId = 2;
    assert(!task.apply(progress), "progress for another operation id is ignored");
    progress.operationId = 1;
    progress.state = OperationState.completed;
    assert(!task.apply(progress), "queued cannot skip to a terminal state");
    progress.state = OperationState.running;
    assert(task.apply(progress));
    progress.state = OperationState.queued;
    assert(!task.apply(progress), "running cannot return to queued");

    OperationResult foreign;
    foreign.operationId = 2;
    foreign.operation = OperationKind.metadata;
    foreign.state = OperationState.completed;
    assert(!task.complete(foreign), "results for other operations are ignored");

    task.paused = true;
    task.pauseAvailable = true;
    task.begin(5, OperationKind.analyze);
    assert(task.operationId == 5 && task.operation == OperationKind.analyze);
    assert(task.state == OperationState.queued && task.running);
    assert(!task.paused && !task.pauseAvailable);

    OperationResult failed;
    failed.operationId = 5;
    failed.operation = OperationKind.analyze;
    failed.state = OperationState.failed;
    assert(task.complete(failed));
    assert(!task.running);
    assert(!operationResultMayHaveChangedSource(failed));
}

@("operation refresh decision distinguishes rolled-back and partial outcomes")
unittest
{
    OperationResult result;
    result.operation = OperationKind.scan;
    result.state = OperationState.cancelled;
    result.scanSummary.filesAdded = 2;
    result.changesCommitted = true;
    assert(operationResultMayHaveChangedSource(result));
    result.changesCommitted = false;
    assert(!operationResultMayHaveChangedSource(result),
        "cancelled JSON work does not replace its source");

    result = OperationResult.init;
    result.operation = OperationKind.analyze;
    result.state = OperationState.cancelled;
    result.analysisSummary.mergedBlobs = 3;
    result.changesCommitted = false;
    assert(!operationResultMayHaveChangedSource(result),
        "cancelled atomic analysis rolls back its planned merges");

    result = OperationResult.init;
    result.operation = OperationKind.metadata;
    result.state = OperationState.cancelled;
    result.metadataSummary.archivesUpdated = 1;
    result.changesCommitted = true;
    assert(operationResultMayHaveChangedSource(result));
}
