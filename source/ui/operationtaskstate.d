/** GTK-independent lifecycle state for one document's backend operation. */
module ui.operationtaskstate;

import dosierskanilo.operations : OperationKind, OperationProgress, OperationResult,
    OperationPhase, OperationState, validOperationStateTransition;

/** Mutable state reduced from value progress/result events for one operation. */
struct OperationTaskState
{
    ulong operationId;
    OperationKind operation;
    OperationState state = OperationState.queued;
    bool running;
    bool pauseAvailable;
    bool paused;

    void begin(ulong id, OperationKind kind)
    {
        operationId = id;
        operation = kind;
        state = OperationState.queued;
        running = true;
        pauseAvailable = false;
        paused = false;
    }

    /** Apply an event only when it belongs to this live task and has a valid transition. */
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

    /** Apply the terminal result and reject any later progress for this operation. */
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

/** Whether a terminal result may have changed persisted source state. */
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
