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
import view.textreport : rowsToDisplayText, countDuplicateDigestGroups, filterDuplicateRows;

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

    toolbar.packStart(pathEntry, true, true, 0);
    toolbar.packStart(btnLoad, false, false, 0);
    toolbar.packStart(btnLoadDupes, false, false, 0);

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

    void loadFromPath(bool duplicatesOnly = false) {
        auto filePath = pathEntry.getText();
        if (!exists(filePath)) {
            status.setText(format("File not found: %s", filePath));
            output.getBuffer().setText("");
            return;
        }

        try {
            const content = readText(filePath);
            const parsed = parseJSON(content);
            const allRows = extractRowsFromRoot(parsed);
            const duplicateGroups = countDuplicateDigestGroups(allRows);
            const rows = duplicatesOnly ? filterDuplicateRows(allRows) : allRows;
            output.getBuffer().setText(rowsToDisplayText(filePath, rows));
            status.setText(format(
                "Loaded %s/%s blobs from %s (duplicate digest groups: %s)",
                rows.length,
                allRows.length,
                filePath,
                duplicateGroups
            ));
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
