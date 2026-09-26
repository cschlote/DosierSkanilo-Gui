# Open Issues

## Directory Tree Redesign

- Replace visible SQL paging with opaque source cursors and logical append-on-demand loading.
- Persist and restore the current file cursor used by Previous/Next navigation.
- Add archive/torrent-specific details actions and nested entry trees.
- Add archive and torrent child trees with lazy loading.
- Add specialized detail renderers and explicit analysis operations.

- The top-level splitter still snaps back to the maximum width after loading a file, so the current layout clamping is not stable enough.
- The preview pane can stay visually empty on first video selection even though audio already plays; the preview refresh path likely races widget realization and sink attachment.
- The preview/details splitter position is still not restored reliably, which suggests the current save/restore path needs a dedicated layout lifecycle pass.
- Switching between video rows still makes the window grow horizontally, so the embedded video area is still influencing the parent layout too much.

## TODO

- Follow up the GTK 3.22 UI baseline by replacing `overrideFont`-based monospace styling with CSS classes and a shared `CssProvider`.
- Remove the legacy `double-buffered` properties from the Glade preview widgets and rely on GTK's default rendering path.
- Rework embedded video preview sink selection so Wayland/X11 setups prefer a GTK-friendly sink such as `gtksink`, with `ximagesink` only as a fallback.
- Move more visual UI tuning from D code and per-widget properties into GTK style classes so the Builder layouts can drive appearance more consistently.
- Evaluate whether any repeated detail subtrees should become Builder templates or composite widgets.
- Keep expanding default widget state in Glade so D only mutates values when the runtime state actually changes.

## Next

- Add export actions (CSV/JSON subset)
- Add row activation action (copy path, open in file manager)
- Add unit tests for CLI help text and startup filter parsing
- Revisit the top-level splitter behavior and redesign it instead of patching around it

## Later

- Revisit whether any scanner/analysis actions should be embedded or kept in the CLI
- Add release packaging and tagging workflow
- Verify stdout/stderr ordering after moving `argsArray` to `__gshared`; a future race or interleaving issue may still surface.
