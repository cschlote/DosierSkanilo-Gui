# DosierSkanilo GUI Packaging

Release scaffolding for Arch/AUR, Flatpak, Fedora and Debian is kept here. The
public source repository is
`https://gitlab.vahanus.net/dlang/dosierskanilo-gui`.

## Package names

- `dosierskanilo-gui`: stable GTK frontend
- `dosierskanilo-gui-git`: development snapshot of the GTK frontend

The CLI/backend is packaged separately as `dosierskanilo` and
`dosierskanilo-git`. There is intentionally no umbrella package.

The latest tagged release is `0.8.0` (`v0.8.0`). Replace checksum placeholders
before publishing packages. The GUI compiles the `DosierSkanilo` D modules into
the executable and requires GTK3/GTKD runtime libraries; it does not require
the `dosierskanilo` CLI package at runtime. The project is licensed under
`GPL-3.0-only`; package recipes should install the repository's `LICENSE.md`.

Build and validate recipes in clean native environments. The Flatpak draft uses
the backend as a sibling source module and needs an offline/vendorable DUB
dependency strategy before Flathub submission.
