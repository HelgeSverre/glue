# TUI Behavior Contract

The rules Glue's terminal UI follows. This is the short version — refer to
`cli/lib/src/app/render_pipeline.dart` and `terminal_event_router.dart` for
the actual implementations.

## Terminal setup

On startup Glue enters raw mode, the alternate screen buffer, and mouse
tracking mode — in that order. On normal shutdown the same four get
reset in reverse. A best-effort cleanup also runs from the `finally` block
in `App.run()` so crashes leave the terminal usable.

The alternate screen means `Ctrl+L`, reverse-i-search, and native
scrollback do **not** affect Glue's transcript — Glue renders its own
scrollback in the output zone.

## Scrollback

Scrolling is internal to Glue. There is no native scrollback while in
alternate screen.

| Input                            | Effect                                     |
| -------------------------------- | ------------------------------------------ |
| `PageUp` / `PageDown`            | Scroll half a viewport up/down             |
| Mouse wheel over the output zone | Scroll ±3 lines                            |
| `Ctrl+End`                       | Jump to the bottom; resume follow-tail     |
| Status bar `↑N`                  | Indicator that you are N lines scrolled up |

While scrolled up, new output still arrives — Glue just doesn't follow
the tail. When `_scrollOffset == 0`, new output appears at the bottom as
it lands.

## Resize

Terminal resize:

- Recomputes layout and clears the screen.
- **Preserves scroll position.** The render pipeline clamps any
  out-of-range offset; you won't snap back to the tail because the window
  changed size.
- Panels and modals re-lay out at the new dimensions.
- The input cursor stays visible.

## Tool call phases

Every tool call the agent makes goes through a phase sequence. The phase
shows up next to the tool name in the transcript.

| Phase              | Meaning                                            | Suffix                       |
| ------------------ | -------------------------------------------------- | ---------------------------- |
| `preparing`        | Model named a tool; arguments still streaming      | `(preparing…)` dim           |
| `awaitingApproval` | User decision required before execution            | `(awaiting approval)` yellow |
| `running`          | Glue is executing the tool                         | `(running…)` cyan            |
| `done`             | Completed successfully                             | (no suffix)                  |
| `denied`           | User or policy refused execution **before it ran** | `(denied)` red               |
| `cancelled`        | User cancelled while the tool was active (Ctrl+C)  | `(cancelled)` dim            |
| `error`            | Ran but returned an error                          | `(error)` red                |

`denied` and `cancelled` are deliberately distinct: `denied` means "this
tool never executed," `cancelled` means "this tool was running and you
stopped it."

## Spinner

The spinner in the status bar runs **only** while actual work is in
flight. It:

- starts when entering `AppMode.streaming` or `AppMode.toolRunning`
- stops on every transition back to `AppMode.idle`
- stops explicitly on cancel, on agent error, and on tool error

If you see the spinner still animating while the status bar reads
`Ready`, that's a bug — file an issue. The intended contract is that
spinner state and mode state never disagree.

## Input and focus

Key events are routed in this priority order:

1. Active panel modal (topmost panel in `_panelStack`)
2. Active confirm modal (`_activeModal`)
3. Focused docked panel
4. Active autocomplete overlay (slash, `@file`, shell)
5. Line editor

`Esc` dismisses the top focused transient UI — first panel, else modal,
else autocomplete — before reaching the editor.

### Keys with global behavior (unchanged by focus)

| Key                              | Effect                                    |
| -------------------------------- | ----------------------------------------- |
| `Shift+Tab`                      | Toggle approval mode (`confirm` ↔ `auto`) |
| `PageUp` / `PageDown`            | Scroll transcript                         |
| `Ctrl+End`                       | Jump to bottom                            |
| `Ctrl+C` (single, active work)   | Cancel current agent / bash               |
| `Ctrl+C` (single, idle)          | Prompt to confirm exit                    |
| `Ctrl+C` (double, within ~160ms) | Exit immediately                          |

### Editor

- `Enter` submits the current input unless autocomplete is open and
  consumes it.
- `Shift+Enter` (where the terminal reports it — iTerm2 and compatible)
  inserts a newline.
- Bracketed paste is handled as one atomic text insert; pasting multi-line
  content does not fire `Enter` submits mid-paste.
- `!` at column 0 toggles into bash mode; `Backspace` at column 0 in bash
  mode toggles out.

## Wrapping

Wrapping is by display width, not code units. ANSI escape sequences are
stripped before measuring. Wide glyphs (CJK, emoji) count as width 2.
Ambiguous-width glyphs default to width 1. See
`cli/lib/src/rendering/ansi_utils.dart` — `visibleLength`, `charWidth`,
`ansiTruncate`, `wrapIndented`.

## Glyph policy

The TUI uses these Unicode markers:

```
❯    user prompt marker
◆    assistant marker
▶    tool call marker
✓ ✗  tool result success / failure
⎇    git branch (demo shots)
│    status-bar separator
```

No ASCII-fallback mode exists today. If you're running in a terminal that
can't render these, the experience will degrade. Fixing that is tracked
but not prioritized — file an issue if it blocks you.

## What this contract does not cover yet

These are known gaps, tracked separately:

- `TranscriptModel` scroll-anchor abstraction (TASK-25.1) — replaces the
  manual `_scrollOffset` int with a proper anchor-or-follow state.
  Lands alongside Replay UI (TASK-27).
- Keyboard expand/collapse for subagent/tool groups (TASK-25.4) — today
  collapse/expand is mouse-only.
- Session persistence of collapsed-group state (TASK-25.4).
- `--no-alt-screen` flag and external-editor suspend/restore
  (Bucket C in the audit).

## See also

- `cli/lib/src/app/render_pipeline.dart` — 60fps paint loop
- `cli/lib/src/app/terminal_event_router.dart` — input routing
- `cli/lib/src/app/spinner_runtime.dart` — spinner timer lifecycle
- `cli/lib/src/rendering/block_renderer.dart` — block + tool-phase rendering
- `cli/bin/glue_theme_demo.dart` — interactive visual reference
