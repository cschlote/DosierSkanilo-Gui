# DosierSkanilo Datenfile-Dokumentation (extrahiert)

Quelle: [DosierSkanilo](https://github.com/cschlote/DosierSkanilo)
Stand: 2026-10-13

## 1. Zweck des Datenfiles

Das Tool speichert Scan-Ergebnisse als JSON. Kernobjekt ist `NamedBinaryBlob`:

- 1 Blob = 1 binärer Inhalt
- mehrere Dateipfade (`FileSpec`) koennen denselben Blob referenzieren

Relevante Stellen:

- `docs/README.md`
- `docs/ARCHITECTURE.md`
- `source/dosierskanilo/model/namedbinaryblob.d`

## 2. Aktuelles Speicherformat

Der Serializer schreibt ein Wrapper-Objekt. Gewöhnliche Kataloge werden weiter
als Version 3 geschrieben; Version 4 wird für rekursive verschachtelte
Archivmetadaten verwendet:

```json
{
  "dataVersion": 3,
  "dataArray": [ ... NamedBinaryBlob ... ]
}
```

Wichtig:

- Beim Schreiben wird standardmäßig `dataVersion: 3` ausgegeben; rekursive
  Archiveinträge benötigen Version 4.
- Beim Lesen werden ein unversioniertes Legacy-Array sowie Wrapper-Versionen 1
  bis 4 akzeptiert. Version 1 und Legacy-Felder werden beim Einlesen
  normalisiert; unbekannte Wrapper-Versionen werden abgewiesen.

Code-Referenzen:

- `source/dosierskanilo/model/namedbinaryblob.d`
  (`deserializeDataClassJsonString`, `deserializeDataClassJsonWrapperFile`,
  `serializeDataClassWrapperFile`)

## 3. NamedBinaryBlob-Felder (semantisch)

Pflicht / Kern:

- `fileSize: size_t`
- `checkSums: { md5sum_b64, sha1sum_b64, xxh64sum_b64 }`
- Dateireferenzen (physisch in v3/v4; geplant auch virtuell in v5 über `fileSpecs[]`)

Optional:

- `fileType: string`
- `mediaInfoSig`: image, video, audio, and text stream arrays
- `archiveSpecs[]` (Versionen 3/4: eingebettete Archiv-Entry-Metadaten inkl.
  Checksummen; in geplantem JSON v5 nur noch Legacy-Eingabe)
- `archivePassword: string` (optional, per archive blob; stored in clear text,
  so catalogs containing it are sensitive)
- `torrentInfo` (Name, Info-Hash, Magnet URI, Dateien, ...)

`NamedBinaryBlob` kombiniert heute Payload-Metadaten mit physischen
`FileSpec[]`-Referenzen. `archiveSpecs[]` und `torrentInfo.files[]` sind
verschachtelte Beschreibungen. WP-13.5 ersetzt für Archivmitglieder die
verschachtelte Inhaltsliste in JSON v5 durch normale Blob-Datensätze mit
virtuellen `FileSpec`-Pfaden. Gleiche vollständige Fingerprints können dabei
einen Content-Blob teilen, während jede Occurrence eine eigene Referenz behält.

Legacy-Felder (werden beim Einlesen/Schreiben gefixt):

- `fileName`, `fileNames`, `timeLastModified`
- `md5sum_b64`, `sha1sum_b64`, `xxh64sum_b64` als Top-Level
- `mediaInfo` als String-Array

## 4. Versionsstand und Migration

Im Code definiert:

- `DATA_CLASS_VERSION1 = 1`
- `DATA_CLASS_VERSION2 = 2`
- `DATA_CLASS_VERSION3 = 3`
- `DATA_CLASS_VERSION4 = 4` (rekursive `ArchiveSpec.nestedEntries`)

Effektiv fuer JSON-I/O aktuell relevant:

- Legacy-Arrays und Wrapper-Versionen 1-4 werden gelesen.
- Gewöhnliche Writes bleiben Version 3; verschachtelte Archive benötigen Version 4.
- WP-13.5 plant JSON v5 mit normalen Member-Blobs und virtuellen `FileSpec`-
  Referenzen. `ArchiveSpec[]` wird dann nur noch als Import-Kompatibilität für
  alte Kataloge gelesen.
- In JSON v5 verwenden alle `FileSpec.fileName`-Pfade die virtuelle
  Archivpfad-Grammatik: `!/` trennt Ebenen, `!!` escaped ein wörtliches `!`,
  `!~N` kennzeichnet eine nullbasierte Occurrence. Physische Pfade werden vor
  der Dateisystemauflösung aus den codierten Schichten dekodiert.

Beispieldateien:

- `test/json_file_v0.json` (unversioniertes Legacy-Array)
- `test/json_file_v1.json` (wrapper mit `dataVersion: 1`)
- `test/json_file_v2.json` (historischer Fixture-Dateiname; enthält Wrapper
  `dataVersion: 3`)
- `test/json_file_wrapper_v2.json` (echter Wrapper mit `dataVersion: 2`)
- `test/json_file_v1_wrongversion.json` (ungültige Version, muss abgewiesen werden)
- `test/json_file_v2_archive.json` und `test/json_file_v2_torrent.json`
  (historische Fixture-Dateinamen; enthalten `dataVersion: 3` sowie Archiv- und
  Torrent-Felder)

Es gibt derzeit keine eingecheckte `json_file_v3.json`-Fixture. Der Serializer
schreibt Version 3; die vorhandenen Fixtures `json_file_v2*.json` dienen als
erwartete Ausgabe für die Serializer-Tests. Die Migration eines echten
`dataVersion: 2`-Wrappers ist mit `json_file_wrapper_v2.json` abgedeckt.

## 5. Aktuelles GUI-Modell

Der Loader akzeptiert und normalisiert:

- sowohl Wrapper als auch Legacy-Array akzeptieren
- immer auf ein internes, vereinheitlichtes Modell normalisieren
- fehlende optionale Felder als `null`/leer behandeln
- mehrere Dateipfade pro Blob

## 6. GUI-Projektionen

`BlobRow` wird für die alternative Blob-Tabelle verwendet. Der primäre
Verzeichnisbaum nutzt die GTK-unabhängigen `DirectoryNode`/`FileNode`-
Projektionen in `source/model/treeprojection.d`; `DirectorySource` adaptiert
JSON- und Repository-Abfragen. Diese Typen sind Anzeigeprojektionen, nicht der
persistente Datenmodell-Owner.

Archivmitglieder erscheinen derzeit in verschachtelten Vorschau-Bäumen aus den
gespeicherten `archiveSpecs`/Repository-Archiveinträgen. Die Hauptansicht kann
Archivdateien noch nicht expandieren; ausgewählte Member werden noch nicht über
einen gemeinsamen Extraktionscache in die normalen Previewer geleitet. WP-13.5
definiert virtuelle FileSpec-Pfade, Content-Blob-Verknüpfungen und
sessiongebundene Cache-Regeln.

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

Scan-, Metadaten- und Analyseaktionen der GUI bauen die gemeinsamen Backend-
Operationsrequests; Details und Verzeichnisdaten kommen weiterhin über die
GUI-seitigen Source-Adapter.

## 7. Verifizierte Quellen (ausgelesen)

- [Backend README](https://github.com/cschlote/DosierSkanilo/blob/main/README.md)
- [Backend architecture](https://github.com/cschlote/DosierSkanilo/blob/main/docs/ARCHITECTURE.md)
- [JSON format reference](https://github.com/cschlote/DosierSkanilo/blob/main/docs/JSON-FORMAT.md)
- `source/dosierskanilo/model/namedbinaryblob.d` in the backend repository
- `test/json_file_v0.json`, `test/json_file_v1.json`, and
  `test/json_file_v2*.json` in the backend repository
