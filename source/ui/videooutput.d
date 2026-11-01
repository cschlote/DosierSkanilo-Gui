/** Video sink preference and fallback order for embedded previews. */
module ui.videooutput;

import std.array : array;

/** Preferred video sinks, in fallback order. */
immutable string[] preferredVideoSinks = ["gtksink", "ximagesink"];

/** Return the sink candidates for one preview mode. */
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
