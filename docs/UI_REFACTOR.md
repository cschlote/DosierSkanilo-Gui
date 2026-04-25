# UI Refactor Note

This note captures the current state of the GTK UI and the agreed next direction.

## Current Problems

- The top-level splitter can still snap back to a maximum width after loading a file.
- The preview pane can remain empty on the first video selection even though audio is already playing.
- The preview/details splitter position is not restored reliably yet.
- Switching between video rows can still cause the window to grow horizontally.

## Working Agreement

- The application should stay tolerant of UI failures.
- Problems should be logged clearly.
- UI/layout faults must not crash the process.
- Layout-heavy work should be easier to verify visually before the business logic depends on it.

## Direction

- Use a Glade/GTK Builder UI as the editable layout surface where practical.
- Keep the logic, state handling, and media playback code in D.
- Use stable object names in the builder file so the code can bind to the UI deterministically.
- Keep dynamic or risky widgets, such as the video preview and sink attachment, behind explicit fallback handling.

## Glade Scope

Glade should describe the static GUI surface and the default presentation state. D should keep the runtime wiring, state transitions, and data-driven updates.

Good Glade candidates in this codebase are:

- widget hierarchy and container structure
- pack order, spacing, margins, and alignment
- default labels, placeholders, tooltips, and icons
- default sensitivity and visibility for controls that start disabled or hidden
- default sizes and ranges for entries, scales, panes, and scrolled windows
- CSS class assignment for reusable visual styling
- expander labels and other presentation-only defaults

Better left in D are:

- signal handlers and callback wiring
- filter and preview state changes
- loading, parsing, rendering, and clipboard actions
- dynamic visibility decisions based on loaded data
- media player setup, sink attachment, and track synchronization

## Possible Next Steps

- Move the remaining top-level window shell, toolbar, and menu layout into Glade if that structure is expected to stay stable.
- Consider a Builder template or composite widget for repeated detail rows if a subpanel becomes reusable across tabs.
- Add more builder-defined defaults for panes, scroll containers, and labels so D only changes them when user state or loaded data requires it.
- Revisit whether more runtime-only widget creation can be replaced with predefined builder objects plus explicit fallback handling.
- Keep any future signal hookup in D unless the callback is intentionally trivial and truly static.

## Why This Helps

- It makes layout changes easier to review and discuss.
- It gives a concrete visual base for ad hoc verification.
- It should make external contributions simpler because the hierarchy is explicit.
- It allows alternative compatible layouts to be tested by restarting with a different UI file.
