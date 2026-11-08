/** GTK-independent routing for synchronized table/tree selections.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.treeselectionlogic;

import std.conv : to;

/** Follow-up needed after a row selection changed. */
enum TreeSelectionFollowup
{
    /// The change originated from a synchronized tree update; do nothing further.
    ignoreSynchronizedChange,
    /// Select the existing materialized tree row that corresponds to the table row.
    selectMaterializedTreeRow,
    /// Reveal the file in the tree because no materialized row exists yet.
    revealTreeFile
}

/** Decide whether a selection change should drive a reciprocal tree action.
 *
 * Params:
 *     syncingTreeSelection = Whether the change is already part of a
 *         tree-to-table synchronization.
 *     matchingTreeRowFound = Whether a materialized tree row exists for the
 *         selected table row.
 * Returns: The follow-up action to perform.
 */
TreeSelectionFollowup treeSelectionFollowup(bool syncingTreeSelection,
    bool matchingTreeRowFound)
{
    if (syncingTreeSelection)
        return TreeSelectionFollowup.ignoreSynchronizedChange;
    return matchingTreeRowFound
        ? TreeSelectionFollowup.selectMaterializedTreeRow
        : TreeSelectionFollowup.revealTreeFile;
}

/** Check a displayed table row's stable ordinal against its filtered row index.
 *
 * Params:
 *     displayedIndex = One-based ordinal shown for the row.
 *     visibleRowIndex = Zero-based index of the row in the filtered view.
 * Returns: `true` when the displayed ordinal equals `visibleRowIndex + 1`.
 */
bool tableIndexMatchesVisibleRow(string displayedIndex, size_t visibleRowIndex)
{
    return displayedIndex == (visibleRowIndex + 1).to!string;
}

/** Skip a filter-worker projection when the active criteria are all empty.
 *
 * Params:
 *     hasActiveCriteria = Whether any filter criterion is active.
 * Returns: `true` when a filter projection is needed, otherwise `false`.
 */
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
