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
- Asynchronous details for repository files outside the current table page.
- Previous/Next navigation for multiple known file references.

Known limitations:

- A table selection does not yet automatically expand collapsed directories to
  reveal its TreeView file.
- Tree filtering and sorting are not yet unified with table filtering/sorting.
- Expanded-directory state is held per tab but is not persisted in `AppState`.
- The table remains a transitional implementation of the alternative blob view.

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

The GUI-facing source interface should be small and read-oriented:

```text
open(path)
root()
listDirectories(parentId)
listFiles(directoryId, filter, page)
loadFileDetails(fileId)
loadArchiveDetails(fileId)
loadTorrentDetails(fileId)
loadAnalysis(sourceScope, analysisKind)
close()
```

The JSON implementation may build an in-memory directory index when opened.
The SQLite implementation should query directory and file children directly.
Both implementations return the same projection types. Missing information
must be represented explicitly rather than inferred differently by each UI
path.

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
- large file lists are paged below the selected directory
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
4. Replace the flattened table as the primary view with the directory tree. **In progress; the table remains as an alternative view.**
5. Move filter, sort, selection, and paging state into each tab. **In progress; expanded IDs and most filter/page state are per-tab.**
6. Add lazy file details and specialized detail renderers. **Partially complete; repository details load asynchronously.**
7. Add archive and torrent entry trees.
8. Add explicit analysis operations through the Tools menu.
9. Move stable, reusable projection and analysis code into `DosierSkanilo`. **Directory query DTOs and bounded queries are complete.**

## Immediate Plan

1. Reveal and select a collapsed TreeView path when the blob table is selected.
2. Add unified tree filtering and stable per-tab sorting.
3. Persist expanded and selected tree state in `AppState`.
4. Make direct `FileNode` detail loading independent of temporary table rows.
5. Add context actions, specialized renderers, archive/torrent trees, and
   explicit analysis operations.

The current pagination and BlobRow table are temporary implementation details.
They may be removed once the new source and tree model are usable.
