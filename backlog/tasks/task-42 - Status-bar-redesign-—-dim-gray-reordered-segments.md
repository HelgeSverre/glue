---
id: TASK-42
title: Status bar redesign — dim gray + reordered segments
status: To Do
assignee: []
created_date: "2026-04-20 00:09"
updated_date: "2026-04-20 00:32"
labels:
  - tui
  - ui
  - cosmetic
milestone: m-1
dependencies: []
documentation:
  - docs/plans/2026-05-status-bar-redesign.md
priority: low
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Replace the current black-on-yellow status bar with a dim gray background / white text style, highlight the model name in bold yellow, and reorder right-side segments to: scroll indicator \u2192 mode \u2192 pwd \u2192 model (bold) \u2192 tokens.

**Per the plan (`docs/plans/2026-05-status-bar-redesign.md`):** cosmetic only \u2014 no behavioral changes, no new state, no new config. Three files touched.

Slot under **TUI Contract** milestone since it touches the same subsystem and ships well with the broader behavior contract work.

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 Status bar uses dim gray bg + white fg; model id bold yellow.
- [ ] #2 Right-side segments ordered: scroll indicator (when present) → approval mode → cwd → model id → token count.
- [ ] #3 No behavior change — status content/visibility logic unchanged.
- [ ] #4 Width math (ANSI escapes excluded) still correct under new style.
- [ ] #5 Visual regression target (`glue_theme_demo` or equivalent) updated.
<!-- AC:END -->
