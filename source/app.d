module app;

import gtk.Main;
import gtk.Widget;
import gtk.Window;
import gtk.Box;
import gtk.Label;
import gtk.Button;
import gtk.Separator;
import gtk.c.types : Orientation;

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

    auto subtitle = new Label("Erster GTKD Stand: Projekt, Fenster und Basis-Layout.");
    subtitle.setXalign(0.0f);

    auto separator = new Separator(Orientation.HORIZONTAL);

    auto toolbar = new Box(Orientation.HORIZONTAL, 8);
    auto btnOpen = new Button("JSON oeffnen (TODO)");
    auto btnReload = new Button("Neu laden (TODO)");
    toolbar.packStart(btnOpen, false, false, 0);
    toolbar.packStart(btnReload, false, false, 0);

    auto status = new Label("Bereit. Naechster Schritt: Datei laden und Tabelle anzeigen.");
    status.setXalign(0.0f);

    root.packStart(title, false, false, 0);
    root.packStart(subtitle, false, false, 0);
    root.packStart(separator, false, false, 0);
    root.packStart(toolbar, false, false, 0);
    root.packStart(status, false, false, 0);

    window.add(root);
    window.showAll();

    Main.run();
    return 0;
}
