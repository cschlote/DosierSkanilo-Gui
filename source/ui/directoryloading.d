/** Recovery helpers for expanded directory nodes with loading placeholders. */
module ui.directoryloading;

import gtk.TreeIter;
import gtk.TreeModelIF;
import gtk.TreePath;
import gtk.TreeStore;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.c.types : GType;

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

/** Request data for expanded directories whose only child is still a placeholder. */
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
