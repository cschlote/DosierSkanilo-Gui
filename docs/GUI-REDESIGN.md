# GUI Data Model and Tree View Plan

This document describes the planned replacement for the current
`NamedBinaryBlob`-oriented table UI. The GUI is still experimental and does not
need to preserve the current widget layout or interaction model.

## Direction

The GUI now presents a directory tree with files below each directory. JSON
files and SQLite repositories should look and behave the same from the user's
perspective:

```text
source adapter -> GUI data projection -> GTK tree and detail views
```

The source adapter hides whether data comes from a JSON file or a
`.dosierskanilo` repository. Loading details, directory children, archive
entries, torrent files, and analysis results may be deferred or lazy.

The existing table of flattened `NamedBinaryBlob` values remains available as
an alternative blob-oriented view. It is useful for duplicate-oriented work,
but it is no longer the only or primary navigation model.

## Current Status

Implemented:

- GTK-independent `DirectoryNode` and `FileNode` projections.
- `DirectorySource` abstraction with JSON and repository adapters.
- SQLite `listDirectories()` and bounded `listFiles()` APIs in `DosierSkanilo`.
- Lazy directory expansion with loading and error states.
- Asynchronous repository child queries and paged file navigation.
- Per-tab expanded-directory tracking and restoration.
- Stable blob-ID selection between the TreeView and blob table where nodes are
  materialized.
- Asynchronous details for repository files outside the current table page,
  rendered directly from the selected Tree file.
- Repository Blob-table view uses a virtual GTK TreeModel with a bounded async
  cursor-page cache instead of retaining a GTK row per catalog result.
- Virtual blob rows support direct GTK value lookups, requested distant chunks
  continue through intermediate cursors, and backward requests remain queued
  while a chunk is loading.
- Previous/Next navigation for multiple known file references.
- Archive and torrent detail sections render their entry paths as nested trees.
- Repository archive and torrent trees fetch bounded first pages asynchronously
  and expose a continuation marker when additional entries exist.
- Late archive/torrent replies are checked against the active blob, selection
  generation, and loading-marker token before changing a TreeStore.
- Audio rows use the GStreamer playback controls even when metadata reports
  embedded cover art; video streams retain preview priority.

Known limitations:

- Archive/torrent continuation beyond the first 250-entry chunk still needs an
  integration test with a larger fixture, including selecting and copying a path
  on a later page.
- The virtual table has a bounded four-chunk cache and regression coverage for
  distant cursor requests and backward reload after eviction; interactive long
  scroll-forward/scroll-back behavior still needs a large-repository UI test.
- The selected tree-file cursor is not yet persisted with the per-tab filter and
  sort state.
- The blob table remains an alternative, transitional view; the directory tree
  is still the primary navigation surface.
- Several window splitters and video-preview layout behaviors remain on the
  open-issues list in `TODO.md`.

## Verification Baseline

The current GUI branch passes:

- `dub test --compiler=ldc2` — 22 tests.
- `dub build --compiler=ldc2`.
- `git diff --check`.
- GTK self-tests under `G_DEBUG=fatal-warnings` for an audio-plus-cover fixture,
  repository archive/torrent fixtures, and a large repository. Self-test mode
  selects the first row and expands remote archive/torrent roots when present.

The virtual-table integration test uses a temporary 20-row repository and a
two-row chunk size. It requests a distant row, forces earlier chunks out of the
four-chunk cache, then requests the first row while a later chunk is in flight
and verifies that the backward request completes. Audio classification and
GStreamer preroll were tested with an MP3 fixture and fake sinks; audible output
through a physical audio device has not been smoke-tested.

The source adapter is intentionally opaque. JSON and SQLite expose the same
logical result set to the GUI. SQLite may fetch internal chunks, but those
chunks must not become visible `Page 1 of N` UI state.

## JSON and Jsonizer

`NamedBinaryBlob` remains the canonical representation of the JSON file format.
Jsonizer is useful because it provides serialization, deserialization, and
compatibility handling without handwritten JSON boilerplate. The JSON adapter
should continue to use it.

The GUI should add a separate projection layer instead of replacing
`NamedBinaryBlob` immediately. Pure D types and functions in this layer must
not depend on GTK, SQLite, or Jsonizer-specific implementation details. This
makes useful parts movable to `DosierSkanilo` later without first untangling
widget code.

## GUI Data Types

The initial projection should contain read-only value types similar to:

```text
DirectoryNode
    id, parentId, name, relativePath
    childDirectoryCount, fileCount, aggregateSize

FileNode
    id, directoryId, name, relativePath
    size, modifiedAt, fileType, presenceFlags

FileDetails
    file, checksums, media, archive, torrent

ArchiveDetails
    archive identity and lazy archive entries

TorrentDetails
    torrent metadata and lazy torrent files

FilterState
    path, name, size, type, media, archive, torrent, checksum filters
```

IDs must be stable for the lifetime of a source. SQLite can use repository IDs.
The JSON adapter can create synthetic IDs based on normalized paths and blob
positions. The GTK layer must only rely on the abstract ID and not inspect its
implementation.

## Source API

The GUI-facing source interface should be small, read-oriented, and source
opaque:

```text
open(path)
root()
listDirectories(parentId)
listFiles(directoryId, filterState, sortOrder, cursor)
loadFileDetails(fileId)
loadArchiveDetails(fileId)
loadTorrentDetails(fileId)
loadAnalysis(sourceScope, analysisKind)
next(fileId, filterState, sortOrder)
previous(fileId, filterState, sortOrder)
close()
```

The JSON implementation may build an in-memory directory index when opened.
The SQLite implementation should use a query cursor or keyset internally.
Both implementations return the same projection types and logical
filtered/sorted sequences. Missing information must be represented explicitly.

Internal chunks may expose `nextCursor` and `hasMore`, but the GUI appends them
to one logical view. `next()` and `previous()` operate on stable file IDs
within the active filter and sort state.

JSON cannot display empty directories unless they are represented in the JSON
input. This capability difference should be exposed as source metadata instead
of silently producing different tree behavior.

## Per-Tab State

Every open tab owns its complete view state:

- source and root selection
- expanded directory nodes
- selected node
- filter state
- sort order
- page size and current page
- pending lazy loads
- detail view state

The toolbar may edit the current tab's filter state, but filters must not be
global. Switching tabs must restore the exact tree, filter, and detail context
of that tab.

## Tree View

The primary view should be a GTK `TreeView` backed by a lazy tree model:

- directories are expandable nodes
- files are children of directories
- child nodes are loaded when a directory is expanded
- large file lists are fetched in internal chunks and appended below the
  selected directory; user-visible pagination controls are not required
- sorting is explicit and stable
- loading and error placeholder nodes are visible states

Directory and file nodes should have context menus with actions appropriate to
the node:

- open in an external application or file manager
- copy name
- copy relative path
- copy absolute path when available
- open details in the detail pane or a separate window
- filter the current tab to the selected directory
- start a relevant analysis operation

## Detail Renderers

The detail area should select a renderer based on available data and file type:

```text
ImageRenderer
VideoRenderer
AudioRenderer
TextRenderer
ArchiveRenderer
TorrentRenderer
FallbackRenderer
```

Renderers receive `FileDetails` and may request additional lazy data. The
fallback renderer must always show useful information:

- file name and path
- size and modification time
- detected file type
- available checksums and metadata flags
- reason why no specialized visualization is available

Archives and torrents should use their own nested tree views rather than large
raw text blocks. Archive and torrent entries need their own lazy loading and
selection actions.

## Analysis Operations

Opening a source should not implicitly run duplicate detection or other costly
analysis. Operations should be explicit and available from a `Tools` menu:

- analyze duplicates
- find missing files
- refresh checksums and metadata
- scan archive contents
- scan torrent metadata
- export the current selection

Operations need progress reporting, cancellation, source-scope selection, and
clear result ownership. Results can initially be held in GUI state. Once their
shape is stable and useful to multiple clients, common result DTOs and
operations should move into `DosierSkanilo`.

## Archive Passwords

Password handling should be abstracted before adding archive operations:

```text
PasswordResolver.resolve(archiveId)
PasswordStore.save(archiveId, password)
PasswordStore.remove(archiveId)
```

The first implementation may live in the GUI, but it must not be coupled to a
widget. Passwords should not be stored as ordinary plaintext metadata. Preferred
storage is the platform keyring. A repository-local fallback can use a
permission-restricted secrets file below `.dosierskanilo`; an encrypted SQLite
store can be considered when a repository-wide secret policy exists.

## Migration Sequence

The migration is intentionally allowed to be a clean replacement rather than
a compatibility layer around the current table UI:

1. Define projection types and source capabilities without GTK dependencies.
2. Implement the JSON projection using `NamedBinaryBlob` and Jsonizer.
3. Implement the SQLite projection using repository queries.
4. Replace the flattened table as the primary view with the directory tree. **Tree-first navigation is implemented; the blob table remains an alternative view.**
5. Move filter, sort, selection, and paging state into each tab. **Mostly complete; current tree-file cursor persistence remains.**
6. Add lazy file details and specialized detail renderers. **Partially complete; repository details and audio/image/video previews are implemented, with other specialized renderers still open.**
7. Add archive and torrent entry trees. **Implemented with bounded asynchronous first-page loading and continuation markers; multi-page integration verification remains.**
8. Add explicit analysis operations through the Tools menu.
9. Move stable, reusable projection and analysis code into `DosierSkanilo`. **Directory query DTOs and bounded queries are complete.**

## Immediate Plan

1. Verify archive/torrent continuation over more than 250 entries, including
   stale-result rejection after selection changes and path copying from a later
   page.
2. Exercise the virtual blob table through interactive forward/backward scrolling
   across multiple cache evictions on a large repository.
3. Persist the active TreeView cursor alongside per-tab filter and sort state.
4. Complete directory/file context actions and remaining specialized detail
   renderers; keep analysis and export operations explicit.
5. Revisit splitter restoration and embedded-video layout issues listed in
   `TODO.md`.

The current pagination and BlobRow table are temporary implementation details.
They may be removed once the new source and tree model are usable.
