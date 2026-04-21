# TUI Behavior Contract Plan

Status: proposed
Owner: implementation agent
Date: 2026-04-19

## Goal

Define how Glue's terminal UI behaves, not just how it looks.

The design references and theme demo are useful, but the implementation needs a
behavior contract for wrapping, resize, scrollback, alternate screen, tool
states, spinner behavior, keyboard focus, and transcript grouping.

## Current Code Context

Relevant files:

- `lib/src/terminal/terminal.dart`
- `lib/src/terminal/layout.dart`
- `lib/src/app/render_pipeline.dart`
- `lib/src/app/terminal_event_router.dart`
- `lib/src/rendering/block_renderer.dart`
- `lib/src/rendering/markdown_renderer.dart`
- `lib/src/ui/*`
- `bin/glue_theme_demo.dart`
- `docs/design/tui-theme-system.md`
- `docs/architecture/agent-loop-and-rendering.md`

Current behavior:

- Glue enters raw mode, alternate screen, and mouse mode.
- `Layout` uses hardware scroll regions and paints output/status/input zones.
- Conversation blocks are held in memory as `_blocks`.
- Render pipeline builds all block lines every render and paints the visible
  viewport.
- Resize clears the screen, reapplies layout, resets scroll offset, and renders.
- Input wrapping accounts for character widths.
- Tool calls have phases: preparing, awaiting approval, running, done, denied,
  error.
- Status line spinner uses Braille frames.
- PageUp/PageDown and mouse wheel adjust `_scrollOffset`.
- Docked panels and modals get input before the editor.

## Product-Level Decisions

### Alternate Screen

Default interactive mode should keep using alternate screen.

Rules:

- On startup: enter raw mode, alternate screen, mouse mode.
- On shutdown: reset style, scroll region, cursor, mouse mode, alternate screen,
  raw mode.
- On external editor open: temporarily leave alternate screen and restore after.
- On crash: best effort restore terminal state.

Optional later:

- `--no-alt-screen` mode for users who want native terminal scrollback.

### Scrollback Model

Glue currently uses an internal transcript viewport, not native terminal
scrollback, while in alternate screen.

Rules:

- Internal scrollback is canonical during interactive mode.
- PageUp/PageDown scroll by half viewport.
- Mouse wheel scrolls transcript when pointer is over output.
- New output follows tail unless user has scrolled up.
- If user is scrolled up, show a status hint like `up 42`.
- A "jump to bottom" key should exist. Candidate: `End`.

### Resize

Rules:

- Recompute layout from current terminal size.
- Rewrap all visible transcript blocks.
- Keep the same transcript anchor when possible.
- Do not reset scroll offset unless the previous offset is invalid.
- Input cursor must remain visible after resize.
- Panels should recompute bounds and preserve focus.

Current reset-to-bottom behavior is simple but loses user position. Preserve
position after the behavior contract is implemented.

### Wrapping

Rules:

- Wrap by display width, not code unit count.
- ANSI escape sequences do not count toward width.
- Wide glyphs count as width 2.
- Ambiguous-width glyphs should default to width 1 unless terminal probing is
  added later.
- Wrapped continuation lines align under the content column, not the marker.
- Long unbroken tokens may hard-wrap.
- Markdown tables may degrade gracefully on narrow widths.
- Tool output should wrap or truncate according to block type, not ad hoc.

### Glyph Policy

Use single-cell symbols for controls and state markers.

Avoid:

- symbols that render as double width in common fonts
- icons that require Nerd Fonts
- decorative long dotted rules
- color-only state

Preferred ASCII fallback must exist for every semantic symbol.

### Spinner And Working State

Rules:

- Spinner only animates while work is actually active.
- Streaming text: "thinking" or "writing" status may use spinner.
- Tool running: show tool state and keep spinner separate or paused.
- Waiting for user approval: no spinner; show approval state.
- Background job running: show job state, not model spinner.
- Spinner frame should tick on a timer independent of incoming tokens.
- Timer must stop when mode returns to idle.

Current code has `_spinnerFrames`, `_startSpinner`, and `_stopSpinner`; the
behavior contract should make mode-to-spinner mapping explicit.

### Tool Display States

Canonical states:

- pending: model has named a tool but args are still streaming
- awaiting approval: user decision required
- running: Glue is executing the tool
- succeeded: tool completed successfully
- failed: tool completed with error
- denied: user or policy denied execution
- cancelled: user cancelled while active

Rendering should support:

- compact collapsed header
- expanded arguments
- streamed output chunks
- final output
- stderr/error summary
- file write diff
- artifact link for long output

### Transcript Groups

Groupable blocks:

- tool call and result
- delegated agent transcript
- long command output
- file write diff
- markdown-heavy assistant response if very long

Rules:

- Collapsed summary must fit on one or two lines.
- Expanded state should be keyboard and mouse accessible.
- Collapsed state should persist during the session.
- If session JSONL later records UI hints, replay can restore expanded state.

### Input And Focus

Rules:

- Focus priority: modal, active panel, autocomplete, file hint, shell
  completion, editor.
- `Esc` closes the focused transient UI first.
- Double `Ctrl+C` exits; single `Ctrl+C` cancels active work or prompts exit in
  idle mode.
- Bracketed paste inserts text without triggering commands mid-paste.
- Shift+Enter inserts newline when terminal reports it.
- Enter submits unless autocomplete/panel consumes it.

## Reference Demo Requirements

`bin/glue_theme_demo.dart` should remain the visual regression target, but it
should also cover behavior:

- resize narrow/wide
- long user prompt wrapping
- long assistant markdown with table/code/list
- tool pending/running/success/error/denied/cancelled
- streamed command output
- collapsed/expanded delegated agent
- file write diff
- no-color mode
- ASCII fallback mode
- spinner animation in active states

## Implementation Plan

1. Add this behavior contract to docs and link it from TUI/theme docs.
2. Add a `TranscriptModel` or equivalent abstraction between `_blocks` and
   rendered lines.
3. Track transcript scroll anchor instead of raw offset only.
4. Add explicit `FollowTail` state.
5. Normalize block render states for tool, agent, command, file, and message
   blocks.
6. Add ASCII/no-color rendering mode.
7. Update resize handling to preserve scroll anchor.
8. Extend `glue_theme_demo.dart` with behavior scenarios.
9. Add tests for wrapping, truncation, scroll anchoring, and tool state
   rendering.

## Tests

Add tests for:

- resize preserves scroll position when scrolled up
- resize follows tail when at bottom
- wide glyph wrapping does not overflow
- ANSI styled strings truncate safely
- spinner starts/stops with mode changes
- tool states render distinct semantic markers
- collapsed transcript can be expanded by mouse and keyboard
- no-color output contains meaningful state text
- long command output produces bounded display

## Acceptance Criteria

- Behavior is predictable across narrow and wide terminals.
- TUI state is understandable without relying on color alone.
- User can scroll, resize, and expand groups without losing context.
- Working spinner does not get stuck.
- Tool and delegated agent states match what is persisted in JSONL.

## Open Questions

- Should default user marker be `>` or a Unicode prompt marker with ASCII
  fallback?
- Should native scrollback mode be supported now or deferred?
- What is the exact key for expand/collapse without mouse?
- Should long assistant markdown collapse automatically or only tool/agent
  output?
