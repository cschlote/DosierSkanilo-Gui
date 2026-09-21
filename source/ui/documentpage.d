/** UI loader for the document page shell and status labels. */
module ui.documentpage;

import gtk.Box;
import gtk.Button;
import gtk.Builder;
import gtk.Label;
import gtk.ComboBoxText;

import ui.builderutils : builderObject, builderObjectOrNull, loadUiBuilder;
import ui.documenttab : DocumentTab;

/** Widgets from the document page layout. */
struct DocumentPageUi
{
    Box pageRoot;
    Box splitSlot;
    Box pageBar;
}

/** Bind the document page layout to a document tab.
 *
 * Params:
 *     document = Active document tab that receives the page widgets.
 * Returns: A struct with the page shell widgets for the document tab.
 * Throws: Any missing builder object or GtkBuilder parse failure is propagated.
 */
DocumentPageUi loadDocumentPageUi(DocumentTab document)
{
    auto pageBuilder = loadUiBuilder!"source/ui/documentpage.ui"("page");
    document.pageBuilder = pageBuilder;

    DocumentPageUi ui;
    ui.pageRoot = builderObject!Box(pageBuilder, "page", "pageRoot");
    ui.splitSlot = builderObject!Box(pageBuilder, "page", "splitSlot");
    ui.pageBar = builderObject!Box(pageBuilder, "page", "pageBar");
    document.pageBar = ui.pageBar;
    document.pagePreviousButton = builderObject!Button(pageBuilder, "page", "pagePreviousButton");
    document.pageNextButton = builderObject!Button(pageBuilder, "page", "pageNextButton");
    document.pageFirstButton = builderObject!Button(pageBuilder, "page", "pageFirstButton");
    document.pageLastButton = builderObject!Button(pageBuilder, "page", "pageLastButton");
    document.pageSizeCombo = builderObject!ComboBoxText(pageBuilder, "page", "pageSizeCombo");
    document.treeSortCombo = builderObject!ComboBoxText(pageBuilder, "page", "treeSortCombo");
    document.viewModeCombo = builderObjectOrNull!ComboBoxText(pageBuilder, "page", "viewModeCombo");
    if (document.viewModeCombo is null)
    {
        document.viewModeCombo = new ComboBoxText();
        document.viewModeCombo.appendText("Tree + table");
        document.viewModeCombo.appendText("Tree only");
        document.viewModeCombo.appendText("Blob table only");
        ui.pageBar.packStart(document.viewModeCombo, false, false, 0);
        document.viewModeCombo.show();
    }
    document.pageStatus = builderObject!Label(pageBuilder, "page", "pageStatus");
    document.pageBar.setVisible(false);
    document.rowDetails = builderObject!Label(pageBuilder, "page", "rowDetails");
    document.status = builderObject!Label(pageBuilder, "page", "status");
    document.perfStatus = builderObject!Label(pageBuilder, "page", "perfStatus");
    document.fileMetaStatus = builderObject!Label(pageBuilder, "page", "fileMetaStatus");

    return ui;
}
