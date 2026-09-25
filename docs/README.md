# DosierSkanilo GUI - Documentation

This directory contains project documentation for the GTK frontend.

## Contents

- `ARCHITECTURE.md`: high-level architecture and module boundaries
- `GUI-REDESIGN.md`: current directory-tree implementation and source-opaque query plan
- `CHANGELOG.md`: user-visible and engineering changes by release
- `TODO.md`: planned next steps
- `UI_REFACTOR.md`: current UI issues and the Glade-based refactor direction
- `DATAFILE_EXTRACTION.md`: extracted data-format notes from scanner project

## Development Flow

Typical local loop:

```bash
./scripts/build-all.sh
```

Or run stages individually:

```bash
./scripts/lint.sh
./scripts/build.sh
./scripts/test.sh
./scripts/build-docs.sh
```

## Debugging With Startup Arguments

Launch the GUI with positional JSON files to open them on startup, for example:

```bash
./build/bin/dosierskanilo-gui ./scan-a.json ./scan-b.json -v
```

The startup parser also accepts filter state and verbose logging, but the GUI
still remains a read-only browser for precomputed scanner output.
