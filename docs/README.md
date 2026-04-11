# DosierSkanilo GUI - Documentation

This directory contains project documentation for the GTK frontend.

## Contents

- `ARCHITECTURE.md`: high-level architecture and module boundaries
- `CHANGELOG.md`: user-visible and engineering changes by release
- `TODO.md`: planned next steps
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

Launch the GUI and open a JSON file from `File` > `Open JSON`.
The startup parser is currently used for filter and preference state, not for
the full scanner workflow.
