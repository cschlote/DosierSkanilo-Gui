# Changelog

All notable changes to this project are documented in this file.

## Unreleased

- Added a scroll container around the Archive metadata expander so its long text no longer forces the details pane to grow vertically.
- Aligned the detail panel content to the top so the visible fields stay anchored when the archive section is expanded.
- Made the horizontal splitter refit to the natural width only on fresh loads; reloads now restore the saved split position and filter updates only clamp to the valid range.
- Kept the main table columns non-resizable after load so mouse-driven autosizing cannot invalidate the splitter width limits.
- Ensured the main table columns are measured once before the mouse-resize lock is applied, so the Size column keeps its full width.
- Reattached the TreeView model before column measurement so the splitter bounds are computed from the live data model instead of a detached table.
- Deferred the column measurement until after GTK has rendered the reattached TreeView model, so the measured widths reflect the actual row content.
- Only trigger that post-layout measurement for full loads, so filtered renders do not overwrite the splitter bounds.
- Explicitly queued a new layout pass after reattaching the TreeView model so the measurement runs on rendered rows instead of the empty intermediate state.
- Set the post-load measurement flag before the TreeView is reattached, so the size-allocate hook cannot miss the first layout pass.
- Added a temporary Relayout button and verbose layout/load logging to help debug the splitter measurement path.
- Added a fixed-width fallback for the Archive and Torrent columns so their widths still count even if GTK reports zero allocated width during measurement.
- Avoided passing a null string into the filter entry at startup and logged the initial filter text length for debugging.
- Reorganized internal code into distinct model, IO, and view modules. No user-visible changes.
- Added a mode to view only records that appear more than once in the loaded dataset.
- Added the ability to open a scanner data file and browse all records in the main window.
- The project was started with a basic GTK window, debugger support, and version control configuration.

## Release 0.5.0 - 2026-04-11

- Removed the last cached blob detail string from `BlobRow`; the detail view now derives the raw text directly from the original `NamedBinaryBlob`.
- Removed the cached known-file name strings from `BlobRow` and now render file names and last-modified timestamps directly from the original `FileSpec` data.
- Corrected the Known file names table so the last modified timestamp now appears in its own column instead of being appended to the filename.
- Tightened the horizontal splitter minimum so it now follows the measured width of the first two table columns instead of a generic fallback.
- Added positional JSON arguments on GUI startup so command-line files open alongside any restored tabs, with duplicate paths ignored.
- Added a `-v/--verbose` startup flag for the GUI logging helpers.
- Aligned the GUI documentation and task list with the overhauled DosierSkanilo backend, clarifying that the desktop app is a read-only browser for precomputed JSON and does not yet expose the scanner-side workflow.

- Refactored GUI code by moving tab state, table column setup, and detail-widget helpers from `source/app.d` into dedicated UI modules under `source/ui/`.
- Extracted all persisted application state types and JSON load/save helpers into a dedicated module `source/ui/appstate.d`.
- Added dedicated CLI modules for startup argument parsing and stdout logging, including verbose debug output support.
- Replaced the GUI's custom scanner JSON parsing path with the DosierSkanilo library loader and `NamedBinaryBlob` projection helpers.
- Added shared text-report and row-filter helpers so GUI and non-GUI output paths can reuse the same projection logic.
- Simplified the table to focused columns (`Index#`, `Size`, `Checksums`, `File Type`, `MediaInfo`, `Archive`, `Torrent`) and reduced `File Type` display to a compact yes/no indicator.
- Persisted window geometry, splitter positions, and key preferences under `~/.config/dosierskanilo-gui/state.json`, including an option in Preferences to clear saved window positions.
- Extended category filtering with two additional toolbar checkboxes for archive and torrent rows (`AR`/`TO`), including `NOT` inversion and hit counters.
- Improved media type filtering (`V/A/I/T`) with robust media key detection and status hit counters, and removed the obsolete duplicates-only load mode from the GUI.

## Release 0.3.0 - 2026-03-15

- Entfernt: Das String-Widget für den Dateinamen und der "Load JSON"-Button wurden aus der Toolbar und dem Code entfernt.
- Die Toolbar ist jetzt kompakter und enthält nur noch relevante Filter- und Steuer-Elemente.
- Alle Referenzen auf die entfernten UI-Elemente wurden bereinigt, der Build ist wieder fehlerfrei.
- Interne Aufräumarbeiten und Refactoring im Zusammenhang mit der Entfernung der alten Lade-Logik.

## Release 0.2.1

- Added GitLab release automation that publishes versioned assets to the GitLab Package Registry and creates GitLab Releases with persistent package links.

## Release 0.2.0

- Added a first executable unit test suite and changed the test script to run real `dub test` checks instead of only recompiling the application.
- Added line coverage reporting for the test stage, including a total percentage for project source files and stored coverage listing artifacts.
- Kept `.lst` coverage files canonical under `build/coverage/lst` and added top-level symlinks for VS Code DCode coverage highlighting.
- Added archive type, torrent indicator, MD5, and xxHash64 checksum columns to the main record table.
- Added a status line showing the format version and data structure of the currently loaded file.
- Extended the record detail view with additional checksums (MD5, xxHash64), the full list of referenced filenames, and archive/torrent availability indicators.
- Added clipboard copy buttons in the detail panel for copying the checksum, filename, or complete record details with one click.
- Removed redundant title and description labels from the window header to reduce visual clutter.
- Added a performance counter at the bottom of the window showing how long the last load, filter, and render operations took, with an Edit menu option to reset it.
- Added a progress bar and status messages that show what stage the application is at during background loading and filtering.
- Added Ctrl+K and a File menu entry to stop any running background operation immediately.
- Made the record filter run in the background so the application stays responsive while searching large datasets.
- Added background file loading with batched table rendering and a Cancel button, so the application stays responsive when opening large files.
- Added a side panel showing the full details of the currently selected record alongside the main table.
- Improved API documentation across all source modules, added startup usage examples to the README, and removed local paths from debugger configuration.
- Added command-line options for opening a file, pre-setting a filter, or auto-loading records when the application starts.
- Added VS Code build and test tasks, and an automated API documentation build using ADRDox.
- Added project documentation (README, architecture notes, TODO list) and a continuous integration pipeline with automated build and test checks.
- Added a detail section below the table showing key fields for the currently selected record.
- Switched the main record list to a sortable, resizable table with clickable column headers.
- Added a menu bar with File, Edit, Preferences, and Help entries, keyboard accelerators, and an About dialog.
- Added a Reload button and keyboard shortcuts for faster access to common actions.
- Added a text search box to filter records by filename or checksum value.

## Release 0.1.0

- Bootstrapped DUB project with GtkD integration
- Added initial runnable GUI window
- Added VS Code launch configuration for GUI target
