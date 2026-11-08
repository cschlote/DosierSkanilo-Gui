# Architecture

This document describes the current architecture of `DosierSkanilo-Gui`.

The tree-first view replaced the flattened `NamedBinaryBlob` table as the
primary navigation surface; the blob table remains an alternative view. Design
history and remaining UI work are documented in
[GUI-REDESIGN.md](GUI-REDESIGN.md). `NamedBinaryBlob` remains the backend's JSON
representation, not the GUI view model.

The GUI browses DosierSkanilo JSON catalogs and initialized `.dosierskanilo`
SQLite repositories. Its Tools actions invoke the shared backend scan, metadata,
and analysis operations; scanner and repository mutation logic remains outside
GTK.

WP-09.1 and WP-09.1b define the shared request, progress, cancellation, and
pause/resume contract. Controlled backend executors, target leases, CLI adapters,
and GUI Tools actions are implemented. Cross-process and display-backed
verification evidence is recorded in the backend
[OPERATION-PARITY.md](https://github.com/cschlote/DosierSkanilo/blob/main/docs/OPERATION-PARITY.md).

The Tools workflow runs backend operations on background workers, reports
phase/progress/results through the owning document tab, supports cooperative
cancellation and pause/resume at backend-acknowledged safe checkpoints, and
refreshes the affected source when a mutation commits. A paused operation holds
no active SQLite transaction; it retains the per-target write lease until it
resumes or is cancelled. Repository writes do not share a connection with
background tree readers; conflicting writes to the same target are serialized.

```text
CLI / GTK action -> typed operation request -> shared DosierSkanilo service
                                           -> progress / pause / resume / cancel / result events
```

SQLite repository and explicit JSON modes remain distinct targets. The GUI
operation dialogs build the same typed requests as the CLI; they do not implement
a second scanner or metadata pipeline. Standalone metadata is repository-only;
JSON supports scan/analyze with optional metadata phases.

## 1. High-Level Flow

1. User opens a JSON index file, repository root, or restores previously open
   tabs.
2. The source adapter opens both JSON catalogs and SQLite repositories through
   the shared `CatalogBackend`; JSON sessions bind a derived filesystem root.
   SQLite references are root-relative, so a copied, moved, or remounted
   repository opens at its current path and refreshes the advisory root metadata.
3. Backend directory queries are exposed through `CatalogDirectorySource`.
4. Directory children are loaded lazily with bounded backend pages on background
   workers.
5. The directory tree is rendered as the primary navigation view. The flattened
   `BlobRow` table remains an alternative blob-oriented view.
6. Selection details are shown in a split view with metadata expanders,
  clipboard actions, and a raw JSON detail block.

## 2. Module Layout

- `source/app.d`: entry point
- `source/cli/commandline.d`: startup parser
- `source/ui/mainwindow.d`: GTK shell, loading, filtering, rendering, and menu actions
- `source/ui/documenttab.d`: per-tab state and table column constants
- `source/ui/documentpage.d`: notebook/document page widgets
- `source/ui/detailpreview.d`: preview surface and progress state
- `source/ui/detailswidgets.d`: detail and preview widget helpers
- `source/ui/virtualblobtable.d`: bounded cursor-backed repository Blob model
- `source/ui/operationdialogs.d`: source-aware operation option dialogs
- `source/ui/operationrequests.d`: pure request mapping from GUI options/targets
- `source/ui/operationtaskstate.d`: GTK-independent progress/lifecycle reduction
- `source/ui/tablecolumns.d`: table column setup
- `source/ui/appstate.d`: persisted preferences and window state
- `source/model/blobrow.d`: presentation model (`BlobRow`)
- `source/model/catalogsource.d`: catalog-backed directory source
- `source/model/treeprojection.d`: directory/file projection and `DirectorySource`
- `source/model/datasource.d`: JSON/repository source adapter
- `source/view/textreport.d`: filtering and helper transformations

Catalog DTOs, directory/file queries, archive pages, and SQLite access live in
the sibling `DosierSkanilo` library behind `CatalogBackend`. The GUI does not
access SQLite directly.

## 3. Startup CLI Layer

`source/cli/commandline.d` includes a `std.getopt`-based startup parser that can
prefill filter and preference state for debugging and scripted launches.

Supported startup controls include:

- initial filter text
- case sensitivity
- auto-filter toggle

The GUI opens JSON files and repository directories through the File menu, and
also accepts them as positional startup arguments. Tools operation requests use
explicit targets and are constructed by `operationrequests.d`; the task worker
calls the public `dosierskanilo.operationrunner` API. Both storage modes use
bounded `CatalogBackend` DTOs/pages. The legacy full-load JSON parser remains
only for filtered export, archive-scan helpers, and tests.
Nested repository details are fetched asynchronously when a row is selected.
Directory expansion and additional file pages use the same background-query
pattern. Known file references can be navigated independently of the blob row.

## 4. UI Composition

- classic menu bar
  - `File`: open, save/revert JSON documents, reload, export, close tab,
    archive passwords, scan archives, recent files, cancel operation, quit
  - `Tools`: start supported operations, pause/resume at safe checkpoints, and
    cancel
  - `Edit`: filter actions, metrics reset, preferences
  - `Help`: shortcuts, about
- toolbar with load/filter controls
- primary lazy directory `TreeView`; `Left` selects the parent row and `Right`
  expands a directory/archive row and selects its first materialized child
- alternative blob table: sortable ListStore rows for JSON and full-list views,
  plus a non-sortable virtual cursor-backed model for paged repositories
- split-view details column and Previewer, separated by a horizontal splitter
- vertically scrollable detail expanders for metadata and known-file information
- large scrollable text content in the Previewer, with filesystem attributes in
  its lower summary area
- archive/torrent entry trees in the large scrollable Previewer area; their
  detail expanders contain summary fields rather than duplicate lists
- status, performance, and file-metadata lines

## 5. Filter Changes and Stable Tree Nodes

Filter changes now retain each document's canonical `TreeStore` and materialized
nodes behind a `GtkTreeModelFilter`. The JSON worker computes stable file and
ancestor visibility IDs plus filtered directory summaries; it no longer creates
a second `DirectoryTree` per filter. SQLite filter loads query the materialized
directory IDs in the worker and reconcile returned rows into the existing store.
The view is refiltered after row visibility is updated on GTK's main loop.

Catalog-backed JSON and repository rows use source-relative paths for tree,
table, cursor, and detail identity. The legacy JSON ordinal scheme remains only
in the `ProjectedDirectorySource` fallback and tests. A directory remains visible
when it has a matching descendant; placeholders and page markers follow the same
visibility index. Filter changes preserve existing
node identity, sorting, selection, and expansion, while new rows are upserted by
stable ID. Clearing a filter restores existing rows and asynchronously fills
already-materialized directories from the unfiltered source.

Matching and index construction run off the GTK thread. GTK model writes and
`GtkTreeModelFilter.refilter()` run on the main loop; filter visibility reads a
precomputed ID lookup and never calls a backend query. Tests cover filter
predicates, stable IDs, ancestor visibility, and canonical-row retention.
Headless filter/tree latency, allocation, and peak-memory measurements are
recorded with the benchmark scripts; per-batch 95,001-row display profiling
remains a follow-up in `TODO.md`.

## 6. GC-Friendly GUI Algorithms

GUI algorithms must be GC-friendly, especially filtering, projection, sorting,
and rendering. Reuse the loaded source and stable node records instead of
allocating another complete `BlobRow[]`, `DirectoryTree`, and GTK model on each
filter change. Build compact match/visibility indexes and reuse bounded
per-document or per-worker scratch buffers; reserve capacity when counts are
known and avoid repeated path normalization/string formatting in per-node loops.
Keep caches bounded, mutable scratch worker-local, and large temporary results
short-lived. Measure repeated filter cycles, GC behavior where tooling permits,
and peak memory on representative JSON and SQLite sources.

The shared archive extraction cache is used by member scraping, checksums, file
type, MediaInfo, and preview; optional same-directory sibling prefetch remains
planned and is not implemented. Cache leases pin entries while a preview or
extractor uses them; eviction must not interrupt an active user. The cache uses
one application-wide, user-configurable base directory and size limit for both
JSON and SQLite sources, plus an application-owned per-session subdirectory that
is removed after workers and previews stop at shutdown. It is never represented
as a persistent catalog file reference. A RAM-backed filesystem may be selected
as the cache base.

## 7. Design Principles

- keep parser compatibility logic outside GTK glue code
- keep UI actions mapped to reusable helper functions
- keep commit scopes small and behavior-focused
- avoid exposing private scan locations in commit metadata
