# Changelog

All notable changes to this project are documented in this file.

## Unreleased

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
