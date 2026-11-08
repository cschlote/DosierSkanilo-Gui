/** UI helpers for document tab actions like reload and close.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.documentactions;

import ui.documenttab : DocumentTab;

/** Callbacks required by document tab actions. */
struct DocumentActionCallbacks
{
    /// Returns the currently selected document tab, or `null` when none is open.
    DocumentTab delegate() currentDocument;
    /// Returns the notebook index of the active page, or a negative value when none is selected.
    int delegate() currentPageIndex;
    /// Returns the number of open document tabs.
    int delegate() documentCount;
    /// Returns the document tab at the given notebook index.
    DocumentTab delegate(int) documentAtIndex;
    /// Removes the notebook page at the given index.
    void delegate(int) removeNotebookPage;
    /// Refreshes toolbar controls from the currently selected document.
    void delegate() syncToolbarFromCurrentDocument;
    /// Persists the current UI state, optionally clearing saved window geometry.
    void delegate(bool) persistCurrentState;
    /// Returns true while a document load is in progress.
    bool delegate() isLoading;
    /// Returns the document tab that owns the current load, or `null` when idle.
    DocumentTab delegate() busyDocument;
    /// Returns true when saved window geometry should be discarded on exit.
    bool delegate() clearSavedWindowGeometryOnExit;
    /// Loads the given document tab; the flag requests fitting the horizontal split after loading.
    void delegate(DocumentTab, bool) loadDocument;
}

/** Reload the currently selected document tab from disk.
 *
 * Params:
 *     callbacks = Accessors and actions used to obtain and reload the active
 *         document tab.
 * Returns: Nothing.
 * Throws: None.
 */
void reloadCurrentDocument(DocumentActionCallbacks callbacks)
{
    auto document = callbacks.currentDocument();
    if (document is null)
    {
        return;
    }
    callbacks.loadDocument(document, false);
}

/** Close the currently selected document tab and persist the remaining open set.
 *
 * Params:
 *     callbacks = Accessors and actions used to inspect the notebook state and
 *         remove the active page.
 * Returns: Nothing.
 * Throws: None.
 */
void closeCurrentDocument(DocumentActionCallbacks callbacks)
{
    auto pageIndex = callbacks.currentPageIndex();
    if (pageIndex < 0 || pageIndex >= callbacks.documentCount())
    {
        return;
    }

    auto document = callbacks.documentAtIndex(pageIndex);
    if (callbacks.isLoading() && callbacks.busyDocument() is document)
    {
        document.status.setText("Cannot close a tab while it is loading.");
        return;
    }

    callbacks.removeNotebookPage(pageIndex);
    callbacks.syncToolbarFromCurrentDocument();
    callbacks.persistCurrentState(callbacks.clearSavedWindowGeometryOnExit());
}