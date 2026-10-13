# Architecture

This document describes the current architecture of `DosierSkanilo-Gui`.

The planned replacement for the current flattened `NamedBinaryBlob` table is
documented in [GUI-REDESIGN.md](GUI-REDESIGN.md). `NamedBinaryBlob` remains the
JSON/Jsonizer representation; it is not intended to be the long-term GUI view
model.

The GUI browses DosierSkanilo JSON catalogs and initialized `.dosierskanilo`
SQLite repositories. Its Tools actions invoke the shared backend scan, metadata,
and analysis operations; scanner and repository mutation logic remains outside
GTK.

WP-09.1 and WP-09.1b define the shared request, progress, cancellation, and
pause/resume contract. Controlled backend executors, target leases, CLI adapters,
and initial GUI Tools actions are implemented. Remaining parity and process-level
verification is tracked in the backend plan:
`https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md`
(WP-09).

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
2. The source adapter loads JSON through the legacy loader or reads the SQLite
  repository through the DosierSkanilo library API.
3. The source is projected into a GTK-independent `DirectorySource`.
4. Directory children are loaded lazily; repository children use bounded SQLite
   queries on background workers.
5. The directory tree is rendered as the primary navigation view. The flattened
   `BlobRow` table remains an alternative blob-oriented view.
6. Selection details are shown in a split view with metadata expanders,
  clipboard actions, and a raw JSON detail block.

## 2. Module Layout

- `source/app.d`: entry point
- `source/cli/commandline.d`: startup parser
- `source/ui/mainwindow.d`: GTK shell, loading, filtering, rendering, and menu actions
- `source/ui/documenttab.d`: per-tab state and table column constants
- `source/ui/operationdialogs.d`: source-aware operation option dialogs
- `source/ui/operationrequests.d`: pure request mapping from GUI options/targets
- `source/ui/operationtaskstate.d`: GTK-independent progress/lifecycle reduction
- `source/ui/detailswidgets.d`: detail widget helpers
- `source/ui/tablecolumns.d`: table column setup
- `source/ui/appstate.d`: persisted preferences and window state
- `source/model/blobrow.d`: presentation model (`BlobRow`)
- `source/model/treeprojection.d`: directory/file projection and `DirectorySource`
- `source/model/datasource.d`: JSON/repository source adapter
- `source/view/textreport.d`: filtering and helper transformations

Repository DTOs and bounded directory SQL queries live in the sibling
`DosierSkanilo` library. The GUI does not access SQLite directly.

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
calls the public `dosierskanilo.operationrunner` API. Repository queries use
bounded backend DTOs/pages; JSON retains a full-load compatibility source with
shared catalog read leases around file parsing.
Nested repository details are fetched asynchronously when a row is selected.
Directory expansion and additional file pages use the same background-query
pattern. Known file references can be navigated independently of the blob row.

## 4. UI Composition

- classic menu bar
  - `File`: open, reload, close tab, cancel operation, quit
  - planned `Tools` actions: start supported operations, pause/resume at safe
    checkpoints, and cancel
  - `Edit`: filter actions, metrics reset, preferences
  - `Help`: shortcuts, about
- toolbar with load/filter controls
- primary lazy directory `TreeView`
- alternative `TreeView`/`ListStore` blob table
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

File-reference identity is separate from Blob identity and filtered-array order:
JSON keys combine source-row and reference ordinals, while SQLite keys use the
file-reference cursor ID. The Blob ID remains separate for detail lookups. A
directory remains visible when it has a matching descendant; placeholders and
page markers follow the same visibility index. Filter changes preserve existing
node identity, sorting, selection, and expansion, while new rows are upserted by
stable ID. Clearing a filter restores existing rows and asynchronously fills
already-materialized directories from the unfiltered source.

Matching and index construction run off the GTK thread. GTK model writes and
`GtkTreeModelFilter.refilter()` run on the main loop; filter visibility reads a
precomputed ID lookup and never calls a backend query. Tests cover filter
predicates, stable IDs, ancestor visibility, and canonical-row retention. Large
tree latency, allocation churn, and peak-memory measurements remain a follow-up.

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

## 7. Design Principles

- keep parser compatibility logic outside GTK glue code
- keep UI actions mapped to reusable helper functions
- keep commit scopes small and behavior-focused
- avoid exposing private scan locations in commit metadata
