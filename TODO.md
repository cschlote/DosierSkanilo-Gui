# GUI Work Plan

Current GUI work and GUI-owned follow-ups. Shared backend operations are planned
in the backend's
[`docs/SQLITE-IMPLEMENTATION-PLAN.md`](https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md);
completed behavior is listed in [`CHANGELOG.md`](CHANGELOG.md) and summarized in
[`docs/GUI-REDESIGN.md`](docs/GUI-REDESIGN.md).

## Current status (2026-11-17)

- Version `0.14.1`; JSON and repository tabs both use `CatalogBackend`.
- JSON tabs have explicit document sessions with modified markers,
  Save/Revert, and save/discard/cancel prompts; SQLite tabs remain
  transactional.
- The main tree expands archive files lazily, synthesizes inner archive
  directories, expands on the first selection click, and previews/extracts
  members through the shared cache. Optional same-directory sibling prefetch
  warms neighboring members behind a preview into the cache (disabled by
  default).
- The GUI Xvfb display job and the shared CLI/GTK operation matrix are green on
  `main`; `testing` mirrors the same commit without deployments. GUI
  verification: 78 tests, coverage 36.90 %, build clean.
- Documentation and Ddoc headers are complete: every documentable public,
  package, and private declaration has Ddoc (verified 2026-11-08).

## P0 — Prepare the next GUI release

Target: `0.14.1` (packaging patch, paired with backend `26.17.1`).

- [x] Release `0.13.0` is complete: changelog, paired backend release,
      Arch/Fedora/Debian/Flatpak metadata, and the Flatpak source hash are
      committed.
- [x] Release `0.13.1` is complete: paired with backend `26.16.0`,
      changelog and packaging updated, Flatpak source hash refreshed.
- [ ] Run the
      [`backend release checklist`](https://github.com/cschlote/DosierSkanilo/blob/main/docs/RELEASE-CHECKLIST.md)
      end to end for the next paired release. Automated gates, tags, Flatpak
      hash pins, and Debian/Arch/Fedora package verification are complete; the
      GUI Flatpak draft and the manual UI acceptance remain.
- [x] Re-run the Xvfb display suite and the 95,001-row JSON/SQLite smoke loads
      as release evidence.
- [x] Verify installation from the packaged artifacts after the next release:
      Debian, Arch, and Fedora packages build, install, start, and remove
      cleanly. The GUI Flatpak manifest remains a documented draft.

## Release 0.14.0 — sibling prefetch and preview stability

- [x] GUI full gate: 78 tests, coverage 36.90 %, build clean; Xvfb display
      suite passed with the JSON and SQLite 95,001-record smoke loads.
- [x] Filter benchmark (`1000 10000 100000`) reviewed: 35.2 ms filter and
      74.0 ms tree projection at 100,000 rows, 22.9 MiB peak.
- [x] `docs/skeleton.html`, `helpdialogs.d`, and the Arch/Fedora/Debian/Flatpak
      metadata use `0.14.0` and the paired backend `26.17.1`.
- [x] Verify installation from the packaged artifacts after the Flatpak hash
      follow-up commit; the `0.14.1` patch release carries the corrected
      recipes.

## Release 0.14.1 — packaging patch

- [x] GUI full gate: 78 tests, coverage 36.90 %, build clean; Xvfb display
      suite passed.
- [x] Debian `0.14.1-1`, Arch, and Fedora packages build, install, start, and
      remove cleanly in their native containers.
- [x] Release commit, tag `v0.14.1`, Flatpak hash pin, and GitHub release are
      published.

## P1 — Finish verification and performance work

- [ ] Profile per-batch rendering of the 95,001-row table on a display and
      record the result in `TODO.md`/the benchmark notes. Headless filter/tree
      and allocation measurements can be reproduced with
      `./scripts/benchmark-filters.sh`.
- [ ] Confirm the final WP-09.5 CLI/GUI result, progress, cancellation, error,
      refresh, and explicit storage-mode parity evidence stays complete when
      either HMI changes; keep the backend parity table in sync.
- [x] Preview failures for filenames with heavy UTF-8 use and for RAR
      archives are fixed in the backend (2026-11-15, released with the next
      backend patch): `unrar` listing runs under `LC_ALL=C` replaced every
      non-ASCII byte of member names with `?` (now a UTF-8-capable C locale),
      and the deep archive scan skipped every RAR archive because the
      encrypted-header check used `find` instead of `canFind`. No GUI code
      change was needed.
- [ ] Re-run the shared display self-tests after any tree/preview change:
      archive expansion, member preview, JSON save/reload, and repository
      operation refresh.

## P1 — Backend Major 27 format cleanup

- [ ] Rebuild and retest the GUI against backend 27 after legacy JSON v0–v4 and
      SQLite schema migrations 1–5 are removed. Verify JSON v5 tabs, schema v6
      repositories, document save/reload, backup/restore, and all shared
      operation paths.
- [ ] Remove GUI wording that implies legacy JSON versions are still supported
      and update the error/help text for rejected old catalogs.

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

- [x] First-selection video playback starts with visible video and audio;
      verified on 2026-11-16 against real AVI files. The fix came from the
      preview stability work: one reused GStreamer pipeline per tab, a bounded
      NULL wait before starting the next stream, and attaching the video sink
      window handle only in READY/PAUSED state.
- [ ] Reproduce horizontal window growth when switching between video rows and
      determine whether the sink, aspect frame, or preferred video size requests
      the extra width.
- [ ] Ensure a failed or delayed video sink falls back without blocking other
      preview controls or changing the parent window's requested width.
- [ ] Verify first and subsequent video selections on the supported GTK display
      backends, and retain audio/image preview behavior.

Known observation (2026-11-16): one GUI freeze occurred with individual files,
but it was not reproducible and did not recur across many other files. Left
unpursued until a repeatable trigger exists.

**Acceptance for both stability packages:** reproduction steps are documented,
the fix is verified through the GTK self-test or a repeatable manual test, and
verbose diagnostics make future allocation/sink failures understandable.

## P2 — Optional and delivery work

- [x] Implement optional same-directory sibling prefetch with cancellable
      bounded requests and the same cache leases as foreground
      preview/extraction. It stays disabled by default and is covered by the
      sibling-prefetch cancellation tests in `model.datasource`.
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
