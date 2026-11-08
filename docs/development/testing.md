---
title: Testing
description: Internal and external test layers for DosierSkanilo GUI.
area: development
---

# Testing

This document explains how the GUI unit, display-backed, and integration tests
are built, executed, and interpreted. The verification policy is summarized in
[`AGENTS.md`](../../AGENTS.md) and
[`engineering-workflow.md`](engineering-workflow.md#verification).

## Test layers

### 1. Default unit suite

GTK-independent model, filtering, projection, request, state, and export logic
is covered by `unittest` blocks. The default suite runs without a display.

- `DUB_COMPILER=ldc2 ./scripts/test.sh` runs the suite with coverage.
- `dub test --compiler=ldc2` is the quick loop while editing.
- Coverage listings and the total are written below `build/coverage/`.

Display-dependent tests are guarded by environment variables and skip in the
default suite.

### 2. Display-gated opt-in tests

These tests require a usable GTK display and are enabled individually:

- `DOSIER_GUI_ACTIVATION_TEST=1` enables TreeView activation checks.
- `DOSIER_GUI_TABLE_SCROLL_TEST=1` enables long virtual-table scrolling across
  evicted chunks.
- `DOSIER_GUI_TREE_LOAD_TEST=1` enables expanded loading-placeholder recovery.
- `DOSIER_GUI_FILTER_TEST=1` enables filter-signal and per-tab state checks.

Run them through `DC=ldc2 ./scripts/test-display.sh`, which starts Xvfb when
needed, or run one test directly with
`DOSIER_GUI_*_TEST=1 dub test --compiler=ldc2 -- --threads=1 --include='...'`.

### 3. Display suite and startup self-tests

`scripts/test-display.sh` is the GUI end-to-end gate. It:

- runs the unit suite with display-gated tests enabled
- builds the GUI
- runs startup self-tests against the backend JSON fixture
- verifies restored splitter positions and embedded video-sink availability
- runs a JSON analyze operation through the Tools path
- creates a SQLite repository, then runs scan, metadata, analyze, and the
  synthetic pause/cancel operation checks
- loads a generated 95,001-record JSON catalog and its SQLite import as smoke
  tests
- fails on GTK criticals through `G_DEBUG=fatal-warnings` in self-test mode

Without `xvfb-run`, `Xvfb`, or an existing `DISPLAY`, the script prints a skip
message and exits successfully. A pass must therefore be confirmed from the
logged test lines, not only from the exit code.

### 4. Lint and metadata checks

`scripts/lint.sh` currently runs `dub describe` only; there is no dedicated
Markdown or shell linter in this repository. Check documentation links manually
and run the backend lint script when changing shared backend sources.

### 5. External CI

- GitHub Actions runs lint, build, default tests, the Xvfb display suite, and
  tag-driven release jobs. The build jobs check out the sibling backend.
- GitLab CI runs lint, build, and the default test suite. Tag pipelines publish
  release assets.
- When remote CI is intentionally disabled, run the equivalent local checks and
  record that they were run locally.

## Commands

| Purpose | Command |
| --- | --- |
| Fast unit feedback | `dub test --compiler=ldc2` |
| Full unit/coverage gate | `DUB_COMPILER=ldc2 ./scripts/test.sh` |
| Display-backed gate | `DC=ldc2 ./scripts/test-display.sh` |
| Filter benchmark | `DC=ldc2 ./scripts/benchmark-filters.sh` |
| Build | `./scripts/build.sh` |

## Policy

- After a change, run the smallest relevant test layer.
- Before merging a feature branch into `main` or preparing a release, run the
  full unit suite and the display suite.
- Record the exact commands and results in the handover or release evidence.
  Never claim a test passed without running it.

## Current baseline

On 2026-11-08 the default suite reported 76 passing tests and 36.43 % coverage;
the Xvfb display suite passed, including the 95,001-record JSON and SQLite smoke
loads. Treat these numbers as a recorded snapshot, not a permanent contract.
