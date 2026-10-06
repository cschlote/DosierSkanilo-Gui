/** Pure policy for deciding whether loaded document rows must be filtered. */
module ui.documentfilterstate;

import std.string : strip;

/** Whether a document has an effective text, media, or presence filter. */
bool documentFilterHasCriteria(string text, bool video, bool audio, bool image,
    bool textStream, bool fileType, bool archive, bool torrent)
{
    return text.strip().length > 0 || video || audio || image || textStream || fileType
        || archive || torrent;
}

/** Return whether a non-empty JSON document filter should run after source load. */
bool shouldApplyDocumentFilter(bool hasActiveFilter, bool filterWasApplied,
    bool autoApplyFilter)
{
    return hasActiveFilter && (filterWasApplied || autoApplyFilter);
}

@("restored document filters reapply even when global auto-filter is disabled")
unittest
{
    assert(!documentFilterHasCriteria("", false, false, false, false, false,
        false, false));
    assert(!documentFilterHasCriteria(" \t\n", false, false, false, false,
        false, false, false));
    assert(documentFilterHasCriteria("needle", false, false, false, false,
        false, false, false));
    assert(documentFilterHasCriteria("", false, false, false, true, false,
        false, false));

    assert(shouldApplyDocumentFilter(true, true, false));
    assert(shouldApplyDocumentFilter(true, false, true));
    assert(!shouldApplyDocumentFilter(true, false, false));
    assert(!shouldApplyDocumentFilter(false, true, true));
}
