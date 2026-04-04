/** Adapter helpers between the GUI row model and the DosierSkanilo library.
 *
 * The GUI should not maintain its own JSON tree parser for scanner data.
 * Instead, it consumes the canonical `NamedBinaryBlob` model exposed by the
 * library and flattens it into `BlobRow` instances for table rendering.
 *
 * Authors: DosierSkanilo contributors
 * License: CC-BY-NC-SA 4.0
 */
module io.dosierjson;

import core.internal.array.equality : __equals;
import std.algorithm : sort;
import std.array : appender;
import std.format : format;
import std.string : join;

import dosierskanilo.metadata.mediainfosig : MediaInfoAudio, MediaInfoSig, MediaInfoVideo;
import dosierskanilo.model.namedbinaryblob : FileSpec, NamedBinaryBlob;
import dosierskanilo.metadata.torrentinfo : BNode;

import model.blobrow;

static this()
{
    // Force druntime equality instantiation for `torrentinfo.BNode[]`.
    // SumType!(long, string, BNode[], BDict).opEquals requires __equals!(BNode, BNode)
    // to be emitted, but this does not happen automatically with some dmd/druntime versions.
    BNode[] nodes;
    auto _ = __equals(nodes, nodes);
}

/** Build a multiline details string from file specs. */
string fileSpecDetails(FileSpec[] specs)
{
    auto lines = appender!(string[])();
    foreach (spec; specs)
    {
        if (spec is null || spec.fileName.length == 0)
        {
            continue;
        }

        auto modified = spec.timeLastModified.length > 0 ? spec.timeLastModified : "-";
        lines.put(format("%s | last modified: %s", spec.fileName, modified));
    }
    return lines.data.join("\n");
}

/** Join array items into a multiline details block using their own string form. */
string detailLines(T)(T[] values)
{
    if (values.length == 0)
    {
        return "";
    }

    auto lines = appender!(string[])();
    foreach (value; values)
    {
        static if (is(T == class))
        {
            if (value is null)
            {
                continue;
            }
        }
        lines.put(value.toString());
    }
    return lines.data.join("\n");
}

/** Build a readable raw details block from the canonical library object. */
string blobDetails(NamedBinaryBlob blob)
{
    auto lines = appender!(string[])();
    lines.put(blob.toString());

    if (blob.fileSpecs.length > 0)
    {
        lines.put("Files:");
        lines.put(fileSpecDetails(blob.fileSpecs));
    }

    if (blob.archiveSpecs.length > 0)
    {
        lines.put("Archive:");
        lines.put(detailLines(blob.archiveSpecs));
    }

    if (blob.mediaInfoSig !is null && !blob.mediaInfoSig.empty)
    {
        lines.put("Media:");
        lines.put(blob.mediaInfoSig.toString());
    }

    if (blob.torrentInfo !is null && !blob.torrentInfo.empty)
    {
        lines.put("Torrent:");
        lines.put(blob.torrentInfo.toString());
    }

    return lines.data.join("\n");
}

/** Convert one library blob into the flat GUI row projection. */
BlobRow rowFromNamedBinaryBlob(NamedBinaryBlob blob)
{
    BlobRow row;
    if (blob is null)
    {
        return row;
    }

    auto specs = blob.fileSpecs.dup;
    specs.sort!((a, b) => a.fileName < b.fileName);

    auto names = appender!(string[])();
    foreach (spec; specs)
    {
        if (spec is null || spec.fileName.length == 0)
        {
            continue;
        }
        names.put(spec.fileName);
    }

    row.primaryFileName = blob.getFirstFileName;
    row.fileSize = cast(ulong) blob.fileSize;
    row.md5 = blob.checkSums.md5sum_b64;
    row.sha1 = blob.checkSums.sha1sum_b64;
    row.xxh64 = blob.checkSums.xxh64sum_b64;
    row.fileCount = names.data.length;
    row.fileNamesSummary = names.data.join(", ");
    row.fileNamesDetails = fileSpecDetails(specs);

    if (blob.mediaInfoSig !is null)
    {
        row.hasMedia = !blob.mediaInfoSig.empty;
        row.hasImage = blob.mediaInfoSig.imageStreams.length > 0;
        row.hasVideo = blob.mediaInfoSig.videoStreams.length > 0;
        row.hasAudio = blob.mediaInfoSig.audioStreams.length > 0;
        row.hasText = blob.mediaInfoSig.textStreams.length > 0;
        row.mediaInfoDetails = blob.mediaInfoSig.toString();
    }

    row.hasArchive = blob.archiveSpecs.length > 0;
    row.archiveDetails = detailLines(blob.archiveSpecs);

    row.hasTorrent = blob.torrentInfo !is null && !blob.torrentInfo.empty;
    row.torrentDetails = row.hasTorrent ? blob.torrentInfo.toString() : "";

    row.fileType = blob.fileType;
    row.rawJson = blobDetails(blob);

    return row;
}

/** Convert a library blob array into GUI rows. */
BlobRow[] extractRowsFromBlobs(NamedBinaryBlob[] blobs)
{
    auto rows = appender!(BlobRow[])();
    foreach (blob; blobs)
    {
        rows.put(rowFromNamedBinaryBlob(blob));
    }
    return rows.data;
}

@("NamedBinaryBlob to BlobRow conversion tests")
unittest
{
    import std.datetime.systime : SysTime;

    auto blob = new NamedBinaryBlob("alpha.mkv", 123, SysTime(1_234_567));
    blob.checkSums.md5sum_b64 = "md5";
    blob.checkSums.sha1sum_b64 = "sha1";
    blob.checkSums.xxh64sum_b64 = "xxh64";
    blob.fileType = "Matroska";
    blob.mediaInfoSig = new MediaInfoSig();
    blob.mediaInfoSig.videoStreams ~= new MediaInfoVideo(0, "de", "AV1", 1920, 1080, 25.0);
    blob.mediaInfoSig.audioStreams ~= new MediaInfoAudio(1, "de", "AAC", 2);

    auto row = rowFromNamedBinaryBlob(blob);
    assert(row.primaryFileName == "alpha.mkv");
    assert(row.fileSize == 123);
    assert(row.sha1 == "sha1");
    assert(row.fileCount == 1);
    assert(row.hasMedia);
    assert(row.hasVideo);
    assert(row.hasAudio);
    assert(!row.hasImage);
    assert(row.fileNamesDetails.length > 0);
    assert(row.rawJson.length > 0);
}

@("BlobRow filtering tests")
unittest
{
    import std.datetime.systime : SysTime;

    auto blob1 = new NamedBinaryBlob("one.bin", 1, SysTime(1_000));
    auto blob2 = new NamedBinaryBlob("two.bin", 2, SysTime(2_000));
    auto rows = extractRowsFromBlobs([blob1, blob2]);

    assert(rows.length == 2);
    assert(rows[0].primaryFileName == "one.bin");
    assert(rows[1].primaryFileName == "two.bin");
}
