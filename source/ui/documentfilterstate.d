/** Pure policy for deciding whether loaded document rows must be filtered.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.documentfilterstate;

import std.string : strip;

/** Whether a document has an effective text, media, or presence filter.
 *
 * Params:
 *     text = Free-text filter value; whitespace-only text counts as empty.
 *     video = Whether the video presence filter is active.
 *     audio = Whether the audio presence filter is active.
 *     image = Whether the image presence filter is active.
 *     textStream = Whether the text-stream presence filter is active.
 *     fileType = Whether the file-type filter is active.
 *     archive = Whether the archive presence filter is active.
 *     torrent = Whether the torrent presence filter is active.
 * Returns: `true` when any criterion is active; `false` when all are absent.
 */
bool documentFilterHasCriteria(string text, bool video, bool audio, bool image,
    bool textStream, bool fileType, bool archive, bool torrent)
{
    return text.strip().length > 0 || video || audio || image || textStream || fileType
        || archive || torrent;
}

/** Return whether a non-empty JSON document filter should run after source load.
 *
 * Params:
 *     hasActiveFilter = Whether the document currently has filter criteria.
 *     filterWasApplied = Whether a filter was already applied to the document.
 *     autoApplyFilter = Whether global auto-filtering is enabled.
 * Returns: `true` only when a filter is active and either it was already
 *     applied or auto-apply is enabled.
 */
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
