# GUI Work Plan

Current GUI work and GUI-owned follow-ups. Shared backend operations are planned
in the backend's
[`docs/SQLITE-IMPLEMENTATION-PLAN.md`](https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md);
completed behavior is listed in [`CHANGELOG.md`](CHANGELOG.md) and summarized in
[`docs/GUI-REDESIGN.md`](docs/GUI-REDESIGN.md).

## Current status (2026-11-08)

- Version `0.12.1`; JSON and repository tabs both use `CatalogBackend`.
- JSON tabs have explicit document sessions with modified markers,
  Save/Revert, and save/discard/cancel prompts; SQLite tabs remain
  transactional.
- The main tree expands archive files lazily, synthesizes inner archive
  directories, expands on the first selection click, and previews/extracts
  members through the shared cache.
- The GUI Xvfb display job and the shared CLI/GTK operation matrix are green on
  `main`; `testing` mirrors the same commit without deployments. GUI
  verification: 76 tests, coverage 36.43 %, build clean.
- Documentation and Ddoc headers are complete: every documentable public,
  package, and private declaration has Ddoc (verified 2026-11-08).

## P0 — Prepare the next GUI release

Target: next version after `0.12.1`; choose patch or minor at release time based
on the user-facing changes since the last tag.

- [x] Release `0.12.1` is complete: changelog, paired backend release,
      Arch/Fedora/Debian/Flatpak metadata, and the Flatpak source hash are
      committed.
- [ ] Run the
      [`backend release checklist`](https://github.com/cschlote/DosierSkanilo/blob/main/docs/RELEASE-CHECKLIST.md)
      end to end for the next paired release.
- [ ] Re-run the Xvfb display suite and the 95,001-row JSON/SQLite smoke loads
      as release evidence.
- [ ] Verify installation from the packaged artifacts after the next release.

## P1 — Finish verification and performance work

- [ ] Profile per-batch rendering of the 95,001-row table on a display and
      record the result in `TODO.md`/the benchmark notes. Headless filter/tree
      and allocation measurements can be reproduced with
      `./scripts/benchmark-filters.sh`.
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

- [ ] Implement optional same-directory sibling prefetch with cancellable
      bounded requests and the same cache leases as foreground
      preview/extraction. Keep it disabled by default and add the
      sibling-prefetch cancellation test.
- [ ] Manually verify the `gtksink` → `ximagesink` preference on a Wayland
      session.
- [ ] Extend the release workflow with distribution artifacts and installation
      smoke checks for the supported packages.
- [ ] Investigate the previously noted CLI stdout/stderr ordering concern around
      `argsArray`; only add synchronization if a reproducible interleaving is
      found.
- [x] Make module-level Ddoc headers consistent across all GUI modules
      (`Authors`/`Copyright`/`License`); verified across all tracked `.d` files.
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
