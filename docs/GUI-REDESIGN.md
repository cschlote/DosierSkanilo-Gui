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
- SQLite `listDirectories()` and bounded `listFiles()` are available in the
  [DosierSkanilo library](https://github.com/cschlote/DosierSkanilo).
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
- JSON and SQLite tree/file adapters pass parity coverage for case-sensitive
  filtering, size sorting, and forward/backward file navigation. Case-sensitive
  matching in the Blob/catalog view remains open as backend WP-10.1.
- Per-tab media, file-type, archive, and torrent toggles are synchronized into
  query state before automatic filtering.
- Late archive/torrent replies are checked against the active blob, selection
  generation, and loading-marker token before changing a TreeStore.
- Audio rows use the GStreamer playback controls even when metadata reports
  embedded cover art; video streams retain preview priority.
- Repository root summaries use bounded backend aggregates, and each directory
  source operation opens an independent repository connection.
- Expanded repository directories reconcile leftover loading placeholders after
  asynchronous child insertion; duplicate requests are suppressed while pending.
- Directory/file context menus support opening files externally and showing
  directories or containing folders in the file manager.
- The File menu exports rows matching the active tab's filters as CSV or a
  versioned GUI JSON summary.
- File-type signatures appear in a wrapped, selectable description view with a
  clear empty state.
- Files without specialized metadata show a fallback overview with identity,
  size, known paths, and available checksums.
- Per-tab filter toggles are captured in the query state before applying filters.

Known limitations:

- Adapter-level archive/torrent continuation is covered with 251-entry fixtures,
  GTK-independent page/copy-path helper logic has unit coverage, and opt-in
  TreeView signal tests verify continuation offsets/tokens and copying a
  later-page leaf's full path. The opt-in GTK model test changes the selection
  token before applying a page reply and verifies that the stale reply is rejected.
- The blob table remains an alternative, transitional view; the directory tree
  is still the primary navigation surface.
- Case-sensitive text filtering is not yet consistent between the directory
  tree and the repository-backed Blob/catalog view; see WP-10.1 in the backend
  plan and the GUI task in `TODO.md`.
- Several window splitters and video-preview layout behaviors remain on the
  open-issues list in `TODO.md`.
- Scan, metadata scraping, and analysis actions are not yet available in GTK;
  their shared CLI/GUI execution plan is described in the backend plan at
`https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md#wp-09`.

## Verification Baseline

The last recorded verification baseline (before the current unverified
asynchronous-filter working-tree changes) passed:

- `dub test --compiler=ldc2` — 35 tests.
- `dub build --compiler=ldc2`.
- `git diff --check`.
- `DOSIER_GUI_ACTIVATION_TEST=1 dub test --compiler=ldc2 -- --threads=1
  --include=activat` — GTK TreeView activation checks with a usable display.
- `DOSIER_GUI_TABLE_SCROLL_TEST=1 dub test --compiler=ldc2 -- --threads=1
  --include='scrolls through evicted chunks'` — GTK TreeView long-scroll check.
- `DOSIER_GUI_TREE_LOAD_TEST=1 dub test --compiler=ldc2 -- --threads=1
  --include='expanded GTK directories recover'` — expanded loading-placeholder
  recovery check.
- GTK self-tests under `G_DEBUG=fatal-warnings` for an audio-plus-cover fixture,
  repository archive/torrent fixtures, and a large repository. Self-test mode
  selects the first row and expands remote archive/torrent roots when present.

The virtual-table test uses a temporary 1,000-row repository with 50-row chunks.
It queues a backward request during a forward load, reads all rows in both
directions, verifies stable blob IDs after cache eviction, and asserts that no
more than four chunks remain cached. An opt-in GTK TreeView test scrolls through
distant rows and back to evicted chunks. Audio classification and GStreamer
preroll were tested with an MP3 fixture and fake sinks; audible output through a
physical audio device has not been smoke-tested.

The repository source concurrency test runs repeated tree queries and selected
blob detail loads in parallel against an 81-file temporary repository.

The JSON/SQLite directory/file source parity test exercises case-sensitive
filtering, size-sorted forward pages, and backward navigation. It does not cover
case-sensitive matching in the repository Blob/catalog query; that is tracked as
WP-10.1 in the backend plan. A separate repository fixture verifies archive and
torrent continuation from 250 to entry 251.

The nested-detail logic test verifies trimming the 251st look-ahead item,
continuation offsets, and copying the complete path of the later-page file.
The GTK signal-level continuation/leaf activation and long-scroll checks are
opt-in to keep the default parallel, display-independent unit suite stable.

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

Status: **Planned; no scanner or analysis actions are currently exposed by the
GUI.** The target is shared operation logic: CLI and GTK pass the same typed
request/options to the DosierSkanilo library. GTK must not reimplement scanning
or metadata extraction. See backend WP-09 for the operation contract and staged
implementation plan at `https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md#wp-09`.

Opening a source should not implicitly run duplicate detection or other costly
analysis. Operations should be explicit and available from a `Tools` menu:

- analyze duplicates
- find missing files
- refresh checksums and metadata
- scan archive contents
- scan torrent metadata
- export the current selection

Operations need a shared progress/cancellation contract, source-scope selection,
and clear result ownership. A background task manager will marshal progress to
the GTK main loop, serialize conflicting writes per repository, and refresh the
active view after successful mutations. CLI output/exit-code behavior should be
an adapter over the same operation results. JSON and SQLite remain explicit
storage modes. See the backend plan at `https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md#wp-09`.

## Archive Passwords

### Desired user flow

When the user opens a password-protected archive, the GUI prompts for its
password. The archive context menu also offers an action to enter or retry the
password. After a successful password check, the GUI asks whether to remember it
for that archive. A remembered password is offered automatically on later opens;
the context menu can forget it or replace it.

The first implementation should use the simplest local persistence available to
the GUI, separate from catalog metadata. Store an entry keyed by the source and
archive identity in the user's GUI settings. There is no requirement for a
keyring, encryption layer, repository-wide secret policy, or backend API. Do
not save a password after a failed attempt or unless the user opts in. This
feature is planned; the GUI does not currently prompt for or remember archive
passwords.

## Migration Sequence

The migration is intentionally allowed to be a clean replacement rather than
a compatibility layer around the current table UI:

1. Define projection types and source capabilities without GTK dependencies.
2. Implement the JSON projection using `NamedBinaryBlob` and Jsonizer.
3. Implement the SQLite projection using repository queries.
4. Replace the flattened table as the primary view with the directory tree.
   **Tree-first navigation is implemented; the blob table remains an
   alternative view.**
5. Move filter, sort, selection, and paging state into each tab. **Filter,
   sort, and TreeView cursor state now persist per document.**
6. Add lazy file details and specialized detail renderers. **Repository details,
   structured MediaInfo streams, file-type signatures, fallback overview, and
   audio/image/video previews are implemented.**
7. Add archive and torrent entry trees. **Implemented with bounded asynchronous
   paging; adapter and GTK continuation, stale-reply, and later-page path tests
   cover entries beyond 250.**
8. Add explicit analysis operations through the Tools menu.
9. Move stable, reusable projection and analysis code into `DosierSkanilo`.
   **Directory query DTOs and bounded queries are complete.**

## Current Work Plan

The older immediate-plan checklist is complete except for scanner/analysis
operations and the explicitly deferred GTK layout issues. Current actionable GUI
work is tracked in [`TODO.md`](../TODO.md): finish and verify asynchronous JSON
filtering, restore case-sensitive Blob-table parity with the tree, then implement
the GTK operations client after the backend and CLI reference slices are ready.
Splitter/video behavior and UI maintenance remain lower-priority GUI work.

The shared CLI/GTK operation work is tracked as WP-09 in the backend's
[`SQLITE-IMPLEMENTATION-PLAN.md`](https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md#wp-09).
Its dependency order is intentional: agree the shared request/control contract,
make backend operations report progress and stop safely, then build the CLI and
GTK adapters, and finally verify parity. GTK must not introduce a second scanner
or analysis implementation.

The current pagination and BlobRow table are temporary implementation details.
They may be removed once the new source and tree model are usable.
