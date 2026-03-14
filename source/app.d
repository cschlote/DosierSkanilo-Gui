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
import gtk.ScrolledWindow;
import gtk.MenuBar;
import gtk.Menu;
import gtk.MenuItem;
import gtk.SeparatorMenuItem;
import gtk.AccelGroup;
import gtk.Dialog;
import gtk.CheckButton;
import gtk.AboutDialog;
import gtk.MessageDialog;
import gtk.c.types : Orientation, DialogFlags, ResponseType, ButtonsType, MessageType;

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

    auto accelGroup = new AccelGroup();
    window.addAccelGroup(accelGroup);

    auto root = new Box(Orientation.VERTICAL, 0);

    auto content = new Box(Orientation.VERTICAL, 10);
    content.setBorderWidth(10);

    auto title = new Label("DosierSkanilo Datafile Viewer");
    title.setXalign(0.0f);

    auto subtitle = new Label("Classic GTK shell with menus, shortcuts, preferences, and help.\n");
    subtitle.setXalign(0.0f);

    auto separator = new Separator(Orientation.HORIZONTAL);

    auto toolbar = new Box(Orientation.HORIZONTAL, 8);
    auto pathEntry = new Entry();
    pathEntry.setHexpand(true);
    pathEntry.setText("../DosierSkanilo/test/json_file_v2.json");

    auto btnLoad = new Button("Load JSON");
    auto btnLoadDupes = new Button("Load Duplicates Only");
    auto btnReload = new Button("Reload");

    auto filterEntry = new Entry();
    filterEntry.setHexpand(true);
    filterEntry.setPlaceholderText("Filter by filename or SHA1...");

    auto btnApplyFilter = new Button("Apply Filter");
    auto btnClearFilter = new Button("Clear Filter");

    toolbar.packStart(pathEntry, true, true, 0);
    toolbar.packStart(btnLoad, false, false, 0);
    toolbar.packStart(btnLoadDupes, false, false, 0);
    toolbar.packStart(btnReload, false, false, 0);
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

    bool prefDefaultDuplicatesOnly = false;
    bool prefAutoApplyFilter = true;
    bool prefCaseSensitiveFilter = false;

    auto menuBar = new MenuBar();

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
                "Showing %s/%s rows (%s mode, duplicate digest groups: %s, filter: %s, case-sensitive: %s)",
                rows.length,
                loadedRows.length,
                mode,
                loadedDuplicateGroups,
                filterLabel,
                prefCaseSensitiveFilter ? "yes" : "no"
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

    void applyFilterFromEntry() {
        if (loadedRows.length == 0) {
            status.setText("No loaded rows to filter.");
            return;
        }
        auto query = filterEntry.getText();
        auto filtered = filterRowsByText(loadedRows, query, prefCaseSensitiveFilter);
        renderRows(filtered, query);
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

            if (prefAutoApplyFilter && filterEntry.getText().length > 0) {
                applyFilterFromEntry();
            } else {
                renderRows(loadedRows);
            }
        } catch (Exception ex) {
            output.getBuffer().setText("");
            status.setText(format("Failed to parse JSON: %s", ex.msg));
        }
    }

    void showPreferencesDialog() {
        auto dialog = new Dialog(
            "Preferences",
            window,
            DialogFlags.MODAL,
            ["_Cancel", "_Save"],
            [ResponseType.CANCEL, ResponseType.OK]
        );

        auto contentArea = dialog.getContentArea();
        auto prefsBox = new Box(Orientation.VERTICAL, 8);
        prefsBox.setBorderWidth(8);

        auto optDefaultDupes = new CheckButton("Start normal loads in duplicate-only mode");
        optDefaultDupes.setActive(prefDefaultDuplicatesOnly);

        auto optAutoApply = new CheckButton("Auto-apply filter after load/reload");
        optAutoApply.setActive(prefAutoApplyFilter);

        auto optCaseSensitive = new CheckButton("Case-sensitive text filtering");
        optCaseSensitive.setActive(prefCaseSensitiveFilter);

        prefsBox.packStart(optDefaultDupes, false, false, 0);
        prefsBox.packStart(optAutoApply, false, false, 0);
        prefsBox.packStart(optCaseSensitive, false, false, 0);
        contentArea.packStart(prefsBox, true, true, 0);

        dialog.showAll();
        auto response = dialog.run();

        if (response == cast(int) ResponseType.OK) {
            prefDefaultDuplicatesOnly = optDefaultDupes.getActive();
            prefAutoApplyFilter = optAutoApply.getActive();
            prefCaseSensitiveFilter = optCaseSensitive.getActive();
            status.setText("Preferences saved.");
        }

        dialog.destroy();
    }

    void showShortcutsHelp() {
        auto dialog = new MessageDialog(
            window,
            DialogFlags.MODAL,
            MessageType.INFO,
            ButtonsType.CLOSE,
            "Keyboard Shortcuts\n\n" ~
            "Ctrl+O  Open JSON\n" ~
            "Ctrl+D  Open Duplicates Only\n" ~
            "Ctrl+R  Reload\n" ~
            "Ctrl+F  Apply Filter\n" ~
            "Ctrl+L  Clear Filter\n" ~
            "Ctrl+,  Preferences\n" ~
            "Ctrl+Q  Quit"
        );
        dialog.run();
        dialog.destroy();
    }

    void showAbout() {
        auto dialog = new AboutDialog();
        dialog.setTransientFor(window);
        dialog.setModal(true);
        dialog.setProgramName("DosierSkanilo GUI");
        dialog.setVersion("0.1.0");
        dialog.setComments("Classic GTK desktop frontend for DosierSkanilo JSON data files.");
        dialog.setAuthors(["Carsten Schlote"]);
        dialog.run();
        dialog.destroy();
    }

    auto fileMenuItem = new MenuItem("_File");
    auto fileMenu = new Menu();
    fileMenuItem.setSubmenu(fileMenu);

    auto fileOpen = new MenuItem((MenuItem _) {
        loadFromPath(prefDefaultDuplicatesOnly);
    }, "_Open JSON", "file.open", true, accelGroup, 'o');

    auto fileOpenDupes = new MenuItem((MenuItem _) {
        loadFromPath(true);
    }, "Open _Duplicates Only", "file.open.dupes", true, accelGroup, 'd');

    auto fileReload = new MenuItem((MenuItem _) {
        loadFromPath(loadedDuplicatesOnly);
    }, "_Reload", "file.reload", true, accelGroup, 'r');

    auto fileQuit = new MenuItem((MenuItem _) {
        Main.quit();
    }, "_Quit", "file.quit", true, accelGroup, 'q');

    fileMenu.append(fileOpen);
    fileMenu.append(fileOpenDupes);
    fileMenu.append(fileReload);
    fileMenu.append(new SeparatorMenuItem());
    fileMenu.append(fileQuit);
    menuBar.append(fileMenuItem);

    auto editMenuItem = new MenuItem("_Edit");
    auto editMenu = new Menu();
    editMenuItem.setSubmenu(editMenu);

    auto editApplyFilter = new MenuItem((MenuItem _) {
        applyFilterFromEntry();
    }, "_Apply Filter", "edit.applyFilter", true, accelGroup, 'f');

    auto editClearFilter = new MenuItem((MenuItem _) {
        filterEntry.setText("");
        renderRows(loadedRows);
    }, "C_lear Filter", "edit.clearFilter", true, accelGroup, 'l');

    auto editPreferences = new MenuItem((MenuItem _) {
        showPreferencesDialog();
    }, "_Preferences", "edit.preferences", true, accelGroup, ',');

    editMenu.append(editApplyFilter);
    editMenu.append(editClearFilter);
    editMenu.append(new SeparatorMenuItem());
    editMenu.append(editPreferences);
    menuBar.append(editMenuItem);

    auto helpMenuItem = new MenuItem("_Help");
    auto helpMenu = new Menu();
    helpMenuItem.setSubmenu(helpMenu);

    auto helpShortcuts = new MenuItem((MenuItem _) {
        showShortcutsHelp();
    }, "_Keyboard Shortcuts", true);

    auto helpAbout = new MenuItem((MenuItem _) {
        showAbout();
    }, "_About", true);

    helpMenu.append(helpShortcuts);
    helpMenu.append(new SeparatorMenuItem());
    helpMenu.append(helpAbout);
    menuBar.append(helpMenuItem);

    btnLoad.addOnClicked((Button _) {
        loadFromPath(prefDefaultDuplicatesOnly);
    });

    btnLoadDupes.addOnClicked((Button _) {
        loadFromPath(true);
    });

    btnReload.addOnClicked((Button _) {
        loadFromPath(loadedDuplicatesOnly);
    });

    btnApplyFilter.addOnClicked((Button _) {
        applyFilterFromEntry();
    });

    btnClearFilter.addOnClicked((Button _) {
        filterEntry.setText("");
        renderRows(loadedRows);
    });

    pathEntry.addOnActivate((Entry _) {
        loadFromPath(prefDefaultDuplicatesOnly);
    });

    filterEntry.addOnActivate((Entry _) {
        applyFilterFromEntry();
    });

    content.packStart(title, false, false, 0);
    content.packStart(subtitle, false, false, 0);
    content.packStart(separator, false, false, 0);
    content.packStart(toolbar, false, false, 0);
    content.packStart(scroll, true, true, 0);
    content.packStart(status, false, false, 0);

    root.packStart(menuBar, false, false, 0);
    root.packStart(content, true, true, 0);

    window.add(root);
    window.showAll();

    Main.run();
    return 0;
}
