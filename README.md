# DosierSkanilo GUI

`DosierSkanilo-Gui` is a classic GTK desktop frontend for browsing and filtering
DosierSkanilo JSON index files.

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

With startup arguments:

```bash
./build/bin/dosierskanilo-gui --json ./.filescanner.json --load
```

## CLI Options

- `-j`, `--json <file>`: JSON file to open
- `-l`, `--load`: load on startup
- `-d`, `--duplicates`: start in duplicate-only mode
- `-q`, `--query <text>`: apply initial text filter
- `--case-sensitive`: case-sensitive filter matching
- `--no-auto-filter`: disable auto-apply filter after load
- `-h`, `--help`: print CLI help and exit

## Current Features

- load JSON index file
- compatibility with wrapper and legacy JSON shapes
- duplicate-only view mode
- text filter by file name and SHA1
- sortable table columns

## Documentation

- `docs/README.md`
- `docs/ARCHITECTURE.md`
- `CHANGELOG.md`
- `TODO.md`
- `docs/DATAFILE_EXTRACTION.md`

## Privacy Note

Commit messages and docs in this repository should avoid disclosing private scan
paths or dataset details.
