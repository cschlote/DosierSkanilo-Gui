/** GTK signal binding for asynchronous nested-detail continuation rows.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.nestedentrysignals;

import gtk.Main : Main;
import gtk.TreeIter;
import gtk.TreeModelIF;
import gtk.TreePath;
import gtk.TreeStore;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.c.types : GType;

import std.conv : to;
import std.process : environment;

/** Query details carried by an activated archive/torrent continuation row. */
struct NestedPageActivation
{
    /// Whether the activation belongs to an archive page rather than a torrent page.
    bool archive;
    /// Stable identifier of the archive or torrent blob whose details are paged.
    string blobId;
    /// Zero-based offset of the first entry to load for the continuation page.
    size_t offset;
    /// Token identifying the root selection the activation belongs to.
    string selectionToken;
    /// Token identifying this particular page request for stale-reply rejection.
    string requestToken;
}

/** Bind a continuation-row activation to its asynchronous page request.
 *
 * Only archive/torrent continuation rows whose parent matches the expected
 * root and blob ID are forwarded; other activations are ignored.
 *
 * Params:
 *     treeView = Tree view whose row-activation signal is bound.
 *     loadPage = Callback invoked with the root path, the copied page path, and
 *         the activation details when a valid continuation row is activated.
 */
void bindNestedPageActivation(TreeView treeView,
    void delegate(TreePath, TreePath, NestedPageActivation) loadPage)
{
    treeView.addOnRowActivated((TreePath path, TreeViewColumn _, TreeView activatedView) {
        auto model = activatedView.getModel();
        auto page = new TreeIter();
        if (!model.getIter(page, path))
            return;
        auto pageKind = model.getValueString(page, 3);
        bool archive;
        if (pageKind == "ArchivePage")
            archive = true;
        else if (pageKind != "TorrentPage")
            return;

        auto parent = new TreeIter();
        if (!model.iterParent(parent, page))
            return;
        auto rootKind = archive ? "ArchiveRoot" : "TorrentRoot";
        auto blobId = model.getValueString(page, 4);
        if (model.getValueString(parent, 3) != rootKind
            || model.getValueString(parent, 4) != blobId)
            return;

        size_t offset;
        try
            offset = to!size_t(model.getValueString(page, 5));
        catch (Exception)
            return;

        NestedPageActivation request;
        request.archive = archive;
        request.blobId = blobId;
        request.offset = offset;
        request.selectionToken = model.getValueString(parent, 6);
        request.requestToken = model.getValueString(page, 6);
        loadPage(model.getPath(parent), path.copy(), request);
    });
}

/** Reject an async page reply unless its root, selection, and marker still match.
 *
 * Params:
 *     model = Tree model containing the root and marker rows.
 *     rootPath = Path of the archive or torrent root row.
 *     markerPath = Path of the loading/continuation marker row.
 *     archive = Whether the expected root kind is `ArchiveRoot` rather than
 *         `TorrentRoot`.
 *     blobId = Expected blob identifier stored on both rows.
 *     offset = Expected continuation offset stored on the marker row.
 *     selectionToken = Expected root selection token.
 *     loadingKind = Expected kind string of the marker row.
 *     requestToken = Expected request token stored on the marker row.
 * Returns: `true` when all root, selection, and marker fields still match;
 *     `false` when either path is invalid or any checked value differs.
 */
bool nestedEntryReplyMatches(TreeModelIF model, TreePath rootPath, TreePath markerPath,
    bool archive, string blobId, size_t offset, string selectionToken,
    string loadingKind, string requestToken)
{
    auto root = new TreeIter();
    auto marker = new TreeIter();
    if (!model.getIter(root, rootPath) || !model.getIter(marker, markerPath))
        return false;
    auto rootKind = archive ? "ArchiveRoot" : "TorrentRoot";
    return model.getValueString(root, 3) == rootKind
        && model.getValueString(root, 4) == blobId
        && model.getValueString(root, 6) == selectionToken
        && model.getValueString(marker, 3) == loadingKind
        && model.getValueString(marker, 4) == blobId
        && model.getValueString(marker, 5) == offset.to!string
        && model.getValueString(marker, 6) == requestToken;
}

@("GTK continuation activation preserves offsets and rejects stale selection replies")
unittest
{
    if (environment.get("DOSIER_GUI_ACTIVATION_TEST", "") != "1")
        return;
    string[] args = ["dosierskanilo-gui-tests"];
    assert(Main.initCheck(args), "GTK activation test requires a usable display.");

    auto store = new TreeStore([GType.STRING, GType.STRING, GType.STRING,
        GType.STRING, GType.STRING, GType.STRING, GType.STRING]);
    auto root = store.createIter(null);
    store.setValue(root, 3, "TorrentRoot");
    store.setValue(root, 4, "42");
    store.setValue(root, 6, "selection-7");
    auto page = store.createIter(root);
    store.setValue(page, 3, "TorrentPage");
    store.setValue(page, 4, "42");
    store.setValue(page, 5, "250");
    store.setValue(page, 6, "request-9");
    auto treeView = new TreeView(store);

    bool called;
    NestedPageActivation actualRequest;
    string actualRootKind;
    bindNestedPageActivation(treeView, (TreePath rootPath, TreePath _,
            NestedPageActivation request) {
        called = true;
        actualRequest = request;
        auto rootIter = new TreeIter();
        assert(store.getIter(rootIter, rootPath));
        actualRootKind = store.getValueString(rootIter, 3);
    });
    treeView.rowActivated(store.getPath(page), null);

    assert(called);
    assert(actualRootKind == "TorrentRoot");
    assert(!actualRequest.archive);
    assert(actualRequest.blobId == "42");
    assert(actualRequest.offset == 250);
    assert(actualRequest.selectionToken == "selection-7");
    assert(actualRequest.requestToken == "request-9");

    store.setValue(page, 3, "TorrentLoadingPage");
    store.setValue(page, 6, "response-11");
    auto rootPath = store.getPath(root);
    auto markerPath = store.getPath(page);
    assert(nestedEntryReplyMatches(treeView.getModel(), rootPath, markerPath,
        false, "42", 250, "selection-7", "TorrentLoadingPage", "response-11"));
    store.setValue(root, 6, "selection-8");
    assert(!nestedEntryReplyMatches(treeView.getModel(), rootPath, markerPath,
        false, "42", 250, "selection-7", "TorrentLoadingPage", "response-11"));
}
