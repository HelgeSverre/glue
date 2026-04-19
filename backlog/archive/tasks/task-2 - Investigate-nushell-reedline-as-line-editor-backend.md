---
id: TASK-2
title: Investigate nushell/reedline as line editor backend
status: To Do
assignee: []
created_date: '2026-04-18 23:57'
updated_date: '2026-04-19 00:43'
labels:
  - spike
  - tui
  - input
  - research
dependencies: []
references:
  - cli/IDEAS.md
  - 'https://github.com/nushell/reedline'
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Spike: evaluate whether Glue's prompt input could be backed by nushell's `reedline` instead of the current custom implementation. Reedline offers built-in history search, hints, multiline support, completion menus, and vi/emacs modes.

Source: `cli/IDEAS.md` — reference: https://github.com/nushell/reedline?tab=readme-ov-file#are-we-prompt-yet-development-status

Output should be a written recommendation (stay with custom impl / adopt reedline / hybrid), documenting:
- How reedline would be called from Dart (FFI? subprocess? Rust bridge?)
- Which current Glue input features are preserved / lost / improved
- Integration risk with the existing TUI scroll regions and raw terminal mode
- Cross-platform story (macOS/Linux/Windows)

This is investigation only — no implementation. If the recommendation is "adopt", a follow-up task captures implementation work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Written recommendation document (in `cli/docs/plans/` or `.backlog/docs/`)
- [ ] #2 Feature parity matrix: current Glue input vs reedline capabilities
- [ ] #3 Integration approach evaluated (FFI / subprocess / rewrite)
- [ ] #4 Cross-platform feasibility documented
- [ ] #5 Clear go/no-go recommendation with rationale
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Overlap with new task-21 (Unified AutocompleteOverlay interface) from the 2026-04-19 simplification plan. If reedline is adopted later, it would supersede M10 entirely. Keep this spike independent; its output should evaluate whether adopting reedline makes M10 unnecessary.
<!-- SECTION:NOTES:END -->
