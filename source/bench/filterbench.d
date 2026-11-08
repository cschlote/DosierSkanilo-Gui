/** Headless filter and tree-projection benchmark for representative row counts.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module bench.filterbench;

import core.memory : GC;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.format : format;
import std.stdio : writefln, writeln;
import std.conv : to;

import dosierskanilo.model.filespec : FileSpec;
import dosierskanilo.model.namedbinaryblob : NamedBinaryBlob,
    NamedBinaryBlobCatalog, DATA_CLASS_VERSION5, serializeDataClassWrapperFile;
import std.datetime.systime : Clock;
import model.blobrow : BlobRow;
import model.treeprojection : FileInput, buildDirectoryTree;
import view.textreport : filterRowsByText;

/** Build synthetic rows for benchmarking filter and tree projections.
 *
 * Params:
 *     count = Number of rows to create.
 * Returns: A newly allocated array of `count` deterministic rows.
 */
private BlobRow[] syntheticRows(size_t count)
{
    BlobRow[] rows;
    rows.reserve(count);
    foreach (index; 0 .. count)
    {
        BlobRow row;
        row.primaryFileName = format("track-%06d.flac", index);
        row.fileSize = (index % 4096) + 1;
        row.sha1 = format("sha1-%08d", index);
        row.hasSummaryFlags = true;
        row.summaryHasAudio = (index % 3) == 0;
        row.summaryHasMedia = row.summaryHasAudio;
        rows ~= row;
    }
    return rows;
}

/** Build synthetic file inputs for benchmarking directory-tree projection.
 *
 * Paths are spread over a fixed number of album directories so the resulting
 * tree has a representative shape.
 *
 * Params:
 *     count = Number of file inputs to create.
 * Returns: A newly allocated array of `count` deterministic inputs.
 */
private FileInput[] syntheticInputs(size_t count)
{
    FileInput[] inputs;
    inputs.reserve(count);
    foreach (index; 0 .. count)
    {
        FileInput input;
        input.path = format("media/album-%02d/track-%06d.flac", index % 100,
            index);
        input.size = (index % 4096) + 1;
        input.hasAudio = (index % 3) == 0;
        input.hasMedia = input.hasAudio;
        inputs ~= input;
    }
    return inputs;
}

/** Write a benchmark catalog containing `count` synthetic blobs.
 *
 * Params:
 *     path = Destination path for the serialized catalog file.
 *     count = Number of blob records to generate and serialize.
 * Throws: File or serialization errors from `serializeDataClassWrapperFile`.
 */
private void writeBenchmarkCatalog(string path, size_t count)
{
    NamedBinaryBlob[] blobs;
    blobs.reserve(count);
    foreach (index; 0 .. count)
    {
        auto blob = new NamedBinaryBlob(
            format("bench/album-%02d/track-%06d.flac", index % 100, index),
            (index % 4096) + 1, Clock.currTime);
        blobs ~= blob;
    }
    NamedBinaryBlobCatalog catalog = NamedBinaryBlobCatalog(
        DATA_CLASS_VERSION5, blobs);
    serializeDataClassWrapperFile(path, catalog);
    writeln("wrote ", count, " records to ", path);
}

/** Run the headless filter and tree benchmark.
 *
 * With `--write-catalog <path> <count>` the command only writes a benchmark
 * catalog. Otherwise it measures the configured row counts, which default to
 * 1,000, 10,000, and 100,000 and can be overridden by numeric arguments.
 *
 * Params:
 *     args = Process arguments, including the program name.
 * Returns: Process exit code; `0` on success.
 * Throws: Argument conversion or file errors are not caught.
 */
int main(string[] args)
{
    if (args.length == 4 && args[1] == "--write-catalog")
    {
        writeBenchmarkCatalog(args[2], args[3].to!size_t);
        return 0;
    }

    size_t[] sizes = [1_000, 10_000, 100_000];
    if (args.length > 1)
    {
        sizes.length = 0;
        foreach (argument; args[1 .. $])
            sizes ~= argument.to!size_t;
    }

    writeln("count\tfilter_ms\ttree_ms\tpeak_mib\tgc_ms\tgc_cycles\talloc_mib\tfiltered\tdirs\tfiles");
    foreach (count; sizes)
    {
        GC.collect();
        auto rows = syntheticRows(count);
        auto inputs = syntheticInputs(count);
        const profileBefore = GC.profileStats;
        const allocatedBefore = GC.stats.allocatedInCurrentThread;

        auto filterWatch = StopWatch(AutoStart.yes);
        const filtered = filterRowsByText(rows, "track-0007", false);
        filterWatch.stop();
        const filterMs = filterWatch.peek.total!"usecs" / 1000.0;

        auto treeWatch = StopWatch(AutoStart.yes);
        const tree = buildDirectoryTree(inputs);
        treeWatch.stop();
        const treeMs = treeWatch.peek.total!"usecs" / 1000.0;

        const profileAfter = GC.profileStats;
        const allocatedBytes = GC.stats.allocatedInCurrentThread
            - allocatedBefore;
        GC.collect();
        const peakMiB = GC.stats.usedSize / (1024.0 * 1024.0);
        const gcMs = (profileAfter.totalCollectionTime
            - profileBefore.totalCollectionTime).total!"usecs" / 1000.0;
        writefln("%d\t%.1f\t%.1f\t%.1f\t%.1f\t%d\t%.1f\t%d\t%d\t%d",
            count, filterMs, treeMs, peakMiB, gcMs,
            profileAfter.numCollections - profileBefore.numCollections,
            allocatedBytes / (1024.0 * 1024.0), filtered.length,
            tree.directories.length, tree.files.length);
    }
    return 0;
}
