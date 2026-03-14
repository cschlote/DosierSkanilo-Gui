# Architecture

This document describes the current architecture of `DosierSkanilo-Gui`.

## 1. High-Level Flow

1. User opens a JSON index file.
2. JSON is parsed and normalized into `BlobRow` projections.
3. Optional duplicate reduction and text filtering are applied.
4. Results are rendered in a `TreeView`/`ListStore` table.
5. Selection details are shown in a compact detail line.

## 2. Module Layout

- `source/app.d`: GTK shell and command wiring
- `source/model/blobrow.d`: presentation model (`BlobRow`)
- `source/io/dosierjson.d`: JSON extraction/normalization
- `source/view/textreport.d`: filtering and helper transformations

## 3. Startup CLI Layer

`source/app.d` includes a `std.getopt`-based startup parser that can preload the
GUI state for debugging and scripted launches.

Supported startup controls include:

- input JSON file
- startup auto-load
- duplicate-only mode
- initial filter text
- case sensitivity and auto-filter toggles

## 4. UI Composition

- classic menu bar
  - `File`: open, reload, quit
  - `Edit`: filter actions, preferences
  - `Help`: shortcuts, about
- toolbar with load/filter controls
- main `TreeView` table for rows
- status line and selection detail line

## 5. Design Principles

- keep parser compatibility logic outside GTK glue code
- keep UI actions mapped to reusable helper functions
- keep commit scopes small and behavior-focused
- avoid exposing private scan locations in commit metadata
