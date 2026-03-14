# DosierSkanilo Datenfile-Dokumentation (extrahiert)

Quelle: `../DosierSkanilo`  
Stand: 2026-03-14

## 1. Zweck des Datenfiles

Das Tool speichert Scan-Ergebnisse als JSON. Kernobjekt ist `NamedBinaryBlob`:

- 1 Blob = 1 binärer Inhalt
- mehrere Dateipfade (`FileSpec`) koennen denselben Blob referenzieren

Relevante Stellen:

- `docs/README.md`
- `docs/ARCHITECTURE.md`
- `source/dosierskanilo/namedbinaryblob.d`

## 2. Aktuelles Speicherformat

Serializer schreibt ein Wrapper-Objekt:

```json
{
  "dataVersion": 2,
  "dataArray": [ ... NamedBinaryBlob ... ]
}
```

Wichtig:

- Beim Lesen wird `dataVersion == 2` erzwungen.
- Legacy-Inhalte werden in `fixupDataClassArrayIn(...)` migriert.

Code-Referenzen:

- `source/dosierskanilo/namedbinaryblob.d` (`deserializeDataClassJsonString`)
- `source/dosierskanilo/namedbinaryblob.d` (`serializeDataClassArrayFile`)

## 3. NamedBinaryBlob-Felder (semantisch)

Pflicht / Kern:

- `fileSize: size_t`
- `checkSums: { md5sum_b64, sha1sum_b64, xxh64sum_b64 }`
- Dateireferenzen (intern v3-konform ueber `fileSpecs[]`)

Optional:

- `fileType: string`
- `mediaInfoSig: { imageStreams[], videoStreams[], audioStreams[], textStreams[] }`
- `archiveSpecs[]` (Archiveinhalte inkl. Checksummen)
- `torrentInfo` (Name, Info-Hash, Magnet URI, Dateien, ...)

Legacy-Felder (werden beim Einlesen/Schreiben gefixt):

- `fileName`, `fileNames`, `timeLastModified`
- `md5sum_b64`, `sha1sum_b64`, `xxh64sum_b64` als Top-Level
- `mediaInfo` als String-Array

## 4. Versionsstand und Migration

Im Code definiert:

- `DATA_CLASS_VERSION1 = 1`
- `DATA_CLASS_VERSION2 = 2`
- `DATA_CLASS_VERSION3 = 3`

Effektiv fuer JSON-I/O aktuell relevant:

- gelesen/geschrieben wird Version 2 im Wrapper
- v0/v1-Beispiele werden nach v2 migriert

Beispieldateien:

- `test/json_file_v0.json` (plain array, legacy)
- `test/json_file_v1.json` (wrapper mit `dataVersion: 1`)
- `test/json_file_v2.json` (wrapper mit `dataVersion: 2`)

## 5. Wichtige GUI-Implikationen

Fuer eine robuste GtkD-GUI sollte der Loader:

- sowohl Wrapper als auch Legacy-Array akzeptieren
- immer auf ein internes, vereinheitlichtes Modell normalisieren
- fehlende optionale Felder als `null`/leer behandeln
- bei Multi-File-Blobs mehrere Dateipfade anzeigen koennen

## 6. Vorschlag internes GUI-Modell

Minimal fuer erste Version:

- `BlobRow`
  - `id` (lokal)
  - `fileSize`
  - `md5`, `sha1`, `xxh64`
  - `primaryFileName`
  - `fileCount`
  - `fileType`
  - `hasMediaInfo`
  - `hasArchiveInfo`
  - `hasTorrentInfo`
- `BlobDetail`
  - `fileSpecs[]`
  - `mediaInfoSig`
  - `archiveSpecs[]`
  - `torrentInfo`

Damit sind Tabelle + Detailansicht + Dubletten-Gruppierung direkt umsetzbar.

## 7. Verifizierte Quellen (ausgelesen)

- `../DosierSkanilo/docs/README.md`
- `../DosierSkanilo/docs/ARCHITECTURE.md`
- `../DosierSkanilo/source/dosierskanilo/namedbinaryblob.d`
- `../DosierSkanilo/test/json_file_v0.json`
- `../DosierSkanilo/test/json_file_v1.json`
- `../DosierSkanilo/test/json_file_v2.json`
