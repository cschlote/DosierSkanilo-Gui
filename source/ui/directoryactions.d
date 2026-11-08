/** TreeView directory expansion actions.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.directoryactions;

import gtk.TreeIter;
import gtk.TreeModelIF;
import gtk.TreePath;
import gtk.TreeView;

/** Toggle one directory row without recursively opening its descendants.
 *
 * Params:
 *     treeView = View containing the directory row.
 *     path = Path of the directory row to expand or collapse.
 */
void toggleDirectoryExpansion(TreeView treeView, TreePath path)
{
    if (treeView.rowExpanded(path))
        treeView.collapseRow(path);
    else
        treeView.expandRow(path, false);
}

/** Toggle every currently represented directory below one tree row.
 *
 * Params:
 *     treeView = View containing the directory row.
 *     path = Path of the directory row whose subtree is toggled.
 */
void toggleDirectorySubtree(TreeView treeView, TreePath path)
{
    if (!treeView.rowExpanded(path))
    {
        treeView.expandRow(path, true);
        return;
    }

    auto model = treeView.getModel();
    auto root = new TreeIter();
    if (!model.getIter(root, path))
        return;
    collapseDirectoryNode(treeView, model, root);
}

/** Recursively collapse a directory row and all nested directories below it.
 *
 * Params:
 *     treeView = View whose rows are collapsed.
 *     model = Tree model backing the view.
 *     directory = Row to collapse after its directory descendants.
 */
private void collapseDirectoryNode(TreeView treeView, TreeModelIF model,
    TreeIter directory)
{
    auto child = new TreeIter();
    if (model.iterChildren(child, directory))
    {
        do
        {
            if (model.getValueString(child, 1) == "Directory")
                collapseDirectoryNode(treeView, model, child);
        }
        while (model.iterNext(child));
    }

    auto path = model.getPath(directory);
    if (treeView.rowExpanded(path))
        treeView.collapseRow(path);
}

@("directory row and subtree actions expand and collapse")
unittest
{
    import gtk.Main : Main;
    import gtk.TreeStore;
    import gtk.c.types : GType;
    import std.process : environment;

    if (environment.get("DOSIER_GUI_ACTIVATION_TEST", "") != "1")
        return;
    string[] args = ["dosierskanilo-gui-directory-actions-test"];
    assert(Main.initCheck(args), "GTK directory action test requires a usable display.");

    auto store = new TreeStore([GType.STRING, GType.STRING]);
    auto root = store.createIter(null);
    store.setValue(root, 0, "root");
    store.setValue(root, 1, "Directory");
    auto child = store.createIter(root);
    store.setValue(child, 0, "child");
    store.setValue(child, 1, "Directory");
    auto leafDirectory = store.createIter(child);
    store.setValue(leafDirectory, 0, "leaf");
    store.setValue(leafDirectory, 1, "Directory");
    auto file = store.createIter(leafDirectory);
    store.setValue(file, 0, "file.txt");
    store.setValue(file, 1, "File");

    auto treeView = new TreeView(store);
    auto rootPath = store.getPath(root);
    auto childPath = store.getPath(child);
    auto leafPath = store.getPath(leafDirectory);

    toggleDirectoryExpansion(treeView, rootPath);
    assert(treeView.rowExpanded(rootPath));
    toggleDirectoryExpansion(treeView, rootPath);
    assert(!treeView.rowExpanded(rootPath));

    toggleDirectorySubtree(treeView, rootPath);
    assert(treeView.rowExpanded(rootPath));
    assert(treeView.rowExpanded(childPath));
    assert(treeView.rowExpanded(leafPath));
    toggleDirectorySubtree(treeView, rootPath);
    assert(!treeView.rowExpanded(rootPath));
    assert(!treeView.rowExpanded(childPath));
    assert(!treeView.rowExpanded(leafPath));
}
