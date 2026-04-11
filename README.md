# DosierSkanilo GUI

`DosierSkanilo-Gui` is a classic GTK desktop frontend for browsing and filtering
precomputed DosierSkanilo JSON index files.

It is a read-only companion to the DosierSkanilo scanner/library stack:
scanning, checksum generation, archive/torrent inspection, duplicate analysis,
and JSON writing remain in the CLI and backend libraries.

The GUI currently supports:

- loading current library JSON and older wrapper/legacy shapes
- text filtering by file name or SHA1
- media filters for video, audio, image, and text streams, including NOT
	inversion and hit counters
- presence filters for file type, archive, and torrent metadata
- sortable table columns for index, size, checksum state, file type, media
	info, archive, and torrent flags
- detail panes for checksums, known file names, MediaInfo, file type, archive,
	and torrent metadata
- persistent window geometry, splitter positions, tabs, preferences, and
	clipboard copy actions
- background loading/filtering with cancel support and performance timings

The GUI does not yet expose the scanner-side workflow from the overhauled
DosierSkanilo backend. Use the CLI for scan, analyze, and write-back jobs.

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

Open JSON files from `File` > `Open JSON`.

## Startup Controls

- positional `*.json` arguments: open JSON files on startup
- `-q`, `--query <text>`: prefill the text filter
- `-v`, `--verbose`: enable verbose logging
- `--case-sensitive`: case-sensitive filter matching
- `--no-auto-filter`: disable auto-apply filter after load
- `-h`, `--help`: print CLI help and exit

## Current Features

- open JSON files from the command line or the file chooser
- load JSON index files for browsing and inspection
- compatibility with wrapper and legacy JSON shapes
- text filter by file name and SHA1
- media, file type, archive, and torrent presence filters
- sortable table columns
- detailed record panes with copy actions and raw JSON inspection

## Documentation

- `docs/README.md`
- `docs/ARCHITECTURE.md`
- `CHANGELOG.md`
- `TODO.md`
- `docs/DATAFILE_EXTRACTION.md`

## Privacy Note

Commit messages and docs in this repository should avoid disclosing private scan
paths or dataset details.
