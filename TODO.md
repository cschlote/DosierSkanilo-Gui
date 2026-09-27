# Open Issues

## Directory Tree Redesign

- Validate the virtual Blob-table cache through interactive long scroll-forward
  and scroll-back sessions on a large repository; tune the four-chunk cache only
  if measurements show it is needed.
- Persist and restore the current file cursor used by Previous/Next navigation.
- Exercise archive and torrent continuation with more than 250 nested entries,
  including activating a later-page file and copying its full path.
- Finish specialized detail renderers and expose analysis as explicit operations.

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

- Add an integration fixture with more than 250 archive and torrent entries and
  verify continuation, selection changes during an in-flight request, and path
  copying on a later page.
- Exercise real TreeView scrolling beyond four cached blob chunks and back to an
  evicted chunk.
- Persist and restore the active file cursor with its filter and sort state.
- Add directory/file context actions, including open-in-file-manager; archive
  and torrent leaf activation already copies the nested path.
- Add export actions (CSV/JSON subset) and unit tests for CLI help text.
- Revisit the top-level splitter behavior and redesign it instead of patching around it

## Later

- Revisit whether any scanner/analysis actions should be embedded or kept in the CLI
- Add release packaging and tagging workflow
- Verify stdout/stderr ordering after moving `argsArray` to `__gshared`; a future race or interleaving issue may still surface.
