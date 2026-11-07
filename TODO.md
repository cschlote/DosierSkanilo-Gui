# GUI Work Plan

Current GUI work and GUI-owned follow-ups. Shared backend operations are planned
in the backend's
[`docs/SQLITE-IMPLEMENTATION-PLAN.md`](https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md);
completed behavior is listed in [`CHANGELOG.md`](CHANGELOG.md) and summarized in
[`docs/GUI-REDESIGN.md`](docs/GUI-REDESIGN.md).

## Current status (2026-11-07)

- Version `0.12.1`; JSON and repository tabs both use `CatalogBackend`.
- JSON tabs have explicit document sessions with modified markers,
  Save/Revert, and save/discard/cancel prompts; SQLite tabs remain
  transactional.
- The main tree expands archive files lazily, synthesizes inner archive
  directories, expands on the first selection click, and previews/extracts
  members through the shared cache.
- The GUI Xvfb display job and the shared CLI/GTK operation matrix are green on
  `testing` and `main`. GUI verification: 76 tests, coverage 36.43 %, build
  clean.
- Documentation and Ddoc headers were refreshed on 2026-11-06.

## P0 — Prepare the next GUI release

Target: `0.12.1` (patch release for large-directory page loading and the
reverted GtkD model cleanup since `0.12.0`).

- [x] Confirm the paired backend release version and run
      [`DosierSkanilo/docs/RELEASE-CHECKLIST.md`](https://github.com/cschlote/DosierSkanilo/blob/main/docs/RELEASE-CHECKLIST.md)
      end to end.
- [x] Move `## Unreleased` to `## Release 0.11.0` in `CHANGELOG.md`, update the
      package version, and commit the release notes.
- [x] Create the annotated `v0.11.0` tag after the backend tag is ready; verify
      that the tag workflow validates tag/VERSION/CHANGELOG and publishes the
      release.
- [x] Re-run the Xvfb display suite and the 95,001-row JSON/SQLite smoke loads
      as release evidence.
- [ ] Update packaging metadata (Arch, Fedora, Flatpak) for `0.11.0`, verify
      the paired Flatpak/source archive hashes, and launch the installed
      package.

## P1 — Finish verification and performance work

- [ ] Profile per-batch rendering of the 95,001-row table on a display and
      record the result in `TODO.md`/the benchmark notes. Headless filter/tree
      and allocation numbers are already recorded.
- [ ] Confirm the final WP-09.5 CLI/GUI result, progress, cancellation, error,
      refresh, and explicit storage-mode parity evidence stays complete when
      either HMI changes; keep the backend parity table in sync.
- [ ] Investigate preview failures for filenames with heavy UTF-8 use and for
      RAR archives; capture the failing external-tool command and stderr.
- [ ] Re-run the shared display self-tests after any tree/preview change:
      archive expansion, member preview, JSON save/reload, and repository
      operation refresh.

## P1 — Stability and UX follow-ups

### Splitter persistence and sizing

- [ ] Reproduce the top-level splitter returning to an extreme position after a
      fresh load, reload, tab switch, and application restart.
- [ ] Reproduce preview/details splitter restoration after those lifecycle
      transitions, including startup before the first real GTK allocation.
- [ ] Define which saved position wins (new-window default versus per-window
      restored value), clamp only after a usable allocation, and avoid saving
      transient/unallocated positions.
- [x] Verify the pane clamp keeps both panes usable at narrow extents; covered
      by `ui.splitterlayout` unit tests.
- [ ] Verify the chosen split positions survive a restart.

### Video preview realization and window growth

- [ ] Reproduce first-selection video playback where audio starts but the video
      frame stays blank; capture widget realization, sink attachment, and
      allocation order in verbose logs.
- [ ] Reproduce horizontal window growth when switching between video rows and
      determine whether the sink, aspect frame, or preferred video size requests
      the extra width.
- [ ] Ensure a failed or delayed video sink falls back without blocking other
      preview controls or changing the parent window's requested width.
- [ ] Verify first and subsequent video selections on the supported GTK display
      backends, and retain audio/image preview behavior.

**Acceptance for both stability packages:** reproduction steps are documented,
the fix is verified through the GTK self-test or a repeatable manual test, and
verbose diagnostics make future allocation/sink failures understandable.

## P2 — Optional and delivery work

- [ ] Implement optional same-directory sibling prefetch, disabled by default,
      with cancellable bounded requests and the same cache leases as foreground
      preview/extraction. Add the sibling-prefetch cancellation test.
- [ ] Manually verify the `gtksink` → `ximagesink` preference on a Wayland
      session.
- [ ] Extend the release workflow with distribution artifacts and installation
      smoke checks for the supported packages.
- [ ] Investigate the previously noted CLI stdout/stderr ordering concern around
      `argsArray`; only add synchronization if a reproducible interleaving is
      found.
- [ ] Make module-level Ddoc headers consistent across all GUI modules
      (`Authors`/`License`), not only the recently touched files.
- [ ] Add a size guard/warning when opening very large JSON catalogs directly
      and point users to repository import; direct JSON tabs keep the whole
      catalog and derived index in memory.

## Completed work (compact record)

- **JSON filtering:** asynchronous projection, indexed child/file lookup,
  per-document filter persistence, Blob-table sort persistence, case/media/
  presence/sort parity, and clear/cancel lifecycle coverage.
- **Shared CLI/GTK operations:** target-aware Tools actions, background workers,
  progress, cancellation, pause/resume, refresh, lease retention, and display
  tests for synthetic scan/metadata/analyze operations.
- **TreeView node reuse:** canonical `TreeStore` retained behind
  `GtkTreeModelFilter`; stable IDs, ancestor visibility, and bounded reflow.
- **Archive tree and cache:** lazy member expansion, synthesized inner
  directories, first-click expansion, nested archives, shared preview leases,
  cache preferences, and shutdown/stale-session cleanup.
- **Backend-backed JSON views:** JSON tabs now use `CatalogBackend` for rows,
  tree, details, archive/torrent pages, and previews after binding a derived
  tree root; the legacy projection remains only for export/tests.
- **JSON document save semantics:** modified markers, Save (Ctrl+S), Revert to
  Stored, close/reload prompts, recovery copy, and external-edit conflicts.
- **UI maintenance:** CSS-based styling, builder cleanup, and the embedded
  video-sink fallback with an Xvfb check.
