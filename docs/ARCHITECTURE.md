# Architecture

This document describes the current architecture of `DosierSkanilo-Gui`.

The GUI is a read-only browser for precomputed DosierSkanilo JSON output and
initialized `.dosierskanilo` SQLite repositories. It does not run the scanner,
compute metadata, or write repository data back to disk.

## 1. High-Level Flow

1. User opens a JSON index file, repository root, or restores previously open
   tabs.
2. The source adapter loads JSON through the legacy loader or reads the SQLite
  repository through the DosierSkanilo library API.
3. Loaded domain objects are normalized into `BlobRow` projections.
4. Text, media, file type, archive, and torrent filters are applied.
5. Results are rendered in a `TreeView`/`ListStore` table.
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
- `source/model/datasource.d`: JSON/repository source adapter
- `source/view/textreport.d`: filtering and helper transformations

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
filtering now use the page controls for repository documents. JSON documents
retain the full-load compatibility path.

## 4. UI Composition

- classic menu bar
  - `File`: open, reload, close tab, cancel operation, quit
  - `Edit`: filter actions, metrics reset, preferences
  - `Help`: shortcuts, about
- toolbar with load/filter controls
- main `TreeView` table for rows
- split-view detail pane with metadata expanders and known-file table
- status, performance, and file-metadata lines

## 5. Design Principles

- keep parser compatibility logic outside GTK glue code
- keep UI actions mapped to reusable helper functions
- keep commit scopes small and behavior-focused
- avoid exposing private scan locations in commit metadata
