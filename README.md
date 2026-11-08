# DosierSkanilo GUI

`DosierSkanilo-Gui` is a classic GTK desktop frontend for browsing and filtering
DosierSkanilo JSON catalogs and `.dosierskanilo` repositories.

The GUI and CLI use the same backend library for scan, metadata, and analysis
operations. The GUI's `Tools` menu runs those operations in background workers
and reports backend progress, cancellation, and safe pause/resume state.

Repository documents support scan, metadata, and analysis. JSON documents
support scan and analysis, including selected metadata extraction as part of
those operations. Targets remain explicit: JSON scan asks for a filesystem root,
while repository operations use the active repository root. See WP-09 in the
backend plan at
`https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md`.

The GUI currently supports:

- loading current library JSON and older wrapper/legacy shapes
- loading initialized `.dosierskanilo` SQLite repositories through the shared
  DosierSkanilo library API
- text filtering by file name or SHA1
- media filters for video, audio, image, and text streams, including NOT
  inversion and hit counters
- presence filters for file type, archive, and torrent metadata
- sortable table columns for index, size, checksum state, file type, media
  info, archive, and torrent flags in JSON and full-list views; the paged
  cursor-backed repository Blob table is not sortable
- detail panes for checksums, known file names, MediaInfo, file type, archive,
  and torrent metadata
- archive and torrent entry trees in their respective scrollable Previewers;
  document-detail expanders show compact archive/torrent metadata summaries
- text file contents in the large scrollable Previewer, with file attributes in
  the summary below
- vertically scrollable document details alongside the existing horizontal
  Previewer splitter
- structured MediaInfo stream details with format, dimensions/channels, and
  available rate, language, and duration fields
- wrapped, selectable file-type signatures in the detail pane
- a fallback file overview for files without specialized metadata
- persistent window geometry, splitter positions, tabs, preferences, and
  clipboard copy actions
- background loading/filtering with stale-request cancellation and performance
  timings
- directory filtering reuses materialized TreeView nodes through a filtered GTK
  model, preserving node identity and expanded state across filter changes
- bounded internal row paging for repositories, with Previous/Next file
  navigation in the detail pane
- CSV and JSON export of the active tab's filtered row subset
- shared backend scan, metadata, and analysis actions with per-operation options
- background task progress and terminal results in the owning document tab
- cooperative cancellation and state-aware pause/resume at backend checkpoints
- repository/catalog write serialization through backend target leases
- JSON tabs track unsaved changes with Save (Ctrl+S), Revert to Stored, and
  save/discard/cancel prompts; SQLite tabs remain transactional without a dirty
  marker
- archive files expand lazily in the main tree, including synthesized inner
  directories and nested archives; selecting a member extracts it internally
  into the shared member-content cache and previews it

For the filtered TreeView model and GC-friendly GUI algorithm design, see
[`docs/GUI-REDESIGN.md`](docs/GUI-REDESIGN.md).

The GUI focuses on a traditional desktop workflow:

- menu bar (`File`, `Edit`, `Tools`, `Help`)
- keyboard shortcuts, including tree navigation with `Left` (select parent) and
  `Right` (expand and select the first child)
- preferences dialog
- sortable table view for JSON and full-list results; paged repository Blob
  tables keep backend order
- row selection details

## Build

The build needs a sibling `../DosierSkanilo` checkout, a D compiler with DUB,
and GTK3/GStreamer development packages. `scripts/install-dependencies.sh`
installs the supported local dependencies.

```bash
dub build --compiler=ldc2
```

## Run

```bash
./build/bin/dosierskanilo-gui
```

Open JSON files from `File` > `Open JSON File`, or repository directories from
`File` > `Open Repository Directory`. A selected directory may be the repository
root or any directory below it; the nearest `.dosierskanilo` directory is used.
Catalog paths are root-relative, so a copied, moved, or remounted repository
opens at its current path even when the stored advisory root differs. For
multi-million-record catalogs, import the JSON into a repository first: direct
JSON tabs keep the complete catalog and derived index in memory.

## Startup Controls

- positional `*.json` arguments: open JSON files on startup
- positional repository directories: open `.dosierskanilo` repositories on startup
- `-q`, `--query <text>`: prefill the text filter
- `-v`, `--verbose`: enable verbose logging
- `--case-sensitive`: case-sensitive filter matching
- `--no-auto-filter`: disable auto-apply filter after load
- `--self-test`, `--self-test-operation <scan|metadata|analyze>`,
  `--self-test-operation synthetic-pause|synthetic-cancel`, `--self-test-save`,
  `--self-test-delay <ms>`, `--self-test-check-splitter`,
  `--self-test-check-video-sinks`: automation and CI smoke-test controls; use
  `--help` for the complete list
- `-h`, `--help`: print CLI help and exit

## Current Features

- open JSON catalogs or repository directories from the command line or the
  file chooser; `Ctrl+O` opens a JSON file and `Ctrl+Shift+O` opens a repository
- browse a tree-first directory view backed by `CatalogBackend` for both JSON
  and SQLite sources
- expand archive files lazily, including nested archives and synthesized inner
  directories; selecting a member extracts it internally into the shared cache
  and previews it
- navigate the tree with `Left` (select parent) and `Right` (expand and select
  the first child)
- text filter by file name and SHA1
- media, file type, archive, and torrent presence filters
- sortable table columns in JSON and full-list views; paged repository Blob
  tables are not sortable
- detailed record panes with copy actions and raw JSON inspection
- JSON document sessions with modified markers, Save/Revert, and conflict
  prompts
- export filtered row subsets as CSV or GUI-specific JSON summaries

## Documentation

- `docs/README.md`
- `docs/ARCHITECTURE.md`
- `docs/development/engineering-workflow.md` - change, verification,
  versioning, and release rules
- `docs/development/testing.md` - test layers and local/CI commands
- [Shared D language guide](https://github.com/cschlote/DosierSkanilo/blob/main/docs/development/d-language-guide.md)
- `CHANGELOG.md`
- `TODO.md`
- `docs/DATAFILE_EXTRACTION.md`

## License

DosierSkanilo-Gui is licensed under [GPL-3.0-only](LICENSE.md).

## Privacy Note

Commit messages and docs in this repository should avoid disclosing private scan
paths or dataset details.
