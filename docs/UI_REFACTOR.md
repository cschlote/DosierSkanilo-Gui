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

## Why This Helps

- It makes layout changes easier to review and discuss.
- It gives a concrete visual base for ad hoc verification.
- It should make external contributions simpler because the hierarchy is explicit.
- It allows alternative compatible layouts to be tested by restarting with a different UI file.
