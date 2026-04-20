---
id: TASK-30
title: BlockRenderer / MarkdownRenderer responsive to resize
status: To Do
assignee: []
created_date: "2026-04-19 20:39"
updated_date: "2026-04-20 00:32"
labels:
  - tui
  - rendering
  - followup
milestone: m-1
dependencies: []
documentation:
  - docs/plans/2026-04-19-responsive-panels.md
priority: low
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Follow-up from the 2026-04-19 responsive panels work (see TASK-22.8 finalSummary). `BlockRenderer` and `MarkdownRenderer` capture `width` at construction and use it to wrap headings + pre-compute inner widths. On terminal resize, any already-rendered block retains the old width. In practice this rarely surfaces because most blocks are rendered once and left alone, but it's architectural fragility worth closing.

## Scope

- `cli/lib/src/rendering/block_renderer.dart:45-78` — `BlockRenderer` captures `this.width` once and derives `_inner`. Consider replacing with a per-call `render(width)` or have the renderer re-derive inner widths when the width changes.
- `cli/lib/src/rendering/markdown_renderer.dart:36-100+` — same pattern for `MarkdownRenderer`. Heading wrapping at line ~83-98 uses `this.width`.

## Why deferred

No user-visible breakage today. The block/markdown content tends to be snapshot content in the transcript; users don't see it reflow because historical output already lives at its old width. Deferred from the initial responsive-panels work to keep that PR focused on picker overlays (where the breakage was user-visible via the /model picker miss).

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 BlockRenderer and MarkdownRenderer rebuild per-render when width changes.
- [ ] #2 No regression in existing rendering tests.
- [ ] #3 If width-dependent caching is added for performance, cache key includes width so stale reads can't happen.
- [ ] #4 Tests cover at least one block type (heading, code fence, bullet) at two widths asserting different output.
<!-- AC:END -->
