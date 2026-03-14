module app;

import gtk.Main;
import gtk.Widget;
import gtk.Window;
import gtk.Box;
import gtk.Label;
import gtk.Button;
import gtk.Separator;
import gtk.Entry;
import gtk.TextView;
import gtk.TextBuffer;
import gtk.ScrolledWindow;
import gtk.c.types : Orientation;

import std.file : exists, readText;
import std.format : format;
import std.json : parseJSON;

import io.dosierjson : extractRowsFromRoot;
import model.blobrow : BlobRow;
import view.textreport : rowsToDisplayText, countDuplicateDigestGroups, filterDuplicateRows, filterRowsByText;

int main(string[] args) {
    Main.init(args);

    auto window = new Window("DosierSkanilo GUI");
    window.setDefaultSize(960, 640);
    window.addOnDestroy((Widget _) {
        Main.quit();
    });

    auto root = new Box(Orientation.VERTICAL, 10);
    root.setBorderWidth(12);

    auto title = new Label("DosierSkanilo Datenfile Viewer");
    title.setXalign(0.0f);

    auto subtitle = new Label("Load and inspect DosierSkanilo JSON data files (v0/v1/v2).\n");
    subtitle.setXalign(0.0f);

    auto separator = new Separator(Orientation.HORIZONTAL);

    auto toolbar = new Box(Orientation.HORIZONTAL, 8);
    auto pathEntry = new Entry();
    pathEntry.setHexpand(true);
    pathEntry.setText("../DosierSkanilo/test/json_file_v2.json");

    auto btnLoad = new Button("Load JSON");
    auto btnLoadDupes = new Button("Load Duplicates Only");
    auto filterEntry = new Entry();
    filterEntry.setHexpand(true);
    filterEntry.setPlaceholderText("Filter by filename or SHA1...");

    auto btnApplyFilter = new Button("Apply Filter");
    auto btnClearFilter = new Button("Clear Filter");

    toolbar.packStart(pathEntry, true, true, 0);
    toolbar.packStart(btnLoad, false, false, 0);
    toolbar.packStart(btnLoadDupes, false, false, 0);
    toolbar.packStart(filterEntry, true, true, 0);
    toolbar.packStart(btnApplyFilter, false, false, 0);
    toolbar.packStart(btnClearFilter, false, false, 0);

    auto output = new TextView();
    output.setEditable(false);
    output.setMonospace(true);
    output.getBuffer().setText("Ready. Enter a JSON path and click 'Load JSON'.");

    auto scroll = new ScrolledWindow(null, null);
    scroll.setVexpand(true);
    scroll.setHexpand(true);
    scroll.add(output);

    auto status = new Label("Ready.");
    status.setXalign(0.0f);

    BlobRow[] loadedRows;
    string loadedFilePath;
    size_t loadedDuplicateGroups;
    bool loadedDuplicatesOnly;

    void renderRows(const(BlobRow)[] rows, string filterLabel = "") {
        if (loadedFilePath.length == 0) {
            output.getBuffer().setText("No data loaded.");
            status.setText("Ready.");
            return;
        }

        output.getBuffer().setText(rowsToDisplayText(loadedFilePath, rows));
        auto mode = loadedDuplicatesOnly ? "duplicates" : "all";
        if (filterLabel.length > 0) {
            status.setText(format(
                "Showing %s/%s rows (%s mode, duplicate digest groups: %s, filter: %s)",
                rows.length,
                loadedRows.length,
                mode,
                loadedDuplicateGroups,
                filterLabel
            ));
            return;
        }

        status.setText(format(
            "Showing %s/%s rows (%s mode, duplicate digest groups: %s)",
            rows.length,
            loadedRows.length,
            mode,
            loadedDuplicateGroups
        ));
    }

    void loadFromPath(bool duplicatesOnly = false) {
        auto filePath = pathEntry.getText();
        if (!exists(filePath)) {
            status.setText(format("File not found: %s", filePath));
            output.getBuffer().setText("");
            return;
        }

        try {
            auto content = readText(filePath);
            auto parsed = parseJSON(content);
            auto allRows = extractRowsFromRoot(parsed);
            loadedDuplicateGroups = countDuplicateDigestGroups(allRows);
            loadedRows = duplicatesOnly ? filterDuplicateRows(allRows) : allRows;
            loadedFilePath = filePath;
            loadedDuplicatesOnly = duplicatesOnly;
            renderRows(loadedRows);
        } catch (Exception ex) {
            output.getBuffer().setText("");
            status.setText(format("Failed to parse JSON: %s", ex.msg));
        }
    }

    btnLoad.addOnClicked((Button _) {
        loadFromPath();
    });

    btnLoadDupes.addOnClicked((Button _) {
        loadFromPath(true);
    });

    btnApplyFilter.addOnClicked((Button _) {
        if (loadedRows.length == 0) {
            status.setText("No loaded rows to filter.");
            return;
        }
        auto query = filterEntry.getText();
        auto filtered = filterRowsByText(loadedRows, query);
        renderRows(filtered, query);
    });

    btnClearFilter.addOnClicked((Button _) {
        filterEntry.setText("");
        renderRows(loadedRows);
    });

    root.packStart(title, false, false, 0);
    root.packStart(subtitle, false, false, 0);
    root.packStart(separator, false, false, 0);
    root.packStart(toolbar, false, false, 0);
    root.packStart(scroll, true, true, 0);
    root.packStart(status, false, false, 0);

    window.add(root);
    window.showAll();

    Main.run();
    return 0;
}
