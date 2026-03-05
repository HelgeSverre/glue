# TUI Theme System and Overlay Patterns

This document defines how Glue's TUI styling primitives should be used so new UI
features stay visually consistent and predictable.

## Scope

Applies to:

- Theme tokens (`lib/src/ui/theme_tokens.dart`)
- UI recipes (`lib/src/ui/theme_recipes.dart`)
- Shared components (`lib/src/ui/select_panel.dart`, `lib/src/ui/table_formatter.dart`)
- Interactive demo harness (`bin/glue_theme_demo.dart`)

## Core Rules

1. Use token roles, not raw colors, for normal UI styling.
2. Use recipes for repeated UI patterns (headings, badges, list rows, panel rows).
3. Keep accent sparse: focus, primary actions, and brand marker only.
4. All docked overlays are floating (on top), not layout-shifting.
5. Focused overlay consumes input first; global handlers run after.

## Token Roles

`GlueThemeTokens` exposes semantic style functions:

- Text: `textPrimary`, `textSecondary`, `textMuted`
- Brand/action: `accent`, `accentSubtle`, `brandDot`
- Surfaces: `surfaceBorder`, `surfaceMuted`
- Interaction: `focus`, `selection`
- Status: `info`, `success`, `warning`, `danger`

Modes:

- `minimal`
- `highContrast`

Switching mode should not require touching feature code; only token mapping should
change.

## Recipes

`GlueRecipes` is the preferred API for common structure:

- `brandHeading()`
- `sectionHeading()`
- `keyHint()`
- `badge()`
- `listItem()`
- `borderLine()`
- `panelRow()`

If a pattern appears in more than one place, add a recipe instead of cloning ANSI
composition logic.

## Shared Components

### SelectPanel

`SelectPanel<T>` is the canonical searchable chooser overlay.

- Supports keyboard navigation, filtering, paging, confirm/cancel.
- Supports barrier dimming modes.
- Returns selection via `Future<T?> selection`.

Use this instead of custom command-picker implementations.

### TableFormatter

`TableFormatter.format(...)` is the canonical aligned table renderer.

- Handles min/max widths
- Supports truncation + ANSI-safe sizing
- Supports right-aligned numeric columns

Use this for session/agent/status lists to avoid column drift.

## Overlay and Focus Model

For floating panels and modals:

1. Render base content.
2. Apply backdrop dim pass.
3. Render overlay panels on top.
4. Route events to focused overlay first.
5. Fall back to page/global handlers only if overlay does not consume input.

Dock panel requirements:

- `DockMode.floating` (no reserved layout insets)
- Explicit focus state
- Clear hotkeys to toggle, focus, and clear focus

## Canonical Realistic Scenario Fixture

The theme demo contains a canonical "realistic scenario" page:

- Conversation history
- Tool call phases (`done`, `running`, `denied`, `error`)
- Expanded status/error messaging
- Subagent activity lines
- Concurrent stream lanes
- Bash/output block

It supports:

- Live streaming progression (timer-driven)
- Scrollable history viewport
- Pause/resume/restart/follow-tail controls

Use this page as the visual regression target when changing render behavior.

## Usage Checklist for New UI

When adding a new panel/overlay/view:

1. Start with tokens and recipes, not raw ANSI.
2. Use `TableFormatter` for tabular content.
3. Use `SelectPanel` for searchable pickers.
4. Keep overlays floating unless there is a hard requirement for pinned layout.
5. Add or update demo coverage in `glue_theme_demo.dart`.
6. Add tests for new formatting/navigation behavior.

## Running the Demo

From `cli/`:

```bash
dart run bin/glue_theme_demo.dart
```

Use page `5` for the realistic scenario and streaming/scroll interaction checks.
