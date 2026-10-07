/** GTK-independent routing for synchronized table/tree selections. */
module ui.treeselectionlogic;

import std.conv : to;

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

/** Check a displayed table row's stable ordinal against its filtered row index. */
bool tableIndexMatchesVisibleRow(string displayedIndex, size_t visibleRowIndex)
{
    return displayedIndex == (visibleRowIndex + 1).to!string;
}

/** Skip a filter-worker projection when the active criteria are all empty. */
bool jsonFilterNeedsRebuild(bool hasActiveCriteria)
{
    return hasActiveCriteria;
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

    // The model may display these row ordinals in a user-selected sort order.
    string[] displayedIndices = ["3", "1", "2"];
    assert(tableIndexMatchesVisibleRow(displayedIndices[0], 2));
    assert(tableIndexMatchesVisibleRow(displayedIndices[1], 0));
    assert(tableIndexMatchesVisibleRow(displayedIndices[2], 1));
    assert(!tableIndexMatchesVisibleRow(displayedIndices[0], 0));
    assert(!jsonFilterNeedsRebuild(false),
        "clearing uses loaded rows directly without a filter projection");
    assert(jsonFilterNeedsRebuild(true));
}
