module ui.tablecolumns;

import gtk.CellRendererText;
import gtk.Label;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.c.types : GtkTreeViewColumnSizing;

enum int MAIN_TABLE_FIXED_COLUMN_WIDTH = 44;

import ui.documenttab : DocumentTab, COL_INDEX, COL_FILE_SIZE, COL_CHECKSUM_SET,
    COL_FILE_TYPE, COL_MEDIA_INFO, COL_HAS_ARCHIVE, COL_HAS_TORRENT,
    COL_INDEX_SORT, COL_FILE_SIZE_SORT;

/** Setzt die Resizability aller Hauptspalten der Blob-Tabelle. */
void setTableColumnsResizable(DocumentTab document, bool resizable)
{
    if (document is null || document.tableView is null)
    {
        return;
    }

    foreach (i; 0 .. 7)
    {
        auto col = document.tableView.getColumn(i);
        if (col !is null)
        {
            col.setResizable(resizable);
        }
    }
}

/** Configure columns for the main result table. */
void configureTableColumns(TreeView treeView)
{
    void addTextColumn(string title, string tooltip, int modelColumn, int sortColumn = -1)
    {
        auto renderer = new CellRendererText();
        auto xalign = (modelColumn == COL_INDEX || modelColumn == COL_FILE_SIZE) ? 1.0f : 0.5f;
        renderer.setAlignment(xalign, 0.5f);
        auto column = new TreeViewColumn();
        auto headerLabel = new Label(title);
        headerLabel.setTooltipText(tooltip);
        headerLabel.setXalign(0.5f);
        headerLabel.show();
        column.setWidget(headerLabel);
        column.packStart(renderer, false);
        column.addAttribute(renderer, "text", modelColumn);
        column.setSortColumnId(sortColumn >= 0 ? sortColumn : modelColumn);
        column.setResizable(false);
        column.setAlignment(xalign);
        column.setExpand(false);
        column.setSizing(
            modelColumn == COL_HAS_ARCHIVE || modelColumn == COL_HAS_TORRENT
                ? GtkTreeViewColumnSizing.FIXED : GtkTreeViewColumnSizing.AUTOSIZE
        );
        if (modelColumn == COL_HAS_ARCHIVE || modelColumn == COL_HAS_TORRENT)
        {
            column.setFixedWidth(MAIN_TABLE_FIXED_COLUMN_WIDTH);
        }
        column.setClickable(true);
        treeView.appendColumn(column);
    }

    addTextColumn("#", "Index number", COL_INDEX, COL_INDEX_SORT);
    addTextColumn("Sz", "File size", COL_FILE_SIZE, COL_FILE_SIZE_SORT);
    addTextColumn("Chk", "Checksums", COL_CHECKSUM_SET);
    addTextColumn("FT", "File type", COL_FILE_TYPE);
    addTextColumn("Med", "Media information", COL_MEDIA_INFO);
    addTextColumn("AR", "Archive", COL_HAS_ARCHIVE);
    addTextColumn("TO", "Torrent", COL_HAS_TORRENT);

    treeView.setHeadersClickable(true);
}

/** Configure the known-files detail table with compact fixed columns. */
void configureKnownFilesColumns(TreeView treeView)
{
    void addColumn(string title, int modelColumn, bool expand)
    {
        auto renderer = new CellRendererText();
        renderer.setAlignment(0.0f, 0.5f);
        auto column = new TreeViewColumn();
        column.setTitle(title);
        column.packStart(renderer, true);
        column.addAttribute(renderer, "text", modelColumn);
        column.setResizable(false);
        column.setExpand(expand);
        column.setSizing(GtkTreeViewColumnSizing.AUTOSIZE);
        treeView.appendColumn(column);
    }

    addColumn("Known file", 0, true);
    addColumn("Last modified", 1, false);
    treeView.setHeadersClickable(false);
}
