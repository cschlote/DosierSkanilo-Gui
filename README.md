# DosierSkanilo GUI

`DosierSkanilo-Gui` is a classic GTK desktop frontend for browsing and filtering
precomputed DosierSkanilo JSON index files and `.dosierskanilo` repositories.

It is a read-only frontend to the DosierSkanilo scanner/library stack. The GUI
and CLI use the same backend library; scanning, checksum generation,
archive/torrent inspection, duplicate analysis, and JSON writing are currently
started through the CLI.

The planned direction is operation parity: both clients will invoke the same
backend scan, metadata, and analysis operations. WP-09.1 defines their shared
request, progress, and cancellation contract, but backend execution and the GUI
task runner are not implemented yet. Pause/resume is a planned WP-09.1b contract
extension. See WP-09 in the backend plan at
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
- structured MediaInfo stream details with format, dimensions/channels, and
  available rate, language, and duration fields
- wrapped, selectable file-type signatures in the detail pane
- a fallback file overview for files without specialized metadata
- persistent window geometry, splitter positions, tabs, preferences, and
  clipboard copy actions
- background loading/filtering with stale-request cancellation and performance
  timings
- Previous/Next page navigation for SQLite repository documents
- CSV and JSON export of the active tab's filtered row subset

The GUI does not yet expose the scanner-side workflow from the overhauled
DosierSkanilo backend. Use the CLI for scan, analyze, and write-back jobs.
The planned direction is for CLI and GUI to start the same library operations;
backend execution, GUI task management, and the planned pause/resume extension
are tracked as WP-09 in the backend plan at
`https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md`.
For the planned incremental TreeView filter model and GC-friendly GUI algorithms,
see [`docs/GUI-REDESIGN.md`](docs/GUI-REDESIGN.md).

The GUI focuses on a traditional desktop workflow:

- menu bar (`File`, `Edit`, `Help`)
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
