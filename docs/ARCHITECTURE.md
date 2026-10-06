# Architecture

This document describes the current architecture of `DosierSkanilo-Gui`.

The planned replacement for the current flattened `NamedBinaryBlob` table is
documented in [GUI-REDESIGN.md](GUI-REDESIGN.md). `NamedBinaryBlob` remains the
JSON/Jsonizer representation; it is not intended to be the long-term GUI view
model.

The GUI is a read-only browser for precomputed DosierSkanilo JSON output and
initialized `.dosierskanilo` SQLite repositories. It does not run the scanner,
compute metadata, or write repository data back to disk.

The planned operation model is that CLI and GTK invoke the same backend scan,
metadata, and analysis operations. WP-09.1 has defined their shared request,
progress, and cooperative-cancellation contract, but backend executors and the
GUI operation task manager are not implemented; the GUI remains read-only.
Pause/resume is a planned WP-09.1b contract extension, not a current API feature.
Implementation phases are tracked in the backend plan:
`https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md`
(WP-09).

The target GUI workflow runs these operations on background workers, reports
phase/progress/results through the active document status UI, supports
cooperative cancellation and pause/resume at backend-acknowledged safe
checkpoints, and refreshes the affected source when a mutation completes. A
paused operation must not hold an active SQLite transaction; it retains the
per-target write lease until it resumes or is cancelled. Repository writes must
not share a connection with background tree readers; conflicting writes to the
same repository are serialized.

```text
CLI / GTK action -> typed operation request -> shared DosierSkanilo service
                                           -> progress / pause / resume / cancel / result events
```

SQLite repository and explicit JSON modes remain distinct targets. The GUI
operation chooser should select the same mode and operation semantics as the
CLI rather than implement a second scanner or metadata pipeline.

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

The GUI still opens JSON data files through the file chooser during normal use.
Repository roots are currently opened through positional startup arguments.
The adapter also exposes bounded page reads; visible page controls and SQL-backed
filtering now use the page controls and backend query filters for repository
documents. JSON documents retain the full-load compatibility path.
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
- split-view detail pane with metadata expanders and known-file table
- status, performance, and file-metadata lines

## 5. Filter Changes and Stable Tree Nodes

**Target architecture:** keep a per-document canonical directory model and its
already materialized GTK tree nodes across filter edits. The current JSON filter
path constructs a new filtered `DirectoryTree`, and `renderDirectoryTree()`
clears the `TreeStore` before attaching the filtered source; this discards loaded
nodes and their GTK identity on each applied filter.

Use a filtered view over the retained model, preferably `GtkTreeModelFilter` or
an equivalent GTK model wrapper. Compute matching file state and the visibility
of ancestor directories by stable node ID; a directory remains visible when it
contains a matching descendant. Refilter the view rather than clearing and
repopulating the underlying `TreeStore`. For lazy SQLite sources, reconcile
backend-filtered children by stable IDs, update existing nodes, and insert only
nodes not already materialized. Do not duplicate rows when changing sort/filter
state.

Define a tree-node key independently from a Blob identity or filtered-array
ordinal. A file-reference node needs a stable key for that particular path
(SQLite file-reference ID; a stable source/path key for JSON), because one Blob
may have multiple known paths. Keep the Blob ID separately for detail lookup.

Match calculation and index construction should run off the GTK thread; apply
visibility/model changes and restore selection/expansion on the GTK main loop.
The filter callback should be a bounded lookup over precomputed visibility state,
not a blocking source query or recursive full-tree scan. Keep the old tree usable
while a new filter is computed, then publish the new visibility state atomically.
Clearing a filter should restore visibility on the retained nodes without
rebuilding the tree.

Validate text, media, presence, negation, sorting, and parent/descendant behavior
against existing filter semantics. Add GTK model coverage that checks stable
node IDs and retained underlying nodes across apply/change/clear, plus large-tree
measurements for latency, allocation churn, and peak memory.

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
