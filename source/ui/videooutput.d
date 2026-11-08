/** Video sink preference and fallback order for embedded previews.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.videooutput;

import std.array : array;

/** Preferred video sinks, in fallback order. */
immutable string[] preferredVideoSinks = ["gtksink", "ximagesink"];

/** Return the sink candidates for one preview mode.
 *
 * Params:
 *     audioOnly = When true, request the audio-only sink instead of video
 *         sinks.
 * Returns: A freshly allocated sink list: `["fakesink"]` for audio-only
 *     previews, otherwise a copy of `preferredVideoSinks` in fallback order.
 */
string[] videoSinkCandidates(bool audioOnly)
{
    return audioOnly ? ["fakesink"] : preferredVideoSinks.dup;
}

@("video preview prefers the GTK sink and falls back to X11")
unittest
{
    assert(videoSinkCandidates(true) == ["fakesink"]);
    assert(videoSinkCandidates(false) == ["gtksink", "ximagesink"]);
}
