---
id: TASK-25.2
title: Display-width wrapping + glyph policy + ASCII fallback mode
status: To Do
assignee: []
created_date: "2026-04-19 00:42"
updated_date: "2026-04-20 00:05"
labels:
  - tui-contract-2026-04
  - rendering
milestone: m-1
dependencies: []
documentation:
  - cli/docs/plans/2026-04-19-tui-behavior-contract-plan.md
parent_task_id: TASK-25
priority: medium
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Wrap by **display width**, not code unit count. Establish a glyph policy for state markers with a mandatory ASCII fallback for every semantic symbol.

**Wrapping rules:**

- Wrap by display width (not code unit count)
- ANSI escape sequences do not count toward width
- Wide glyphs count as width 2
- Ambiguous-width glyphs default to width 1 (unless terminal probing added later)
- Wrapped continuation lines align under the content column, not the marker
- Long unbroken tokens may hard-wrap
- Markdown tables may degrade gracefully on narrow widths
- Tool output wraps or truncates by block type (not ad hoc)

**Glyph policy:**

- Use single-cell symbols for control and state markers
- AVOID: double-width-in-common-fonts symbols, Nerd Fonts, long dotted rules, color-only state
- REQUIRED: ASCII fallback for every semantic symbol

**ASCII/no-color mode:**

- Add `--ascii` or env `GLUE_ASCII=1` (decide during implementation)
- All semantic symbols fall back to plain ASCII (`*`, `>`, `+/-`, `[x]`)
- Respect `NO_COLOR` env var (standard)

**Files:**

- Modify: rendering code in `cli/lib/src/rendering/` + `cli/lib/src/ui/`
- Create: `cli/lib/src/rendering/glyph_set.dart` — Unicode + ASCII fallback mappings
- Tests: wide-glyph wrapping, ANSI-safe truncation, ASCII fallback mode
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 Wrapping uses display width; ANSI sequences don't count; wide glyphs count as 2
- [ ] #2 Ambiguous-width glyphs default to width 1
- [ ] #3 `--ascii` / `NO_COLOR` triggers ASCII fallback mode
- [ ] #4 Every semantic symbol has ASCII fallback (state markers, user prompt, list bullets)
- [ ] #5 No Nerd Font icons required
- [ ] #6 Tool output has bounded display (not unbounded scrollable)
- [ ] #7 Tests cover wide glyphs, ANSI truncation, ASCII mode
<!-- AC:END -->
