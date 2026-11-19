/** Pure splitter-position math for the document panes.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module ui.splitterlayout;

/** Minimum primary pane extent kept visible in pixels. */
enum int minPrimaryExtent = 240;

/** Minimum details pane extent kept visible in pixels. */
enum int minDetailsExtent = 180;

/** Minimum preview pane extent kept visible in pixels. */
enum int minPreviewExtent = 240;

/**
 * Clamp a requested splitter position to the visible pane bounds.
 *
 * Params:
 *   requested = requested divider position from saved state or the user.
 *   totalExtent = allocated width or height of the splitter, zero before layout.
 *   minPosition = dynamic lower bound for the primary pane.
 *   maxPosition = dynamic upper bound for the divider.
 * Returns: A position that keeps both panes usable, or the requested position
 *     before the widget has been allocated.
 */
int clampSplitPosition(int requested, int totalExtent, int minPosition,
    int maxPosition)
{
    if (totalExtent <= 0)
        return requested;
    if (totalExtent <= minPrimaryExtent + minDetailsExtent)
        return totalExtent / 2;
    if (requested < minPosition)
        return minPosition;
    if (requested > maxPosition)
        return maxPosition;
    return requested;
}

/** Clamp the details/preview divider so both panes stay usable.
 *
 * The divider position is the width of the details pane on the left; the
 * preview pane keeps the remaining width on the right. Unallocated splitters
 * keep the requested position so a saved value survives the first layout pass.
 *
 * Params:
 *     requested = Requested details width from saved state or the user.
 *     totalExtent = Allocated width of the details/preview splitter.
 * Returns: A details width that keeps both panes usable, or the requested
 *     position before the widget has been allocated.
 */
int clampPreviewSplitPosition(int requested, int totalExtent)
{
    if (totalExtent <= 0)
        return requested;
    if (totalExtent <= minDetailsExtent + minPreviewExtent)
        return totalExtent / 2;
    if (requested < minDetailsExtent)
        return minDetailsExtent;
    const auto maxDetails = totalExtent - minPreviewExtent;
    if (requested > maxDetails)
        return maxDetails;
    return requested;
}

/** Default details width that leaves the preview maximized.
 *
 * Params:
 *     totalExtent = Allocated width of the details/preview splitter.
 * Returns: A quarter of the width, clamped to the usable details range, or 0
 *     before the widget has been allocated.
 */
int defaultPreviewSplitPosition(int totalExtent)
{
    if (totalExtent <= 0)
        return 0;
    return clampPreviewSplitPosition(totalExtent / 4, totalExtent);
}

@("splitter clamp keeps both panes usable across window sizes")
unittest
{
    assert(clampSplitPosition(500, 0, 240, 800) == 500,
        "unallocated splitters keep their requested position");

    assert(clampSplitPosition(500, 300, 240, 200) == 150,
        "narrow windows split evenly");

    assert(clampSplitPosition(100, 1000, 240, 800) == 240,
        "positions below the primary minimum are raised");

    assert(clampSplitPosition(950, 1000, 240, 800) == 800,
        "positions beyond the details minimum are lowered");

    assert(clampSplitPosition(500, 1000, 240, 800) == 500,
        "valid positions are preserved");

    assert(clampSplitPosition(240, 1000, 240, 800) == 240);
    assert(clampSplitPosition(800, 1000, 240, 800) == 800);
}

@("preview split clamp keeps details and preview usable")
unittest
{
    assert(clampPreviewSplitPosition(320, 0) == 320,
        "unallocated splitters keep the saved position");
    assert(clampPreviewSplitPosition(100, 300) == 150,
        "narrow panes split evenly");
    assert(clampPreviewSplitPosition(10, 1000) == minDetailsExtent,
        "details never collapse");
    assert(clampPreviewSplitPosition(900, 1000) == 1000 - minPreviewExtent,
        "preview never collapses");
    assert(clampPreviewSplitPosition(320, 1000) == 320);

    assert(defaultPreviewSplitPosition(1000) == 250);
    assert(defaultPreviewSplitPosition(0) == 0);
    assert(defaultPreviewSplitPosition(400) == 200);
    assert(defaultPreviewSplitPosition(1000) > 0);
    assert(defaultPreviewSplitPosition(1000) < 1000 / 2,
        "the default leaves the preview maximized");
}
