---
title: Engineering Workflow
description: Change, verification, versioning, branch, and release rules for DosierSkanilo GUI.
area: development
---

# Engineering Workflow

This document is the detailed companion to [`AGENTS.md`](../../AGENTS.md). It
applies to human contributors and coding agents.

## Change scope and user work

- Solve the requested problem with the smallest coherent change. Avoid drive-by
  refactors, renames, and formatting churn.
- Inspect the working tree before editing. Treat unfamiliar modified or
  untracked files as user work and leave them untouched unless the task
  explicitly requires changing them.
- Do not revert or reformat unrelated user changes.
- Follow the existing module boundaries, GTK ownership rules, and naming
  patterns. D style and Ddoc follow the shared
  [D language guide](https://github.com/cschlote/DosierSkanilo/blob/main/docs/development/d-language-guide.md).
- When a task touches the GUI and backend together, keep the API and
  user-facing behavior consistent and verify both repositories.
- If ambiguity or an environment limitation could affect correctness, stop and
  state the assumption instead of guessing.

## Documentation gaps and approval

If a goal, rule, or procedure cannot be derived logically from `AGENTS.md` and
the linked documentation, do not invent a new workflow. Stop, explain the gap,
and ask for approval. After approval, update `AGENTS.md` or the appropriate
linked document in the same change so the rule is explicit for the next
contributor. Documentation is part of the implementation, not an optional
afterthought.

## Verification

The test layers and their exact commands are documented in
[`testing.md`](testing.md). Summary:

- Run the smallest relevant check after editing. Examples:
  - Pure logic/model code: `DUB_COMPILER=ldc2 ./scripts/test.sh`.
  - UI, tree, table, preview, or GTK lifecycle: the unit suite plus
    `DC=ldc2 ./scripts/test-display.sh`.
  - Filter or tree performance-sensitive code: the above plus
    `DC=ldc2 ./scripts/benchmark-filters.sh`.
  - Build/package metadata: `./scripts/build.sh` and `./scripts/lint.sh`.
  - Markdown: no Markdown linter is configured yet; check links manually.
- `test-display.sh` runs under Xvfb (or an existing `DISPLAY`) and includes
  JSON/repository self-tests, splitter/video-sink checks, and the
  95,001-record JSON/SQLite smoke loads. Without a display server it exits
  successfully without running the suite, so confirm the test lines in the log
  rather than relying only on the exit code.
- Report any check that could not be run and why. Do not claim a pass without
  running the command.
- Prefer local verification during normal iteration. If remote CI is
  intentionally disabled, run the equivalent local checks and use `[skip ci]`
  only where it is appropriate.
- Before merging a feature branch into `main` or preparing a release, run the
  full unit suite and the display suite, not only the targeted tests.

## Changelog, docs, and planning

- Update `CHANGELOG.md` for every user-visible behavior change. Keep entries
  under `## Unreleased` and write them in simple English.
- Internal refactors and test-only changes normally do not need a changelog
  entry; documentation-only changes may add one when they affect contributors.
- Update `TODO.md` when a work item, verification result, or known limitation
  changes. Do not leave completed work presented as open.
- Keep Ddoc and module headers complete. The shared requirements are in the
  [D language guide](https://github.com/cschlote/DosierSkanilo/blob/main/docs/development/d-language-guide.md#ddoc).
- Keep README and docs links accurate when moving or adding documentation.

## Versioning

- The GUI is not a backend API, but its DUB package releases still use
  Semantic Versioning because packaging and release tags are versioned.
  Release tags use `vX.Y.Z`.
- Bump major for incompatible user-facing changes, minor for backward-compatible
  features, and patch for fixes.
- Keep GUI versions independent of the backend package version. A paired release
  uses compatible backend and GUI versions but does not force identical numbers.
- The backend dependency is consumed as a DUB path dependency during local
  development. Verify changes against the intended backend commit before a
  paired release.

## Branches and merges

- Keep work on a feature or integration branch and keep unrelated work out of
  the change.
- Merge completed work into `main` with `--no-ff` so the integration point stays
  explicit. In the shared branch model this is normally `testing` into `main`.
- After merging, fast-forward `testing` to `main` so both branches point at the
  same verified state.
- Push branches to all configured mirrors when publishing the result.

## Releases

Follow the backend [release checklist](https://github.com/cschlote/DosierSkanilo/blob/main/docs/RELEASE-CHECKLIST.md).
Before creating a release commit, review that checklist explicitly and confirm
that documentation, scripts, package metadata, changelog, and tests all describe
the same intended state. The non-negotiable points are:

- Create the release commit on the integration branch: move `## Unreleased` to
  `## Release X.Y.Z`, update package metadata, and keep the summary in simple
  English.
- Merge the release commit to `main` first, then create the annotated tag
  `vX.Y.Z` on the `main` merge commit. Do not tag a branch-only commit.
- Source archives embed the tagged commit SHA. Moving or re-creating a tag
  changes the archive hash even when the tree is identical.
- Update Flatpak `sha256` pins in a follow-up commit on `main` after downloading
  the published tag archive. Do not tag the hash-update commit.
- Publish the paired backend release and verify tag metadata and archive hashes
  together.

## Reporting risks

State assumptions, unresolved questions, known risks, and follow-up work
explicitly. Say which checks passed, which were skipped, and what evidence is
still missing when a change is handed over.
