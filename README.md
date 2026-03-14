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
