# GUI Work Plan

This file tracks active GUI work and GUI-owned follow-ups. The shared scan,
metadata, and analysis operation plan is maintained in
[`DosierSkanilo/docs/SQLITE-IMPLEMENTATION-PLAN.md`](https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md).
Completed implementation history is in `CHANGELOG.md`; completed integration
and verification coverage is summarized in `docs/GUI-REDESIGN.md`.

## P0 — Finish asynchronous JSON filtering

Status: **in progress in the current working tree; not yet verified**.

The current changes move construction of filtered JSON tree projections away
from the GTK main thread and add indexes for directory-child and per-directory
file lookup. Finish this as one bounded change before starting another GUI
refactor.

- [ ] Review the filter lifecycle for apply, clear, changing tabs, loading a new
  source, and cancelling while filtering. A late result must not replace a newer
  filter or source; cancellation must restore a usable tree and table.
- [ ] Verify the unfiltered JSON tree/source remains available after applying a
  filter and is restored by Clear. A filtered projection must not accidentally
  become the next filter's source.
- [ ] Verify text case sensitivity, media negation, file-type/archive/torrent
  presence filters, sorting, and directory visibility match the JSON
  `DirectorySource` semantics. Blob/catalog case-sensitive parity is tracked
  separately as backend WP-10.1.
- [ ] Exercise large directory/file projections and confirm indexed lookups do
  not change results or require repeated full-tree scans during rendering.
- [ ] Run GUI unit tests and build, `git diff --check`, and relevant opt-in GTK
  tree/filter tests when a display is available.

**Acceptance:** filtering does not freeze GTK while computing the JSON
projection; Clear/cancel and rapid successive requests leave the active document
in a consistent state; JSON filter results retain the established filter and
sort semantics; the normal verification commands pass.

## P1 — Restore Blob-table filter parity (WP-10.1)

The review found a real gap between case-sensitive tree filtering and the
repository Blob/catalog query. Implement the backend query option under WP-10.1,
then finish the GUI adapter side:

- [ ] Add the active case-sensitivity preference to `SourceQuery` and propagate
  it through GUI catalog offset/cursor requests to `RepositoryQueryOptions`.
- [ ] Verify the Blob table and directory tree return the same path matches for
  mixed-case names in JSON and SQLite documents.
- [ ] Verify SHA1 lookups remain case-insensitive and cursor navigation remains
  stable after the case-sensitive filter is applied.

**Acceptance:** one preference produces matching results in the JSON/SQLite
tree and Blob-table views; regression coverage exists at backend and GUI adapter
boundaries. Backend API/SQL scope and dependency are defined in WP-10.1.

## P1 — Complete shared CLI/GTK operations

Use backend work packages WP-09.1 through WP-09.5 as the source of truth. The
GUI-specific deliverable is WP-09.4: explicit Tools actions for supported scan,
metadata, and analysis operations, an options/target flow that preserves the
explicit JSON-versus-repository distinction, background execution, main-loop
progress updates, cooperative cancellation, per-target write serialization, and
view refresh after successful mutations. Do not implement scanner or analysis
logic in GTK.

Before GTK operation implementation begins, WP-09.1 and the relevant WP-09.2
backend slices must provide the shared request/control API and real cancellation.
Implement and verify each CLI operation adapter (WP-09.3) as its backend slice
lands; then use the CLI behavior as the reference for GTK WP-09.4. WP-09.5
verifies parity across both frontends.

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

- [ ] Decide whether archive password prompting/remembering is in scope. If
  accepted, implement prompt/retry/forget flows and opt-in persistence keyed by
  source plus archive identity; never persist a failed attempt or a password the
  user did not ask to remember. The proposed behavior is documented in
  `docs/GUI-REDESIGN.md`.
- [ ] Define and implement a release packaging/tagging workflow for supported
  distributions, including version source, build artifacts, and installation
  smoke checks.
- [ ] Investigate the previously noted CLI stdout/stderr ordering concern around
  `argsArray`; only add synchronization if a reproducible interleaving is found.
