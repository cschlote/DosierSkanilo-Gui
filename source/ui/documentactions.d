/** UI helpers for document tab actions like reload and close. */
module ui.documentactions;

import ui.documenttab : DocumentTab;

/** Callbacks required by document tab actions. */
struct DocumentActionCallbacks
{
    DocumentTab delegate() currentDocument;
    int delegate() currentPageIndex;
    int delegate() documentCount;
    DocumentTab delegate(int) documentAtIndex;
    void delegate(int) removeNotebookPage;
    void delegate() syncToolbarFromCurrentDocument;
    void delegate(bool) persistCurrentState;
    bool delegate() isLoading;
    DocumentTab delegate() busyDocument;
    bool delegate() clearSavedWindowGeometryOnExit;
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