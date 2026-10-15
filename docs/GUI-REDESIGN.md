# GUI Data Model and Tree View Plan

This document records the current source-neutral directory/tree projection and
its remaining design work. The Blob table remains available as an alternative
view; the directory tree is the primary navigation surface. Widget layout may
continue to evolve independently of the catalog API.

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
  filtering, size sorting, and forward/backward file navigation. Repository
  Blob/catalog path filtering now carries the same case-sensitive preference.
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
- Long preview summaries use a size-bounded two-axis scroll area and preserve
  long lines without expanding the containing window.
- Per-tab filter toggles are captured in the query state before applying filters.
- Per-document filters and Blob-table sorting are persisted. On reload, JSON
  sources are filtered after the source projection is attached and expanded
  directories are restored against the resulting tree. The directory/Blob
  notebook tabs are the view switch; there is no separate view-mode dropdown.
- Tree-to-Blob selection resolves the displayed row identity rather than using
  its unsorted array position. An empty JSON filter takes the unfiltered fast
  path instead of copying and rebuilding the same catalog projection.
- JSON and SQLite filter changes reuse materialized directory TreeStore rows via
  `GtkTreeModelFilter`, stable file-reference IDs, precomputed match/ancestor
  indexes, and worker-fetched pages for materialized directories.
- JSON filtering evaluates text/media/presence predicates in one pass and uses
  dense file/directory projection-index bitmaps; table sorting uses numeric
  hidden keys instead of formatted strings.
- Archive and torrent entry trees render in their scrollable Previewer areas;
  their detail expanders show compact metadata summaries. The whole details
  column is vertically scrollable while its horizontal Previewer splitter stays
  in place.
- Text content renders in the large preview scroller; the lower summary lists
  path, size, access rights, access and modification times, file type, and
  checksum availability.
- In-memory JSON directory paging keeps a bounded sorted candidate window rather
  than materializing and sorting every file in the directory for each page.

Known limitations:

- Adapter-level archive/torrent continuation is covered with 251-entry fixtures,
  GTK-independent page/copy-path helper logic has unit coverage, and opt-in
  TreeView signal tests verify continuation offsets/tokens and copying a
  later-page leaf's full path. The opt-in GTK model test changes the selection
  token before applying a page reply and verifies that the stale reply is rejected.
- The blob table remains an alternative, transitional view; the directory tree
  is still the primary navigation surface.
- The backend now exposes archive members as content/reference projections, but
  the GUI Directory Tree does not yet expand the archive file row. The Previewer
  lists indexed entries; selecting a member does not yet extract it into a shared
  cache for ordinary file preview or metadata extraction. The storage/path
  transition is planned in backend WP-13.5.
- Several window splitters and video-preview layout behaviors remain on the
  open-issues list in `TODO.md`.
- General scan, metadata, and analysis are available from the Tools menu through
  shared backend requests. The remaining CLI/GUI parity matrix and process-level
  lifecycle verification are tracked in the backend plan at
  `https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md#wp-09`.

## Verification Baseline

The current working tree passes:

- `dub test --compiler=ldc2` — 61 tests.
- `dub build --compiler=ldc2`.
- `git diff --check`.

The GTK-independent filter projection and request-state tests are included in
the default suite. The expanded-tree GTK opt-in test was run with a display.
Torrent and archive preview summaries were also smoke-tested with
`G_DEBUG=fatal-warnings` and a fresh GUI state.
Earlier display-backed verification also covered:

- `DOSIER_GUI_ACTIVATION_TEST=1 dub test --compiler=ldc2 -- --threads=1
  --include=activat` — GTK TreeView activation checks with a usable display.
- `DOSIER_GUI_TABLE_SCROLL_TEST=1 dub test --compiler=ldc2 -- --threads=1
  --include='scrolls through evicted chunks'` — GTK TreeView long-scroll check.
- `DOSIER_GUI_TREE_LOAD_TEST=1 dub test --compiler=ldc2 -- --threads=1` — the
  expanded loading-placeholder recovery check is enabled in the full suite.
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
filtering, size-sorted forward pages, and backward navigation. The filtered
export parity test also checks case-sensitive filename matching in the
repository Blob/catalog query. A separate repository fixture verifies archive
and torrent continuation from 250 to entry 251.

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

The primary view is a GTK `TreeView` backed by a lazy tree model:

- directories are expandable nodes
- files are children of directories
- child nodes are loaded when a directory is expanded
- large file lists are fetched in internal chunks and appended below the
  selected directory; user-visible pagination controls are not required
- sorting is explicit and stable
- loading and error placeholder nodes are visible states

### Reuse Nodes When Filters Change (Implemented)

Filter changes retain the per-document canonical directory `TreeStore`; a
`GtkTreeModelFilter` changes row visibility without clearing loaded nodes.
File-node identity is separate from Blob identity and filtered-array position:
one Blob can have multiple path nodes. JSON uses stable source-row/reference
ordinals; SQLite uses file-reference cursor IDs.

For JSON, parse/index the source once and compute stable-ID visibility and
filtered directory summaries on a worker; no new full `DirectoryTree` is built
per query. For SQLite, preserve materialized nodes and reconcile
server-filtered rows from bounded pages by stable ID. Apply visibility changes on
the GTK main loop, preserve selection/expansion by stable ID, and keep the prior
tree visible while matching runs.

Visibility is a bounded lookup over precomputed IDs; it does not query a source
or traverse descendants. Directories remain visible when they have matching
descendants. Clearing, changing, and reapplying filters upsert rows by stable ID,
refresh already materialized directories, and restore the same canonical nodes.

Unit/model tests cover filter parity, stable IDs, ancestor visibility, and
retention of underlying rows. A display-backed JSON filter smoke test passed with
`G_DEBUG=fatal-warnings`. Measure large-tree latency, allocation churn, and peak
memory on representative catalogs as a follow-up; include Blob-table rendering
at 95,001 JSON rows and record per-batch time and GC behavior.

## GC-Friendly Algorithms

All GUI algorithms must be GC-friendly; this means bounded, low-churn allocation,
not bypassing the D GC. Reuse canonical JSON/source indexes, node records, and
per-document/per-worker scratch buffers. Avoid a fresh full row array, directory
projection, path/string temporary, or GTK model per filter change. Keep SQLite
pages and caches bounded, avoid repeated normalization/formatting in hot loops,
and keep mutable reusable buffers owned by one worker. Verify repeated operations
as well as first-load latency and peak memory; record GC measurements where the
available tooling permits.

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

Shared Tools actions now expose scan, metadata, and analysis requests through the
DosierSkanilo operation API. The GUI runs them on workers, shows progress, and
supports backend-acknowledged pause/resume/cancel. Archive-member extraction and
member metadata use are the remaining archive-specific integration. See backend
WP-09 and WP-13 in the operation plan at
`https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md`.

Opening a source should not implicitly run duplicate detection or other costly
analysis. Operations should be explicit and available from a `Tools` menu:

- analyze duplicates
- find missing files
- refresh checksums and metadata
- scan archive contents
- scan torrent metadata
- export the current selection

Operations use the shared progress/cancellation contract and keep JSON and
SQLite targets explicit. CLI output/exit behavior remains an adapter over the
same operation results. Archive-member scraping will reuse the extraction cache
and persist results on the member's normal content blob, never on the temporary
cache path.

## Archive Passwords

The File menu provides a filename-based Archive Passwords dialog and a catalog-wide
Scan Archives action. Archive file context menus can scan just the selected
archive. A user-entered filename is resolved to its Blob; JSON sources store the
optional `archivePassword` on `NamedBinaryBlob`, while SQLite repositories store
it in the `archive_passwords` relation. During archive listing or deep extraction,
DosierArkivo reports that a password is required or rejected. The GUI marshals
that request to GTK, prompts the user, and the scan persists an accepted password
with its catalog or repository. Blank password input in the manager removes the
mapping. The current implementation stores passwords as plain text, as agreed
for this feature.

## Archive Member Tree, Extraction, and Cache

Archive Preview leaf selection now extracts through the shared leased cache and
uses the regular media/text/fallback preview pipeline. The logical reference
stays virtual, while the cache lease pins the temporary preview file for the
active document. The main Directory Tree also expands physical archive rows
lazily, pages member rows, and supports nested archive rows without projecting
virtual member paths as ordinary directories. Cache preferences and prefetch
remain planned.

The archive file remains the TreeView file row and is expandable when it has an
archive index or a recognized archive extension. Expansion lists safe member
rows lazily; it does not unpack the whole archive. Selecting a member extracts it
through the shared cache and passes the cached path to the existing preview
pipeline. Nested archives use the same flow recursively.

Virtual reference paths use `!/` between archive layers, `!!` for a literal
exclamation mark, and `!~N` for zero-based duplicate-name occurrences. Tree
labels show the original name; content/reference identity uses the structured
locator and occurrence. JSON v5 stores scraped members as ordinary content
records with virtual `FileSpec` paths. SQLite schema v4 migrates existing archive
rows to virtual `file_refs` and removes `archive_entries`/`archive_indexes`
without adding archive-specific tables.

One session extraction cache is shared by archive scraping, checksums, file-type
and MediaInfo extraction, preview, and optional prefetch. JSON defaults to an OS
temporary cache root; SQLite uses a configurable local cache base. Each run owns
a session subdirectory that is removed at normal exit, and stale owned sessions
are cleaned at startup. A maximum cache size and pinned active previews bound
retention. Same-directory sibling prefetch is a preference, disabled by default
until cancellation and resource-bound tests pass; a RAM-backed cache can be
selected by choosing a RAM-disk path.

### GUI work packages

- **Archive-tree expansion (implemented):** loading rows page safe members into
  the same TreeStore, preserve duplicate occurrences, and allow nested archive
  members to expand. Entry listing remains separate from extraction.
- **Selected-member extraction/preview (implemented):** resolve the virtual
  reference chain, extract to the shared cache off the GTK thread, and feed the
  cached file to the existing image/audio/video/text/fallback previewers. The
  logical selected path remains virtual; external preview paths are cache paths
  only.
- **Cache preferences/lifecycle:** configure the cache base and maximum size,
  default prefetch off, coalesce repeated requests, pin files used by previews,
  stop previews and cancel/join workers before shutdown cleanup, and sweep only
  stale session folders carrying the application's ownership marker.
- **Archive scraping:** explicit deep scans process every safely selectable
  member, reuse one cache lease per member for the enabled metadata extractors,
  and persist results on the content blob. Do not create durable filesystem
  references to session-cache files.

**Acceptance:** expand/select/preview works for JSON and SQLite, including nested
archives, duplicate names, passwords, cancellation, and cache eviction. After a
normal exit no extracted session files remain; reopening and selecting a member
re-extracts it without losing persisted metadata.

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

The older immediate-plan checklist is complete except for the archive-member
TreeView/extraction workflow, remaining CLI/GUI operation parity checks, and the
explicitly deferred GTK layout issues. Current GUI work is tracked in
[`TODO.md`](../TODO.md). Archive-member work depends on backend WP-13.5 virtual
references and the shared cache contract. Large-catalog latency, GC allocation,
and peak-memory measurements remain follow-up verification.

The shared CLI/GTK operation work is tracked as WP-09 in the backend's
[`SQLITE-IMPLEMENTATION-PLAN.md`](https://github.com/cschlote/DosierSkanilo/blob/main/docs/SQLITE-IMPLEMENTATION-PLAN.md#wp-09).
Its dependency order is intentional: agree the shared request/control contract,
extend it with safe pause/resume semantics, make backend operations report
progress and stop/pause safely, then build the CLI and GTK adapters, and finally
verify parity. GTK must not introduce a second scanner or analysis
implementation.

The current pagination and BlobRow table are temporary implementation details.
They may be removed once the new source and tree model are usable.
