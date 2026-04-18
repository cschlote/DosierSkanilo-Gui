# TODO

## Next

- Add export actions (CSV/JSON subset)
- Add row activation action (copy path, open in file manager)
- Add unit tests for CLI help text and startup filter parsing

## Later

- Revisit whether any scanner/analysis actions should be embedded or kept in the CLI
- Add release packaging and tagging workflow
- Verify stdout/stderr ordering after moving `argsArray` to `__gshared`; a future race or interleaving issue may still surface.
