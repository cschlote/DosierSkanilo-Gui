# Changelog

All notable changes to this project are documented in this file.

## Unreleased

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
- Reorganized internal code into distinct model, IO, and view modules. No user-visible changes.
- Added a mode to view only records that appear more than once in the loaded dataset.
- Added the ability to open a scanner data file and browse all records in the main window.
- The project was started with a basic GTK window, debugger support, and version control configuration.

## 0.1.0

- Bootstrapped DUB project with GtkD integration
- Added initial runnable GUI window
- Added VS Code launch configuration for GUI target
