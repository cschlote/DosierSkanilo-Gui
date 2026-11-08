# DosierSkanilo GUI Packaging

Release scaffolding for Arch/AUR, Flatpak, Fedora and Debian is kept here. The
public source repository is
`https://gitlab.vahanus.net/dlang/dosierskanilo-gui`.

## Package names

- `dosierskanilo-gui`: stable GTK frontend
- `dosierskanilo-gui-git`: development snapshot of the GTK frontend

The CLI/backend is packaged separately as `dosierskanilo` and
`dosierskanilo-git`. There is intentionally no umbrella package.

The latest tagged release is `0.13.0` (`v0.13.0`). Replace checksum placeholders
before publishing packages. The GUI compiles the `DosierSkanilo` D modules into
the executable and requires GTK3, GStreamer, and SQLite runtime libraries; it
does not require the `dosierskanilo` CLI package at runtime. The project is
licensed under
`GPL-3.0-only`; package recipes should install the repository's `LICENSE.md`.

Build and validate recipes in clean native environments.

## Dependencies

### Build dependencies

- D compiler and DUB: `ldc2` is the tested compiler; DUB resolves `gtk-d`,
  `gtk-d:gstreamer`, `silly`, `va_toolbox`, and the sibling `dosierskanilo`
  path dependency.
- C toolchain and linker (`gcc`/`cc`), `pkg-config`.
- GTK3 development headers plus GStreamer core and plugin-base development
  headers: `libgtk-3-dev`, `libgstreamer1.0-dev`,
  `libgstreamer-plugins-base1.0-dev`, `libsqlite3-dev` (Debian/Ubuntu);
  `gtk3`, `gstreamer`, `gst-plugins-base`, `sqlite` (Arch);
  `gtk3-devel`, `gstreamer1-devel`, `gstreamer1-plugins-base-devel`,
  `sqlite-devel` (Fedora).
- A sibling `../DosierSkanilo` checkout for the shared backend sources.
- Documentation: `adrdox` is fetched by DUB; GDC is preferred when available.

The helper script used by CI is
[`../scripts/install-dependencies.sh`](../scripts/install-dependencies.sh);
the package recipes below are the authoritative distribution metadata.

### Mandatory runtime dependencies

- GTK3 runtime (`libgtk-3-0`, `gtk3`, `gtk3`) for the window and widgets.
- GStreamer 1.0 core and base plugins (`libgstreamer1.0-0`,
  `gstreamer1.0-plugins-base`; `gstreamer`, `gst-plugins-base`;
  `gstreamer1`, `gstreamer1-plugins-base`) for `playbin` and the X11 video
  sink.
- SQLite runtime library (`libsqlite3.so.0`); the backend is compiled into the
  GUI and links it directly.
- The platform C runtime and `libgcc_s`.

### Optional runtime dependencies

| Command or package | Enables |
| --- | --- |
| MediaInfo library (`libmediainfo`) | media metadata and stream details |
| `gstreamer1.0-plugins-good` / `gst-plugins-good` | `gtksink` and common audio/video elements |
| `gstreamer1.0-libav`, `-bad`, `-ugly` / `gst-libav`, `gst-plugins-bad`, `gst-plugins-ugly` | additional codecs |
| `file` | file-type signatures |
| `unzip` | ZIP archive expansion and preview |
| `tar` | TAR archive expansion and preview |
| `unrar` | RAR archive expansion and preview |
| `p7zip` / `7z` | 7z archive expansion and preview |
| `python3` | exact extraction of duplicate-name ZIP members |

The GUI starts and browses catalogs without the optional tools; the
corresponding media, archive, or metadata feature becomes unavailable or
degrades gracefully.

### Package mapping

- **Debian/Ubuntu:** mandatory GTK/GStreamer/SQLite libraries;
  `Recommends: libmediainfo0v5, gstreamer1.0-plugins-good, file, unzip, tar,
  unrar, p7zip-full | 7zip`; `Suggests` the extra codec packs and Python.
- **Arch:** `depends=('gtk3' 'gstreamer' 'gst-plugins-base' 'sqlite')`;
  MediaInfo, GStreamer plugin packs, and archive tools are `optdepends`.
- **Fedora:** `Requires: gtk3, gstreamer1, gstreamer1-plugins-base,
  sqlite-libs`; `Recommends` MediaInfo, `gstreamer1-plugins-good`, and the
  archive tools; `Suggests` extra codecs and Python.
- **Flatpak:** the GNOME runtime supplies GTK and GStreamer. The current draft
  only installs a prebuilt binary and license, so it does not yet bundle the
  optional codecs or archive tools and has no source build.

The current Flatpak draft installs a prebuilt `build/bin/dosierskanilo-gui` and
the license file; it does not yet build the GUI or the sibling backend from
source. A complete manifest must add both sources, the backend dependency, and
an offline/vendorable DUB dependency strategy before Flathub submission.

## Release tags and Flatpak hashes

Create annotated release tags on the `main` merge commit, after the release
commit has been merged. GitHub and GitLab source archives include the tagged
commit SHA in their archive metadata, so re-pointing or re-creating a tag
changes the archive `sha256` even when the source tree is identical.

The source archive cannot contain the final hash of itself. Tag first, download
the published archive, compute its `sha256`, then update the Flatpak manifest in
a follow-up commit on `main`. Never tag that hash-update commit, and never reuse
a hash after moving a tag.
