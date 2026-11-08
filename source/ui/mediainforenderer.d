/** Structured presentation rows for MediaInfo streams.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.mediainforenderer;

import std.format : format;
import std.string : join;

import dosierskanilo.metadata.mediainfosig : MediaInfoSig;

/** One concise row in the MediaInfo stream table. */
struct MediaInfoStreamRow
{
    /// Human-readable stream label such as `Video 1` or `Audio 2`.
    string stream;
    /// Codec or container format name reported for the stream.
    string format;
    /// Preformatted properties joined with a middle dot separator.
    string properties;
}

/** Append `label` and `value` to `properties` when the value is non-empty.
 *
 * Params:
 *     properties = Accumulator that receives the combined label and value.
 *     label = Prefix text, including any trailing separator such as `": "`.
 *     value = Value to append; empty values are ignored.
 */
private void appendProperty(ref string[] properties, string label, string value)
{
    if (value.length > 0)
        properties ~= label ~ value;
}

/** Project image, video, audio, and text streams into display-ready rows.
 *
 * Params:
 *     signature = MediaInfo signature to project; may be null.
 * Returns: One row per stream in video, audio, image, text order, or an empty
 *     array when `signature` is null.
 */
MediaInfoStreamRow[] mediaInfoStreamRows(const(MediaInfoSig) signature)
{
    MediaInfoStreamRow[] rows;
    if (signature is null)
        return rows;

    foreach (stream; signature.videoStreams)
    {
        if (stream is null)
            continue;
        string[] properties;
        appendProperty(properties, "Language: ", stream.language);
        if (stream.width > 0 && stream.height > 0)
            properties ~= format("%s × %s", stream.width, stream.height);
        if (stream.frameRate > 0)
            properties ~= format("%s fps", stream.frameRate);
        if (stream.bitRate > 0)
            properties ~= format("%s bps", stream.bitRate);
        appendProperty(properties, "Duration: ", stream.duration);
        rows ~= MediaInfoStreamRow(format("Video %s", stream.index), stream.format,
            properties.join(" · "));
    }
    foreach (stream; signature.audioStreams)
    {
        if (stream is null)
            continue;
        string[] properties;
        appendProperty(properties, "Language: ", stream.language);
        if (stream.channels > 0)
            properties ~= format("%s channels", stream.channels);
        if (stream.bitRate > 0)
            properties ~= format("%s bps", stream.bitRate);
        appendProperty(properties, "Duration: ", stream.duration);
        rows ~= MediaInfoStreamRow(format("Audio %s", stream.index), stream.format,
            properties.join(" · "));
    }
    foreach (stream; signature.imageStreams)
    {
        if (stream is null)
            continue;
        string[] properties;
        if (stream.width > 0 && stream.height > 0)
            properties ~= format("%s × %s", stream.width, stream.height);
        rows ~= MediaInfoStreamRow(format("Image %s", stream.index), stream.format,
            properties.join(" · "));
    }
    foreach (stream; signature.textStreams)
    {
        if (stream is null)
            continue;
        string[] properties;
        appendProperty(properties, "Language: ", stream.language);
        if (stream.frameRate > 0)
            properties ~= format("%s fps", stream.frameRate);
        if (stream.bitRate > 0)
            properties ~= format("%s bps", stream.bitRate);
        appendProperty(properties, "Duration: ", stream.duration);
        rows ~= MediaInfoStreamRow(format("Text %s", stream.index), stream.format,
            properties.join(" · "));
    }
    return rows;
}

@("MediaInfo renderer projects stream fields into typed rows")
unittest
{
    import std.algorithm.searching : canFind;
    import dosierskanilo.metadata.mediainfosig : MediaInfoAudio, MediaInfoImage,
        MediaInfoText, MediaInfoVideo;

    auto signature = new MediaInfoSig();
    signature.imageStreams ~= new MediaInfoImage(0, "JPEG", 640, 480);
    signature.videoStreams ~= new MediaInfoVideo(1, "en", "AV1", 1920, 1080,
        23.976, 4_000_000, "00:02:10");
    signature.audioStreams ~= new MediaInfoAudio(2, "fr", "Opus", 2,
        192_000, "00:02:10");
    signature.textStreams ~= new MediaInfoText(3, "en", "UTF-8", 0, 0, "");

    auto rows = mediaInfoStreamRows(signature);
    assert(rows.length == 4);
    assert(rows[0].stream == "Video 1");
    assert(rows[0].format == "AV1");
    assert(rows[0].properties.canFind("1920 × 1080"));
    assert(rows[0].properties.canFind("23.976 fps"));
    assert(rows[1].stream == "Audio 2");
    assert(rows[1].properties.canFind("2 channels"));
    assert(rows[2].stream == "Image 0");
    assert(rows[2].properties == "640 × 480");
    assert(rows[3].stream == "Text 3");
    assert(rows[3].properties == "Language: en");
    assert(mediaInfoStreamRows(null).length == 0);
}
