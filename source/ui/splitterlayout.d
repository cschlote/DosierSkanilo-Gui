/** Pure splitter-position math for the document panes. */
module ui.splitterlayout;

/** Minimum primary pane extent kept visible in pixels. */
enum int minPrimaryExtent = 240;

/** Minimum details pane extent kept visible in pixels. */
enum int minDetailsExtent = 180;

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
