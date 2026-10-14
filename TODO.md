# GUI Work Plan

This file tracks active GUI work and GUI-owned follow-ups. The shared scan,
metadata, and analysis operation plan is maintained in
[`DosierSkanilo/docs/SQLITE-IMPLEMENTATION-PLAN.md`](https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md).
Completed implementation history is in `CHANGELOG.md`; completed integration
and verification coverage is summarized in `docs/GUI-REDESIGN.md`.

## P0 — Finish asynchronous JSON filtering

Status: **complete and verified**.

The current changes move construction of filtered JSON tree projections away
from the GTK main thread and add indexes for directory-child and per-directory
file lookup. Finish this as one bounded change before starting another GUI
refactor.

- [x] Review the filter lifecycle for apply, clear, changing tabs, loading a new
  source, and cancelling while filtering. A late result must not replace a newer
  filter or source; cancellation must restore a usable tree and table.
- [x] Verify the unfiltered JSON tree/source remains available after applying a
  filter and is restored by Clear. A filtered projection must not accidentally
  become the next filter's source.
- [x] Persist whether each document's filter is applied; reapply an active saved
  filter after JSON source binding even if global auto-filter is disabled, then
  restore expanded directories against that filtered tree. New documents start
  empty rather than inheriting the previous tab's filter.
- [x] Persist Blob-table sort column/direction per document and use the existing
  Directory tree / Blob table notebook tabs instead of a redundant view dropdown.
- [x] Verify text case sensitivity, media negation, file-type/archive/torrent
  presence filters, sorting, and directory visibility match the JSON
  `DirectorySource` semantics. Blob/catalog case-sensitive parity is verified
  separately under backend WP-10.1.
- [x] Exercise large directory/file projections and confirm indexed lookups do
  not change results or require repeated full-tree scans during rendering.
- [x] Run GUI unit tests/build, `git diff --check`, GTK-independent
  lifecycle/filter projection tests, and the opt-in GTK tree-loading test. There
  is no dedicated display-driven filter lifecycle test yet.

**Acceptance:** filtering does not freeze GTK while computing the JSON
projection; Clear/cancel and rapid successive requests leave the active document
in a consistent state; JSON filter results retain the established filter and
sort semantics; the normal verification commands pass.

## P1 — Restore Blob-table filter parity (WP-10.1)

Status: **complete and verified**.

The review found a real gap between case-sensitive tree filtering and the
repository Blob/catalog query. The backend option and GUI adapter propagation are
implemented and verified under WP-10.1:

- [x] Add the active case-sensitivity preference to `SourceQuery` and propagate
  it through GUI catalog offset/cursor requests to `RepositoryQueryOptions`.
- [x] Verify the Blob table and directory tree return the same path matches for
  mixed-case names in JSON and SQLite documents.
- [x] Verify exact SHA1 matches remain independent of path case and cursor
  navigation remains stable after the path filter is applied.

**Acceptance:** one preference produces matching results in the JSON/SQLite
tree and Blob-table views; regression coverage exists at backend and GUI adapter
boundaries. Backend API/SQL scope and dependency are defined in WP-10.1.

## P1 — Complete shared CLI/GTK operations

The initial WP-09.4 GUI task manager is implemented: Tools actions construct the
shared requests, run them on workers, marshal progress to GTK, expose safe
pause/resume/cancel controls, and reload the affected tab after success. Backend
WP-09.5 remains the source of truth for cross-frontend parity; its current matrix
and remaining process/display checks are in the backend's `docs/OPERATION-PARITY.md`.

- [x] Add target-aware Tools actions for repository/JSON scan and analysis and
  repository metadata extraction.
- [x] Run requests on background workers, display backend progress, and marshal
  all widget updates to the GTK main loop.
- [x] Connect Cancel/Pause/Resume to backend operation control and retain the
  operation's target lease until completion.
- [x] Refresh the affected document after successful mutations and prevent tab
  closure while its operation is draining.
- [ ] Add GTK-independent task-manager lifecycle tests and opt-in display-backed
  tests for Tools wiring, progress, pause/resume, cancellation, and refresh.
- [ ] Complete WP-09.5 CLI/GUI result, progress, cancellation, error, refresh, and
  explicit storage-mode parity coverage.

## P1 — Reuse directory TreeView nodes across filter changes

Status: **implemented for JSON and SQLite filter changes**. The former path
created a new JSON projection and cleared the GTK `TreeStore`; the current path
retains its per-document store behind `GtkTreeModelFilter`. See
[`docs/GUI-REDESIGN.md`](docs/GUI-REDESIGN.md).

- [x] Define stable tree-node IDs that survive filtering/sorting and distinguish
  file-reference paths from their Blob IDs; preserve materialized rows when a
  filter changes or is cleared.
- [x] Compute match state and visible ancestors off the GTK thread, then update
  the filtered model on the GTK main loop. Visibility callbacks must not perform
  source queries or recursive descendant scans.
- [x] Reconcile lazy SQLite results by stable ID, reusing existing rows and only
  inserting newly materialized nodes; keep paging/query caches bounded.
- [x] For JSON, reuse the one loaded/indexed source and a compact match index;
  do not rebuild a complete `DirectoryTree` and GTK model on every filter.
- [x] Preserve selection, expansion, sort, placeholder/loading states, and exact
  text/media/presence/negation semantics through apply/change/clear cycles.
- [x] Add GTK model tests for underlying node retention and result parity.
- [ ] Measure repeated filter latency and peak memory on representative JSON and
  SQLite catalogs; profile Blob-table rendering at 95,001 JSON rows, including
  GC allocation behavior and batch time.

**Acceptance:** filter changes update the visible projection without clearing or
recreating existing source nodes; matching descendants keep their ancestor paths
visible; repeated filtering is GC-friendly and preserves existing behavior. Unit
tests and the display-backed startup/filter smoke test pass.

## P1 — Archive member TreeView and shared extraction cache (WP-13.5)

Status: **planned; backend JSON v5 and SQLite schema-v4 work is tracked in the
DosierSkanilo WP-13.5 plan.** The archive file remains the expandable file row;
the GUI must not create a second sibling folder or persist cache paths.

- [ ] Give `hasArchive` file rows an async TreeView expander. Expanding lists safe
  entries lazily; selecting a member extracts it for preview. Nested archives
  use the same flow, and visible names hide the duplicate-occurrence path suffix.
- [ ] Carry the structured container/entry locator through JSON and SQLite
  directory/file sources. Use the virtual path only as a reversible reference
  spelling (`!/`, `!!`, `!~N`), not as an OS path or the primary identity.
- [ ] Add one shared extraction-cache service for preview, checksums, File Type,
  MediaInfo, archive scans, and optional prefetch. Coalesce in-flight requests,
  pin active previews, bound size/workers, and never persist cache paths as
  `FileSpec` references.
- [ ] Add cache preferences: JSON defaults below OS temp; SQLite uses a
  configurable local cache base and a per-session subdirectory. Remove the
  session cache on normal exit and sweep only application-owned stale sessions
  at startup. Stop media previews and join/cancel workers before cleanup. A RAM
  disk can be selected as the cache base.
- [ ] Keep same-directory sibling prefetch disabled by default. When enabled,
  make it cancellable, bounded, and use the same cache leases as foreground
  preview/extraction.
- [ ] During explicit deep scans, process every safely selectable non-directory
  member using one cache lease for checksums and the selected metadata extractors;
  persist metadata against the member content blob, not the temporary path.
- [ ] Test nested archives, `!` escaping, duplicate occurrence IDs, unsafe paths,
  encrypted containers, extraction cancellation, prefetch cancellation, cache
  eviction/pinning, and shutdown/stale-session cleanup for both storage modes.

**Acceptance:** selecting an archive member displays it in the normal Previewer;
scraped metadata survives cache eviction, no cache paths enter JSON/SQLite source
references, and shutdown removes the current session's extracted files.

## P2 — Stabilize GTK layout and video preview

The following are separate user-visible issues. Reproduce and log each before
changing allocation or persistence code, so fixes can be evaluated independently.

### Splitter persistence and sizing

- [ ] Reproduce the top-level splitter returning to an extreme position after a
  fresh load, reload, tab switch, and application restart.
- [ ] Reproduce preview/details splitter restoration after those same lifecycle
  transitions, including startup before the first real GTK allocation.
- [ ] Define which saved position wins (new window default versus per-window
  restored value), clamp only after a usable allocation, and avoid saving
  transient/unallocated positions.
- [ ] Verify the list and details panes remain usable at the minimum supported
  window size; verify the chosen positions survive restart.

### Video preview realization and window growth

- [ ] Reproduce first-selection video playback where audio starts but the video
  frame stays blank; capture widget realization, sink attachment, and allocation
  order in verbose logs.
- [ ] Reproduce horizontal window growth when switching between video rows and
  determine whether the sink, aspect frame, or preferred video size requests the
  extra width.
- [ ] Ensure a failed or delayed video sink falls back without blocking other
  preview controls or changing the parent window's requested width.
- [ ] Verify first and subsequent video selections on the supported GTK display
  backends, and retain audio/image preview behavior.

**Acceptance for both layout tasks:** the reproduction steps are documented, the
fix is verified through the GTK self-test or a repeatable manual test, and
verbose diagnostics make future allocation/sink failures understandable.

## P3 — UI maintenance and portability

These are lower-priority cleanup packages; start them only when they have a
specific visual or compatibility outcome to verify.

- [ ] Replace `overrideFont` monospace styling with reusable CSS classes and a
  shared `CssProvider`; verify all detail/report text remains legible.
- [ ] Remove obsolete `double-buffered` Builder properties and confirm preview
  rendering remains correct on the supported GTK baseline.
- [ ] Evaluate `gtksink` preference with an `ximagesink` fallback for embedded
  video, including Wayland and X11 behavior; keep sink selection isolated behind
  the existing fallback path.
- [ ] Move repeated static widget styling/defaults into Builder files only where
  this removes runtime duplication without moving behavior or signal logic out of
  D.

## P4 — Deferred product and delivery work

- [x] Add archive password prompting and filename-based persistence for JSON
  catalogs and repositories, including the archive scan retry flow (Release
  0.8.0).
- [ ] Define and implement a release packaging/tagging workflow for supported
  distributions, including version source, build artifacts, and installation
  smoke checks.
- [ ] Investigate the previously noted CLI stdout/stderr ordering concern around
  `argsArray`; only add synchronization if a reproducible interleaving is found.
