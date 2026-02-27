# Panel Modal — Construction-Branded Full-Screen Overlay

## Overview

A reusable, scrollable, centered floating panel that renders on top of dimmed terminal content. Used for `/help` and future commands that need to display rich content in a dialog-style overlay. Separate from `ConfirmModal` (which handles inline tool approval prompts).

## Data Model

```dart
PanelModal({
  title: String,              // "HELP", "SESSION", etc.
  lines: List<String>,        // Pre-rendered ANSI content lines
  style: PanelStyle,          // .tape, .simple, .heavy
  barrier: BarrierStyle,      // .dim, .obscure, .none
  width: PanelSize,           // .fluid(maxPercent, minCols) or .fixed(cols)
  height: PanelSize,          // .fluid(maxPercent, minRows) or .fixed(rows)
  dismissable: bool,          // whether Escape closes it
})
```

### PanelSize

Sealed class:
- `PanelFixed(int size)` — exact column/row count
- `PanelFluid(double maxPercent, int minSize)` — percentage of terminal with a floor

Defaults: width = 70% / min 40 cols, height = 70% / min 10 rows.

### PanelStyle

Three border variants:

**`.tape`** (default) — Construction-branded:
```
▚▞▚▞▚▞ HELP ▚▞▚▞▚▞▚▞▚▞▚▞
│                          │
│  /help — Show this panel │
│  /info — Session info    │
│                          │
▚▞▚▞▚▞▚▞▚▞▚▞▚▞▚▞▚▞▚▞▚▞▚▞
```
Top/bottom: alternating `▚▞` in yellow on black. Title rendered inverse (black on yellow) inline. Sides: `│` in yellow.

**`.simple`** — Clean box-drawing:
```
┌─ HELP ───────────────────┐
│                          │
│  /help — Show this panel │
│                          │
└──────────────────────────┘
```
Title in yellow, border in dim gray.

**`.heavy`** — Double-line brutalist:
```
╔═ HELP ═══════════════════╗
║                          ║
║  /help — Show this panel ║
║                          ║
╚══════════════════════════╝
```
Title and border in yellow.

### BarrierStyle

- `.dim` — Wrap every visible background line in `\x1b[2m` (ANSI dim). Fakes a dark transparency layer.
- `.obscure` — Replace background content with `░` in dark gray. Hides content entirely.
- `.none` — No barrier effect.

## Rendering

`PanelModal.render(int terminalWidth, int terminalHeight, List<String> backgroundLines)` returns a `List<String>` representing the full terminal grid:

1. Apply barrier effect to `backgroundLines`
2. Calculate centered panel rect from width/height settings
3. Render border (style-dependent) with title
4. Splice scrolled content lines into the panel interior with 1-char padding on all sides
5. Add scroll indicator (`▲`/`▼` or page number) in bottom border if content overflows

## Scrolling

Internal `_scrollOffset` tracked by `PanelModal`. Handles:
- Up/Down — single line scroll
- PageUp/PageDown — viewport-height scroll
- Clamped to `[0, max(0, contentLines - visibleHeight)]`

## Event Handling

`bool handleEvent(TerminalEvent event)`:
- Escape → completes `result` future if `dismissable`, swallowed if not
- Up/Down/PageUp/PageDown → scroll
- All other input → swallowed (panel is modal)

Exposes `Future<void> get result` that completes on dismiss (same pattern as `ConfirmModal`).

## Integration with App

- New field: `PanelModal? _activePanel`
- In `_handleTerminalEvent`: if `_activePanel != null`, route events to panel first
- In `_doRender`: if `_activePanel != null`, render panel overlay over the full viewport (output + overlay + status bar). Input area hidden while panel is open.
- `/help` command changes from returning a string to setting `_activePanel` and returning empty string

## `/help` Content

Built dynamically from `SlashCommandRegistry` + hardcoded keybindings:

```
■ COMMANDS

  /help          Show this panel
  /info          Session info
  /clear         Clear conversation
  /model <name>  Switch model
  /resume        Resume a session
  /tools         List available tools
  /history       Show input history
  /exit          Exit Glue

■ KEYBINDINGS

  Ctrl+C         Cancel / Exit
  Escape         Cancel generation
  Up / Down      History navigation
  Ctrl+U         Clear line
  Ctrl+W         Delete word
  Ctrl+A / E     Start / End of line
  PageUp / Dn    Scroll output
  Tab            Accept completion

■ FILE REFERENCES

  @path/to/file  Attach file to message
  @dir/          Browse directory
```

Section headers: `■` prefix in yellow (matching website brand label style). Content: 2-space indent.

## File Changes

| File | Change |
|---|---|
| `lib/src/ui/panel_modal.dart` | **New** — `PanelStyle`, `BarrierStyle`, `PanelSize`, `PanelModal` |
| `lib/src/app.dart` | **Modified** — `_activePanel` field, event routing, render integration, `/help` wiring |
| `lib/glue.dart` | **Modified** — export new types |
| `test/ui/panel_modal_test.dart` | **New** — border rendering, scroll, dismiss, sizing, barrier, padding |
