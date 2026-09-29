/** Application-wide CSS helpers for GTK widgets used by the GUI. */
module ui.styles;

import gdk.Screen;
import gtk.CssProvider;
import gtk.StyleContext;
import gtk.c.types : GTK_STYLE_PROVIDER_PRIORITY_APPLICATION;

private __gshared CssProvider applicationCssProvider;

/** Install the shared CSS classes used by the application.
 *
 * Params: None.
 * Returns: Nothing.
 * Throws: None.
 */
void installApplicationCss()
{
    if (applicationCssProvider !is null)
    {
        return;
    }

    auto screen = Screen.getDefault();
    if (screen is null)
    {
        return;
    }

    auto provider = new CssProvider();
    provider.loadFromData(q"CSS
.digest-entry {
    font-family: Monospace;
    font-size: 10pt;
}

.document-status-label {
    padding-top: 2px;
    padding-bottom: 2px;
}

.preview-title {
    font-weight: 600;
}

.preview-summary {
    font-size: 0.95em;
}

.preview-summary-monospace {
    font-family: monospace;
    font-size: 9pt;
}
CSS");

    StyleContext.addProviderForScreen(screen, provider, GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    applicationCssProvider = provider;
}
