---
id: TASK-23.6
title: >-
  Custom Vue components: TerminalDemo, ModelTable, RuntimeMatrix, ConfigSnippet,
  FeatureStatus
status: To Do
assignee: []
created_date: '2026-04-19 00:38'
labels:
  - website-2026-04
  - components
dependencies:
  - TASK-23.1
documentation:
  - docs/plans/2026-04-19-website-redesign-plan.md
  - docs/plans/2026-04-19-docs-site-source-of-truth-plan.md
parent_task_id: TASK-23
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Vue components for the unified site. Each receives data from generated JSON or Markdown frontmatter — never duplicates full tables internally.

**Components to create** (in `devdocs/.vitepress/theme/components/`):

1. **`TerminalDemo.vue`** — scripted playback of a multi-turn session (user prompt → assistant response → tool call → edit summary → command output → concise answer). Embeddable via `<TerminalDemo script="..." />`. Real fonts/colors matching the TUI. Replay via click.

2. **`ModelTable.vue`** — renders the catalog from `cli/docs/reference/models.yaml` (or a processed build-time copy). Used on `/models` and in docs.

3. **`RuntimeMatrix.vue`** — capability matrix (host/Docker/remote × `command_capture`/`filesystem_write`/`browser_cdp`/…). Used on `/runtimes`.

4. **`ConfigSnippet.vue`** — renders a tested config snippet with syntax highlighting. Source snippets live in `docs/snippets/`.

5. **`FeatureStatus.vue`** — small badge component for `shipping` / `experimental` / `planned` labels (see W10).

**Design rules:**
- No decorative gradients; semantic colors only
- Match the TUI visual direction (minimal, compact symbols, readable blocks)
- Prefer real screenshots or scripted terminal renders over hand-made mockups

**Depends on:** W1.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Five components exist under `devdocs/.vitepress/theme/components/`
- [ ] #2 `TerminalDemo` supports scripted playback + click-to-replay
- [ ] #3 `ModelTable` reads from `cli/docs/reference/models.yaml` (via W9 generation)
- [ ] #4 `RuntimeMatrix` accepts capability data via prop/frontmatter
- [ ] #5 `FeatureStatus` badges render for each of `shipping`/`experimental`/`planned`
- [ ] #6 No decorative gradients; all color use is semantic
<!-- AC:END -->
