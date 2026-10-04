/** GTK-independent routing for synchronized table/tree selections. */
module ui.treeselectionlogic;

/** Follow-up needed after a row selection changed. */
enum TreeSelectionFollowup
{
    ignoreSynchronizedChange,
    selectMaterializedTreeRow,
    revealTreeFile
}

/** Decide whether a selection change should drive a reciprocal tree action. */
TreeSelectionFollowup treeSelectionFollowup(bool syncingTreeSelection,
    bool matchingTreeRowFound)
{
    if (syncingTreeSelection)
        return TreeSelectionFollowup.ignoreSynchronizedChange;
    return matchingTreeRowFound
        ? TreeSelectionFollowup.selectMaterializedTreeRow
        : TreeSelectionFollowup.revealTreeFile;
}

@("tree selection sync guard prevents reciprocal reveal and expansion")
unittest
{
    assert(treeSelectionFollowup(true, false)
        == TreeSelectionFollowup.ignoreSynchronizedChange);
    assert(treeSelectionFollowup(true, true)
        == TreeSelectionFollowup.ignoreSynchronizedChange);
    assert(treeSelectionFollowup(false, true)
        == TreeSelectionFollowup.selectMaterializedTreeRow);
    assert(treeSelectionFollowup(false, false)
        == TreeSelectionFollowup.revealTreeFile);
}
