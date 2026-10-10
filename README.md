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
  info, archive, and torrent flags
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
- Previous/Next page navigation for SQLite repository documents
- CSV and JSON export of the active tab's filtered row subset
- shared backend scan, metadata, and analysis actions with per-operation options
- background task progress and terminal results in the owning document tab
- cooperative cancellation and state-aware pause/resume at backend checkpoints
- repository/catalog write serialization through backend target leases

Archive entries are currently searchable/renderable as nested metadata details,
not as ordinary deduplicated content blobs. The target virtual-content model and
storage-neutral catalog API are planned in WP-13 of the backend plan.

For the filtered TreeView model and GC-friendly GUI algorithm design, see
[`docs/GUI-REDESIGN.md`](docs/GUI-REDESIGN.md).

The GUI focuses on a traditional desktop workflow:

- menu bar (`File`, `Edit`, `Tools`, `Help`)
- keyboard shortcuts
- preferences dialog
- sortable table view
- row selection details

## Build

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

## Startup Controls

- positional `*.json` arguments: open JSON files on startup
- positional repository directories: open `.dosierskanilo` repositories on startup
- `-q`, `--query <text>`: prefill the text filter
- `-v`, `--verbose`: enable verbose logging
- `--case-sensitive`: case-sensitive filter matching
- `--no-auto-filter`: disable auto-apply filter after load
- `-h`, `--help`: print CLI help and exit

## Current Features

- open JSON files from the command line or the file chooser
- open repository directories from the file chooser or command line
- `Ctrl+O` opens a JSON file; `Ctrl+Shift+O` opens a repository directory
- load JSON index files for browsing and inspection
- compatibility with wrapper and legacy JSON shapes
- text filter by file name and SHA1
- media, file type, archive, and torrent presence filters
- sortable table columns
- detailed record panes with copy actions and raw JSON inspection
- export filtered row subsets as CSV or GUI-specific JSON summaries

## Documentation

- `docs/README.md`
- `docs/ARCHITECTURE.md`
- `CHANGELOG.md`
- `TODO.md`
- `docs/DATAFILE_EXTRACTION.md`

## License

DosierSkanilo-Gui is licensed under [GPL-3.0-only](LICENSE.md).

## Privacy Note

Commit messages and docs in this repository should avoid disclosing private scan
paths or dataset details.
