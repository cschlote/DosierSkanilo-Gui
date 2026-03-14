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

import std.array : appender;
import std.conv : to;
import std.file : exists, readText;
import std.format : format;
import std.json : JSONType, JSONValue, parseJSON;
import std.string : join;

struct BlobRow {
    string primaryFileName;
    ulong fileSize;
    string sha1;
    size_t fileCount;
    bool hasMedia;
    string fileType;
}

ulong jsonAsULong(JSONValue value) {
    if (value.type == JSONType.integer) {
        return cast(ulong) value.integer;
    }
    if (value.type == JSONType.uinteger) {
        return value.uinteger;
    }
    if (value.type == JSONType.float_) {
        return cast(ulong) value.floating;
    }
    return 0;
}

string firstFileNameFromSpecs(JSONValue[] specs) {
    foreach (spec; specs) {
        if (spec.type != JSONType.object) {
            continue;
        }
        auto obj = spec.object;
        if ("fileName" in obj) {
            return (*("fileName" in obj)).str;
        }
    }
    return "";
}

BlobRow rowFromJsonObject(JSONValue objValue) {
    BlobRow row;
    if (objValue.type != JSONType.object) {
        return row;
    }

    auto obj = objValue.object;

    if ("fileSize" in obj) {
        row.fileSize = jsonAsULong(*("fileSize" in obj));
    }

    if ("checkSums" in obj && (*("checkSums" in obj)).type == JSONType.object) {
        auto checksums = (*("checkSums" in obj)).object;
        if ("sha1sum_b64" in checksums) {
            row.sha1 = (*("sha1sum_b64" in checksums)).str;
        }
    }
    if (row.sha1.length == 0 && "sha1sum_b64" in obj) {
        row.sha1 = (*("sha1sum_b64" in obj)).str;
    }

    if ("fileSpecs" in obj && (*("fileSpecs" in obj)).type == JSONType.array) {
        auto specs = (*("fileSpecs" in obj)).array;
        row.fileCount = specs.length;
        row.primaryFileName = firstFileNameFromSpecs(specs);
    } else if ("fileNames" in obj && (*("fileNames" in obj)).type == JSONType.array) {
        auto names = (*("fileNames" in obj)).array;
        row.fileCount = names.length;
        if (names.length > 0) {
            row.primaryFileName = names[0].str;
        }
    } else if ("fileName" in obj) {
        row.primaryFileName = (*("fileName" in obj)).str;
        row.fileCount = row.primaryFileName.length == 0 ? 0 : 1;
    }

    row.hasMedia = false;
    if ("mediaInfoSig" in obj && (*("mediaInfoSig" in obj)).type == JSONType.object) {
        row.hasMedia = true;
    }
    if (!row.hasMedia && "mediaInfo" in obj && (*("mediaInfo" in obj)).type == JSONType.array) {
        row.hasMedia = (*("mediaInfo" in obj)).array.length > 0;
    }

    if ("fileType" in obj) {
        row.fileType = (*("fileType" in obj)).str;
    }

    return row;
}

BlobRow[] extractRowsFromRoot(JSONValue root) {
    JSONValue[] blobs;

    if (root.type == JSONType.array) {
        blobs = root.array;
    } else if (root.type == JSONType.object) {
        auto rootObj = root.object;
        if ("dataArray" in rootObj && (*("dataArray" in rootObj)).type == JSONType.array) {
            blobs = (*("dataArray" in rootObj)).array;
        }
    }

    auto rowsAcc = appender!(BlobRow[])();
    foreach (blob; blobs) {
        if (blob.type != JSONType.object) {
            continue;
        }
        rowsAcc.put(rowFromJsonObject(blob));
    }
    return rowsAcc.data;
}

string rowsToDisplayText(string filePath, const(BlobRow)[] rows) {
    auto lines = appender!(string[])();
    lines.put(format("Loaded file: %s", filePath));
    lines.put(format("Blob count: %s", rows.length));
    lines.put("");
    lines.put("# | Size (bytes) | Files | Media | SHA1 (base64) | Primary file");
    lines.put("--+--------------+-------+-------+---------------+-------------------------------");

    foreach (idx, row; rows) {
        auto media = row.hasMedia ? "yes" : "no";
        auto sha = row.sha1.length > 0 ? row.sha1 : "-";
        auto fileName = row.primaryFileName.length > 0 ? row.primaryFileName : "-";
        lines.put(format("%s | %s | %s | %s | %s | %s", idx + 1, row.fileSize, row.fileCount, media, sha, fileName));
    }

    return lines.data.join("\n");
}

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

    toolbar.packStart(pathEntry, true, true, 0);
    toolbar.packStart(btnLoad, false, false, 0);

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

    void loadFromPath() {
        auto filePath = pathEntry.getText();
        if (!exists(filePath)) {
            status.setText(format("File not found: %s", filePath));
            output.getBuffer().setText("");
            return;
        }

        try {
            const content = readText(filePath);
            const parsed = parseJSON(content);
            const rows = extractRowsFromRoot(parsed);
            output.getBuffer().setText(rowsToDisplayText(filePath, rows));
            status.setText(format("Loaded %s blobs from %s", rows.length, filePath));
        } catch (Exception ex) {
            output.getBuffer().setText("");
            status.setText(format("Failed to parse JSON: %s", ex.msg));
        }
    }

    btnLoad.addOnClicked((Button _) {
        loadFromPath();
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
