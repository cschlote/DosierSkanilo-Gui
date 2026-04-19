# Open Issues

- The top-level splitter still snaps back to the maximum width after loading a file, so the current layout clamping is not stable enough.
- The preview pane can stay visually empty on first video selection even though audio already plays; the preview refresh path likely races widget realization and sink attachment.
- The preview/details splitter position is still not restored reliably, which suggests the current save/restore path needs a dedicated layout lifecycle pass.
- Switching between video rows still makes the window grow horizontally, so the embedded video area is still influencing the parent layout too much.

## TODO

## Next

- Add export actions (CSV/JSON subset)
- Add row activation action (copy path, open in file manager)
- Add unit tests for CLI help text and startup filter parsing
- Revisit the top-level splitter behavior and redesign it instead of patching around it

## Later

- Revisit whether any scanner/analysis actions should be embedded or kept in the CLI
- Add release packaging and tagging workflow
- Verify stdout/stderr ordering after moving `argsArray` to `__gshared`; a future race or interleaving issue may still surface.
