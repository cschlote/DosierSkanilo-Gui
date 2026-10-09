# AGENTS

Minimal guidelines for coding AI working in this repository:

- Make focused changes that directly solve the requested task.
- Do not revert or reformat unrelated user changes.
- Follow the existing D style and module structure unless the task requires a different approach.
- Update `CHANGELOG.md` for user-visible behavior changes.
- The GUI is not a backend API, but its DUB package release tags must still use
  Semantic Versioning in the `vX.Y.Z` form. Keep GUI versions independent of the
  backend package version; bump major for incompatible user-facing changes,
  minor for backward-compatible features, and patch for fixes.
- Run the smallest relevant verification step after editing and report if verification could not be completed.
- Flag assumptions, risks, or follow-up work clearly when they affect correctness.
