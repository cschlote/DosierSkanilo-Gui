# DosierSkanilo Datenfile-Dokumentation (extrahiert)

Quelle: [DosierSkanilo](https://github.com/cschlote/DosierSkanilo)
Stand: 2026-11-02

## 1. Zweck des Datenfiles

Das Tool speichert Scan-Ergebnisse als JSON. Kernobjekt ist `NamedBinaryBlob`:

- 1 Blob = 1 binärer Inhalt
- mehrere Dateipfade (`FileSpec`) koennen denselben Blob referenzieren

Relevante Stellen:

- `docs/README.md`
- `docs/ARCHITECTURE.md`
- `source/dosierskanilo/model/namedbinaryblob.d`

## 2. Aktuelles Speicherformat

Der Serializer schreibt ein Wrapper-Objekt mit `dataVersion: 5`:

```json
{
  "dataVersion": 5,
  "dataArray": [ ... NamedBinaryBlob ... ]
}
```

Wichtig:

- Beim Schreiben wird immer `dataVersion: 5` ausgegeben; ältere Versionen werden
  beim Speichern beziehungsweise Import normalisiert.
- Beim Lesen werden ein unversioniertes Legacy-Array sowie Wrapper-Versionen 1
  bis 5 akzeptiert. Version 1 und Legacy-Felder werden beim Einlesen
  normalisiert; unbekannte Wrapper-Versionen werden abgewiesen.

Code-Referenzen:

- `source/dosierskanilo/model/namedbinaryblob.d`
  (`deserializeDataClassJsonString`, `deserializeDataClassJsonWrapperFile`,
  `serializeDataClassWrapperFile`)

## 3. NamedBinaryBlob-Felder (semantisch)

Pflicht / Kern:

- `fileSize: size_t`
- `checkSums: { md5sum_b64, sha1sum_b64, xxh64sum_b64 }`
- Dateireferenzen über `fileSpecs[]` (physisch oder virtuell)

Optional:

- `fileType: string`
- `mediaInfoSig`: image, video, audio, and text stream arrays
- `archiveSpecs[]` (Legacy-Eingabe aus v0-v4; v5 schreibt normale Member-Blobs
  mit virtuellen `FileSpec`-Pfaden)
- `archivePassword: string` (optional, per archive blob; stored in clear text,
  so catalogs containing it are sensitive)
- `torrentInfo` (Name, Info-Hash, Magnet URI, Dateien, ...)

`NamedBinaryBlob` kombiniert Payload-Metadaten mit physischen oder virtuellen
`FileSpec[]`-Referenzen. `archiveSpecs[]` und `torrentInfo.files[]` bleiben
Legacy- beziehungsweise Manifest-Beschreibungen. JSON v5 speichert
Archivmitglieder als normale Blob-Datensätze mit virtuellen `FileSpec`-Pfaden.
Gleiche vollständige Fingerprints können einen Content-Blob teilen, während jede
Occurrence eine eigene Referenz behält.

Legacy-Felder (werden beim Einlesen/Schreiben gefixt):

- `fileName`, `fileNames`, `timeLastModified`
- `md5sum_b64`, `sha1sum_b64`, `xxh64sum_b64` als Top-Level
- `mediaInfo` als String-Array

## 4. Versionsstand und Migration

Im Code definiert:

- `DATA_CLASS_VERSION1 = 1`
- `DATA_CLASS_VERSION2 = 2`
- `DATA_CLASS_VERSION3 = 3`
- `DATA_CLASS_VERSION4 = 4` (rekursive `ArchiveSpec.nestedEntries`, Legacy-Eingabe)
- `DATA_CLASS_VERSION5 = 5` (aktuelles Schreibformat)

Effektiv fuer JSON-I/O aktuell relevant:

- Legacy-Arrays und Wrapper-Versionen 1-5 werden gelesen.
- Writes erzeugen JSON v5 mit normalen Member-Blobs und virtuellen `FileSpec`-
  Referenzen. `ArchiveSpec[]` wird nur noch als Import-Kompatibilität für alte
  Kataloge gelesen.
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

Es gibt derzeit keine eingecheckte JSON-v5-Fixture. Der Serializer schreibt
Version 5; die vorhandenen Fixtures `json_file_v2*.json` sind historische
Version-3-Eingaben und dienen als normalisierte Erwartung für die
Serializer-Tests. Die Migration eines echten
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
Projektionen in `source/model/treeprojection.d`; `CatalogDirectorySource`
adaptiert `CatalogBackend`-Abfragen für JSON und Repository. Diese Typen sind
Anzeigeprojektionen, nicht der persistente Datenmodell-Owner.

Archivmitglieder erscheinen in einem paginierten Archive-Preview-Baum aus den
gespeicherten Legacy-`archiveSpecs` bzw. den virtuellen JSON-v5- und
Repository-Dateireferenzen.
Die Auswahl eines Datei-Blatts extrahiert den Member über den gemeinsamen
Backend-Cache und leitet den Cache-Pfad an den normalen Previewer weiter. Die
virtuelle Referenz bleibt der logische Pfad; der Cache-Pfad wird nicht in den
Katalog geschrieben. Die Preview-Lease bleibt bis zum Wechseln des Previews oder
Schließen des Tabs aktiv. Der Haupt-Verzeichnisbaum zeigt virtuelle Member nicht
als physische Verzeichnisse an; Archivdateien lassen sich dort ebenfalls lazy
und paginiert expandieren. Archiv-Member, die selbst Archive sind, können im
gleichen Baum weiter expandiert werden. Cache-Einstellungen sind implementiert;
Same-Directory-Prefetch bleibt optional und standardmäßig deaktiviert.

- `BlobRow`
  - `sourceId` / `sourceKey` (Repository-ID bzw. katalogrelativer Pfad)
  - `fileSize`
  - `md5`, `sha1`, `xxh64`
  - `primaryFileName`
  - `fileCount`
  - Presence-Flags für Dateityp, Medien, Archiv und Torrent
  - optionale `sourceBlob`-Referenz für Legacy-Zeilen
  - kataloggerenderte Detailtexte (`catalog*`)
- Es gibt keinen separaten `BlobDetail`-Typ. Vollständige Details werden über
  die angehängte `NamedBinaryBlob` oder über `CatalogBackend` geladen.

Scan-, Metadaten- und Analyseaktionen der GUI bauen die gemeinsamen Backend-
Operationsrequests; Details und Verzeichnisdaten werden für beide Speicherarten
über `CatalogBackend` geladen.

## 7. Verifizierte Quellen (ausgelesen)

- [Backend README](https://github.com/cschlote/DosierSkanilo/blob/main/README.md)
- [Backend architecture](https://github.com/cschlote/DosierSkanilo/blob/main/docs/ARCHITECTURE.md)
- [JSON format reference](https://github.com/cschlote/DosierSkanilo/blob/main/docs/JSON-FORMAT.md)
- `source/dosierskanilo/model/namedbinaryblob.d` in the backend repository
- `test/json_file_v0.json`, `test/json_file_v1.json`, and
  `test/json_file_v2*.json` in the backend repository
