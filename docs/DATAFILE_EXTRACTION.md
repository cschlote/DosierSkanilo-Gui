# DosierSkanilo Datenfile-Dokumentation (extrahiert)

Quelle: [DosierSkanilo](https://github.com/cschlote/DosierSkanilo)
Stand: 2026-09-28

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
  "dataVersion": 3,
  "dataArray": [ ... NamedBinaryBlob ... ]
}
```

Wichtig:

- Beim Schreiben wird immer `dataVersion: 3` ausgegeben.
- Beim Lesen werden ein unversioniertes Legacy-Array sowie Wrapper-Versionen 1,
  2 und 3 akzeptiert. Version 1 und Legacy-Felder werden beim Einlesen
  normalisiert; unbekannte Wrapper-Versionen werden abgewiesen.

Code-Referenzen:

- `source/dosierskanilo/model/namedbinaryblob.d`
  (`deserializeDataClassJsonString`, `serializeDataClassArrayFile`)

## 3. NamedBinaryBlob-Felder (semantisch)

Pflicht / Kern:

- `fileSize: size_t`
- `checkSums: { md5sum_b64, sha1sum_b64, xxh64sum_b64 }`
- Dateireferenzen (intern v3-konform ueber `fileSpecs[]`)

Optional:

- `fileType: string`
- `mediaInfoSig`: image, video, audio, and text stream arrays
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

- gelesen/geschrieben wird Version 3 im Wrapper
- akzeptierte Legacy- und Wrapper-Eingaben werden intern normalisiert und
  beim Schreiben als Version 3 ausgegeben

Beispieldateien:

- `test/json_file_v0.json` (unversioniertes Legacy-Array)
- `test/json_file_v1.json` (wrapper mit `dataVersion: 1`)
- `test/json_file_v2.json` (historischer Fixture-Dateiname; enthält Wrapper
  `dataVersion: 3`)
- `test/json_file_v1_wrongversion.json` (ungültige Version, muss abgewiesen werden)
- `test/json_file_v2_archive.json` und `test/json_file_v2_torrent.json`
  (historische Fixture-Dateinamen; enthalten `dataVersion: 3` sowie Archiv- und
  Torrent-Felder)

Es gibt derzeit keine eingecheckte `json_file_v3.json`-Fixture. Der Serializer
schreibt Version 3; die vorhandenen Fixtures `json_file_v2*.json` dienen als
erwartete Ausgabe für die Serializer-Tests. Eine separate Fixture mit
`dataVersion: 2` gibt es derzeit nicht.

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

- [Backend README](https://github.com/cschlote/DosierSkanilo/blob/main/README.md)
- [Backend architecture](https://github.com/cschlote/DosierSkanilo/blob/main/docs/ARCHITECTURE.md)
- [JSON format reference](https://github.com/cschlote/DosierSkanilo/blob/main/docs/JSON-FORMAT.md)
- `source/dosierskanilo/model/namedbinaryblob.d` in the backend repository
- `test/json_file_v0.json`, `test/json_file_v1.json`, and
  `test/json_file_v2*.json` in the backend repository
