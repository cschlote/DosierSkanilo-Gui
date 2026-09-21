# Architecture

This document describes the current architecture of `DosierSkanilo-Gui`.

The planned replacement for the current flattened `NamedBinaryBlob` table is
documented in [GUI-REDESIGN.md](GUI-REDESIGN.md). `NamedBinaryBlob` remains the
JSON/Jsonizer representation; it is not intended to be the long-term GUI view
model.

The GUI is a read-only browser for precomputed DosierSkanilo JSON output and
initialized `.dosierskanilo` SQLite repositories. It does not run the scanner,
compute metadata, or write repository data back to disk.

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
  - `Edit`: filter actions, metrics reset, preferences
  - `Help`: shortcuts, about
- toolbar with load/filter controls
- primary lazy directory `TreeView`
- alternative `TreeView`/`ListStore` blob table
- split-view detail pane with metadata expanders and known-file table
- status, performance, and file-metadata lines

## 5. Design Principles

- keep parser compatibility logic outside GTK glue code
- keep UI actions mapped to reusable helper functions
- keep commit scopes small and behavior-focused
- avoid exposing private scan locations in commit metadata
