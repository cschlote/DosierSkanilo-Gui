/** UI loader for the document page shell and status labels. */
module ui.documentpage;

import gtk.Box;
import gtk.Builder;
import gtk.Label;

import ui.builderutils : builderObject, loadUiBuilder;
import ui.documenttab : DocumentTab;

/** Widgets from the document page layout. */
struct DocumentPageUi
{
    Box pageRoot;
    Box splitSlot;
}

/** Bind the document page layout to a document tab. */
DocumentPageUi loadDocumentPageUi(DocumentTab document)
{
    auto pageBuilder = loadUiBuilder!"source/ui/documentpage.ui"("page");
    document.pageBuilder = pageBuilder;

    DocumentPageUi ui;
    ui.pageRoot = builderObject!Box(pageBuilder, "page", "pageRoot");
    ui.splitSlot = builderObject!Box(pageBuilder, "page", "splitSlot");
    document.rowDetails = builderObject!Label(pageBuilder, "page", "rowDetails");
    document.status = builderObject!Label(pageBuilder, "page", "status");
    document.perfStatus = builderObject!Label(pageBuilder, "page", "perfStatus");
    document.fileMetaStatus = builderObject!Label(pageBuilder, "page", "fileMetaStatus");

    return ui;
}