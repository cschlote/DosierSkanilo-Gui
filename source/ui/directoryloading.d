/** Recovery helpers for expanded directory nodes with loading placeholders.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.directoryloading;

import gtk.TreeIter;
import gtk.TreeModelIF;
import gtk.TreePath;
import gtk.TreeStore;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.c.types : GType;

/** Recursively request children for expanded directories that still show a placeholder.
 *
 * Params:
 *     model = Tree model being inspected.
 *     treeView = View used to test whether a row is expanded.
 *     parent = Parent row whose children are scanned; ignored when `hasParent`
 *         is false.
 *     hasParent = Whether `parent` identifies a row instead of the top level.
 *     loadChildren = Callback invoked with the directory path, its identifier,
 *         and the placeholder path.
 */
private void scanExpandedDirectories(TreeModelIF model, TreeView treeView,
    TreeIter parent, bool hasParent,
    void delegate(TreePath, string, TreePath) loadChildren)
{
    TreeIter iter;
    if (hasParent)
    {
        if (!model.iterChildren(iter, parent))
            return;
    }
    else if (!model.getIterFirst(iter))
        return;

    do
    {
        if (model.getValueString(iter, 1) == "Directory")
        {
            auto directoryId = model.getValueString(iter, 3);
            auto directoryPath = model.getPath(iter);
            if (treeView.rowExpanded(directoryPath))
            {
                TreeIter child;
                if (model.iterChildren(child, iter)
                    && model.getValueString(child, 1) == "Placeholder")
                    loadChildren(directoryPath, directoryId, model.getPath(child));
            }
            if (model.iterHasChild(iter))
                scanExpandedDirectories(model, treeView, iter, true, loadChildren);
        }
    }
    while (model.iterNext(iter));
}

/** Request data for expanded directories whose only child is still a placeholder.
 *
 * Params:
 *     treeView = View whose expanded rows are inspected.
 *     loadChildren = Callback invoked with a directory path, its identifier,
 *         and the placeholder path.
 */
void loadExpandedDirectoryPlaceholders(TreeView treeView,
    void delegate(TreePath, string, TreePath) loadChildren)
{
    auto model = treeView.getModel();
    if (model is null)
        return;
    scanExpandedDirectories(model, treeView, new TreeIter(), false, loadChildren);
}

@("expanded nested GTK directories recover loading placeholders without a toggle")
unittest
{
    import gtk.Main : Main;
    import std.process : environment;

    if (environment.get("DOSIER_GUI_TREE_LOAD_TEST", "") != "1")
        return;
    string[] args = ["dosierskanilo-gui-tests"];
    assert(Main.initCheck(args), "GTK tree loading test requires a usable display.");

    auto store = new TreeStore([GType.STRING, GType.STRING, GType.STRING,
        GType.STRING]);
    auto root = store.createIter(null);
    store.setValue(root, 0, "(source root)");
    store.setValue(root, 1, "Directory");
    store.setValue(root, 3, "root");
    auto directory = store.createIter(root);
    store.setValue(directory, 0, "nested");
    store.setValue(directory, 1, "Directory");
    store.setValue(directory, 3, "directory-17");
    auto loading = store.createIter(directory);
    store.setValue(loading, 0, "Loading...");
    store.setValue(loading, 1, "Placeholder");
    auto treeView = new TreeView(store);
    assert(treeView.expandRow(store.getPath(root), false));
    auto directoryPath = store.getPath(directory);
    assert(treeView.expandRow(directoryPath, false));

    size_t loadRequests;
    loadExpandedDirectoryPlaceholders(treeView,
        (TreePath parentPath, string directoryId, TreePath placeholderPath) {
            assert(parentPath.toString == directoryPath.toString);
            assert(directoryId == "directory-17");
            assert(placeholderPath.toString == "0:0:0");
            ++loadRequests;
        });
    assert(loadRequests == 1);
}
