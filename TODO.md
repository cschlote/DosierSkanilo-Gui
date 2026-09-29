# Open Issues

## Directory Tree Redesign

- [x] Replace eager root-summary enumeration in `RepositoryDirectorySource`
  with bounded directory/file count and aggregate-size queries.
- [x] Give concurrent background source operations independent repository read
  connections instead of sharing the `RepositoryDirectorySource` connection.
- [x] Stress-test simultaneous repository tree and detail requests against an
  81-file repository.
- [x] Exercise virtual Blob-table reads across 1,000 rows in both directions and
  verify the four-chunk cache remains bounded after eviction/reload.
- [x] Persist and restore the current file cursor, directory, sort order, and
  per-document filter state used by Previous/Next navigation.
- [x] Exercise archive and torrent adapter continuation with more than 250
  nested entries and verify a later-page full path.
- [x] Exercise TreeView file-row activation and clipboard callback with a
  later-page full nested path.
- [x] Exercise GTK continuation-marker activation and verify its requested page
  offset and selection/request tokens.
- [x] Test stale-result rejection after the GTK selection token changes before
  an asynchronous page reply is applied.
- [x] Recover expanded repository directories whose loading placeholder remained
  after child rows were inserted; query dispatch is deduplicated while pending.
- [x] Add a fallback detail renderer with file identity, available checksums, and
  an explicit message when no specialized metadata exists.
- [ ] Implement CLI/GTK operation parity over shared backend operations:
  - [ ] WP-09.1: Freeze common request, result, progress, and cancellation types.
  - [ ] WP-09.2: Add safe progress/cancel checkpoints to backend SQLite and JSON
    services.
  - [ ] WP-09.3: Adapt CLI output and Ctrl-C to the shared operation API.
  - [ ] WP-09.4: Add GTK Tools actions and a background task/status manager.
  - [ ] WP-09.5: Verify CLI/GUI parity, cancellation, and source refresh.

- The top-level splitter still snaps back to the maximum width after loading a
  file, so the current layout clamping is not stable enough.
- The preview pane can stay visually empty on first video selection even though
  audio already plays; the preview refresh path likely races widget realization
  and sink attachment.
- The preview/details splitter position is still not restored reliably, which
  suggests the current save/restore path needs a dedicated layout lifecycle
  pass.
- Switching between video rows still makes the window grow horizontally, so
  the embedded video area is still influencing the parent layout too much.

## TODO

- Follow up the GTK 3.22 UI baseline by replacing `overrideFont`-based
  monospace styling with CSS classes and a shared `CssProvider`.
- Remove the legacy `double-buffered` properties from the Glade preview widgets
  and rely on GTK's default rendering path.
- Rework embedded video preview sink selection so Wayland/X11 setups prefer a
  GTK-friendly sink such as `gtksink`, with `ximagesink` only as a fallback.
- Move more visual UI tuning from D code and per-widget properties into GTK
  style classes so the Builder layouts can drive appearance more consistently.
- Evaluate whether any repeated detail subtrees should become Builder templates
  or composite widgets.
- Keep expanding default widget state in Glade so D only mutates values when
  the runtime state actually changes.

## Next

- [x] Exercise the virtual Blob-table cache through long forward/backward row
  access across cache evictions.
- [x] Exercise GTK TreeView scrolling to distant rows and back to evicted chunks.
- [x] Add directory/file context actions for opening files externally and
  opening directories or containing folders in the file manager.
- [x] Add CSV and JSON exports for the active tab's filtered row subset.
- [x] Cover every registered startup option in the CLI help/parser test.
- Revisit the top-level splitter behavior and redesign it instead of patching
  around it.

## Later

- Revisit whether any scanner/analysis actions should be embedded or kept in the
  CLI.
- Add release packaging and tagging workflow
- Verify stdout/stderr ordering after moving `argsArray` to `__gshared`; a future
  race or interleaving issue may still surface.
