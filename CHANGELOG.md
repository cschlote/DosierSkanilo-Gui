# Changelog

All notable changes to this project are documented in this file.

## Release 0.7.0 - 2026-09-17

- Ignore missing paths in the recent-files list instead of terminating the GUI,
  and normalize empty filter text before passing it to GTK.
- Added the GTK-independent directory projection and source adapter entry point
  used by the planned tree model.
- Added a transitional directory TreeView above the existing result table;
  selecting a file in it selects the corresponding table row and detail view.
- Directory trees are now built from the complete loaded source rather than the
  current filtered or paged table rows.
- Directory children are now materialized in the GTK TreeStore when their
  parent is expanded, with visible loading placeholder nodes.
- The TreeView now consumes a read-only `DirectorySource` interface, isolating
  GTK from the current in-memory adapter and preparing a repository-backed
  directory query implementation.
- Tree selections now resolve repository rows by stable blob ID instead of
  display filename.
- Directory sources now expose bounded file-page queries; tree expansion no
  longer requests an unbounded file list.
- Repository directory expansions now query children on a background worker and
  show an error row when the asynchronous query fails.
- The `More files available...` row now loads subsequent file pages on
  activation for both repository and JSON sources.
- Selecting a repository file that is outside the current table page now loads
  its details by stable blob ID and selects it in the detail view.
- Each document tab now tracks expanded directory IDs independently of the
  legacy result table.
- Tree rebuilds now restore the directories tracked as expanded, including
  repository trees that load child levels asynchronously.
- Asynchronous tree updates now resolve GTK iterators from stable TreePaths on
  the main thread, avoiding invalid-iterator warnings during expansion.
- GTK TreePath lookups now initialize their iterator objects correctly before
  reading or updating asynchronous tree rows.
- Table selection now selects the matching TreeView file when it is currently
  materialized, while selecting a known file name updates the active file
  action target for blobs with multiple references.
- The detail pane now provides Previous/Next controls for switching between
  multiple known file names of one binary blob.
- Selecting a blob-table row now searches and expands its directory path before
  selecting the matching TreeView file, including repository paths loaded in a
  background worker.
- Expanded Directory IDs are now persisted per document path in `AppState` and
  restored when tabs are recreated.
- The selected TreeView file is now persisted per document path and revealed
  after the source is loaded again.
- The active text filter is now applied to TreeView file children for both JSON
  and repository sources.
- Directory and file nodes now support per-tab sorting by name or size through
  the TreeView sort selector.
- The per-document TreeView sort order is now persisted in `AppState`.
- Tree selections outside the current blob-table page now render directly in
  the detail pane without appending a temporary table row.
- Added a per-tab view switch for `Tree + table`, `Tree only`, and `Blob table
  only`.
- The selected view mode is now persisted per document path in `AppState`.
- Repository tabs now use the discovered repository root name, even when the
  user opened a nested directory below that root.
- GUI `DirectorySource` now exposes source-opaque `FilePage`/`FileCursor`
  projections for internal chunk navigation across JSON and SQLite adapters.
- Tree file chunks now use `FileCursor` continuation state in the loading path;
  numeric SQL offsets are no longer required by the TreeView integration.
- Repository Blob-table loading now drains internal SQL chunks automatically,
  so the alternative view no longer exposes SQL page controls by default.
- Repository `FileNode` projections now carry metadata-presence flags from the
  backend for the shared filter model.
- Tree file queries now apply the same typed media, file-type, archive, and
  torrent filters for JSON and SQLite sources, including media-filter negation.
- Directory nodes with no descendant files matching the active typed filter are
  now omitted from both JSON and repository trees.
- JSON tree projections now retain the same metadata-presence flags as
  repository projections.
- The repository TreeView root node now uses the same discovered repository
  root basename.
- Startup restoration now advances to the next saved document after the
  asynchronous table/tree render completes, so multiple JSON and repository
  tabs are restored in sequence.
- Source opening now validates JSON before creating a tab and normalizes
  repository subdirectories to their discovered repository root.
- Activating a File node in the TreeView now opens its source-relative path in
  the configured external application.
- Added a `Copy Path` action for the active file reference in the detail pane.
- File nodes now provide a right-click menu for copying their name or
  source-relative path directly from the TreeView.
- Directory nodes now provide right-click actions for copying their relative
  path and filtering the current tab to that directory.
- File nodes now provide a right-click action for filtering the current tab to
  the selected relative path.
- File nodes now also provide an explicit `Show details` context action.
- Added GTK-independent `NestedFileNode` projections and GUI source adapters
  for bounded repository archive-entry and torrent-file pages.
- Fixed a startup segmentation fault caused by registering the view-mode
  callback before the document-page Builder had created its ComboBox.
- Fixed malformed detail-pane Builder nesting that attempted to add the Copy
  Path button to a checksum expander.
- Fixed the `Details below` layout restoring a zero-height list area after
  loading by deferring vertical splitter positioning until GTK allocates it.
- Added a close button directly to each document tab label.
- The filter bar now hides while loading so the progress bar is the active
  toolbar content and reappears when loading finishes.
- Filter bars are now owned by individual document tabs; the global
  `mainwindow.ui` filter slot has been removed.
- Media preview selection now gives audio priority over embedded cover-art
  image metadata, so MP3 files use the audio path instead of the image preview.
- Tree and Blob views are now separate pages in a per-document `GtkNotebook`
  instead of being shown simultaneously.
- Added a repository-directory chooser. It searches the selected directory and
  its parents for `.dosierskanilo` and opens the matching SQLite repository.
- Added First/Prev/Next/Last repository navigation, selectable page sizes, and
  an All rows mode for comparison experiments.
- Restored all saved open documents when startup restoration is enabled.
- Added mode icons, paths/tooltips, and a keyboard shortcut for repository tabs.
- Added a shared data-source adapter for JSON files and DosierSkanilo SQLite
  repository roots.
- Repository roots can now be opened as read-only GUI documents through the
  DosierSkanilo library API.
- Added bounded page loading to the shared JSON/repository data-source adapter
  as preparation for GUI pagination.
- Added Previous/Next page controls for SQLite repository documents while
  keeping JSON documents fully loaded for compatibility.
- Repository filter changes now reload SQLite pages through backend query
  filters instead of filtering the complete repository in the GUI.
- Repository detail records are now loaded asynchronously on row selection,
  keeping nested metadata out of the initial page payload.
- Fixed media filters so selecting video does not allow image-only rows through via another metadata filter.
- Added a recent-files submenu to the File menu with duplicate suppression, reverse-use ordering, a configurable maximum count, and a Preferences action to clear the list.
- Moved the File/Edit/Help menu entries into the GtkBuilder main window layout so the menus are now static UI and only their callbacks, ghosting, and keyboard shortcuts are wired in D.
- Moved the shared filter entry, toggle buttons, and apply/clear controls into `source/ui/filterbar.ui` and `source/ui/filterbar.d` so the main window toolbar now embeds the filter block as its own UI unit.
- Improved the video preview track labels by using additional stream metadata where available, and fixed the subtitle track selector so selecting Off no longer snaps back to the active subtitle.
- Moved the periodic video preview progress timer into `source/ui/previewprogress.d` so the main window entry point no longer owns the live preview heartbeat.
- Moved the startup tab-restoration and self-test shutdown workflow into `source/ui/startupworkflow.d` so the main window entry point no longer owns the startup queue wiring.
- Moved the notebook/window lifecycle signal wiring into `source/ui/windowlifecycle.d` so startup and shutdown hooks are grouped separately from the main window actions.
- Moved the toolbar and filter signal wiring into `source/ui/toolbarbindings.d` so `mainwindow.d` keeps the action implementations but no longer owns the hookup boilerplate.
- Moved the duplicated filter-reset state cleanup into `source/ui/selectionstatus.d` so the toolbar and menu actions share one helper.
- Moved the performance-metrics reset helper into `source/ui/selectionstatus.d` so status-related UI actions stay grouped together.
- Moved the shared GTK application CSS bootstrap into `source/ui/styles.d` so the main window module no longer owns style provider setup.
- Moved the open-JSON file chooser into `source/ui/fileopendialog.d` so `mainwindow.d` now only passes the load callbacks into the dialog helper.
- Moved the keyboard shortcuts and About dialogs into `source/ui/helpdialogs.d` so `mainwindow.d` now only routes the menu actions to dedicated UI helpers.
- Updated the About dialog version to match the current 0.6.x release line instead of the stale placeholder.
- Raised the Glade/GTK Builder UI minimum requirement from GTK 3.10 to GTK 3.22 across the UI definition files.
- Moved the top-level window shell, shared toolbar, and notebook layout into a GtkBuilder UI file so the startup code now binds the static structure instead of constructing it manually.
- Moved the main menu bar container into the GtkBuilder shell so the top-level layout now owns the menu placement while D keeps the action wiring.
- Moved the static File/Edit/Help menu shells into the GtkBuilder shell so the menu hierarchy now lives with the rest of the layout and D only appends runtime actions.
- Moved the Preferences dialog form into a GtkBuilder UI file so the dialog layout and its default widget state now live alongside the other UI definitions.
- Moved the remaining video preview rendering default into the GtkBuilder UI file so the preview widget setup no longer needs a D-side special case.
- Fixed the main Builder startup warning by letting the window keep the root widget from Glade instead of adding it again, and removed the unsupported GtkScale value property from the preview UI.
- Moved static detail and preview widget defaults from D setup code into the GtkBuilder UI files so the runtime code now mainly wires behavior and state changes.
- Continued the UI refactor by moving the detail preview, detail pane, and selection/status helpers into dedicated `source/ui/` modules so `mainwindow.d` keeps shrinking toward pure orchestration.
- Fixed the video preview control visibility so the volume slider remains available for video rows even when the preview path cannot be resolved immediately.
- Continued the UI refactor by moving the Preferences dialog orchestration into `source/ui/preferencesdialog.d` so `mainwindow.d` only passes state and callbacks.
- Fixed the video preview volume slider initialization by explicitly setting a 0-1 range and syncing it to the active document volume.
- Compact the BinaryBlob table header labels, keep the full column names in header tooltips, show image scaling buttons only for image previews, and add icon-based video controls plus preview track selectors.
- Populate the video preview track selectors from GStreamer stream metadata when available and align the video/audio/subtitle dropdowns side by side.
- Cache the loaded image preview pixbuf so resize-driven preview refreshes no longer reopen the same file on every layout pass.

## Release 0.6.0 - 2026-04-19

- Reattach the image preview widget to the scrolled preview container so image previews are visible again after the video layout adjustments.
- Restore a 640x360 minimum size for the video aspect frame and center it vertically so the preview does not collapse to an undersized box when the splitter is narrow.
- Removed the fixed 640x480 sizing from the video preview so the embedded frame can keep growing with the splitter instead of capping out early.
- Let the embedded video drawing area fill the aspect frame instead of centering it, so the video preview no longer appears bottom-aligned.
- Continued the UI refactor by moving the tab page root and status labels into a GTK Builder layout, so the outer shell is now also editable as UI data.
- Continued the UI refactor by moving the right-hand details pane containers into a second GTK Builder layout while keeping widget behavior in D.
- Started the UI refactor by moving the preview/details pane hierarchy into a GTK Builder layout so the structure can be edited independently of the D wiring.
- Added a Preferences field for the external opener program and wired known-file double-clicks to open the selected file with that program.
- Added icon-based preview scaling modes above the image preview, with Contain as the default and the selected mode persisted across exits.
- Kept the preview caption below the image area so the available space is controlled by the chosen scaling mode instead of a manual splitter.
- Added a right-hand preview pane next to the metadata expanders so the selected row can show image previews or media summaries with a fixed-width preview area.
- Added embedded video playback controls under the preview area, including autostart, play/pause, jump buttons, and adjustable stream volume.
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
