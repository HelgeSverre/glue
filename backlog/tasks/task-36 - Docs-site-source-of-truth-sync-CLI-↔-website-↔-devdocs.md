---
id: TASK-36
title: Docs site source-of-truth sync (CLI ↔ website ↔ devdocs)
status: To Do
assignee: []
created_date: "2026-04-20 00:08"
updated_date: "2026-04-20 00:32"
labels:
  - docs
  - website
  - consistency
milestone: m-0
dependencies: []
references:
  - website/
  - docs/reference/
  - cli/docs/reference/
documentation:
  - docs/plans/2026-04-19-docs-site-source-of-truth-plan.md
  - docs/plans/2026-04-19-website-redesign-plan.md
priority: low
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Stop getglue.dev / VitePress docs / CLI reference / TUI demos from drifting apart. The website redesign plan defines page structure; this plan defines how content should be sourced so the site doesn't claim behavior the CLI no longer has.

**Per the plan (`docs/plans/2026-04-19-docs-site-source-of-truth-plan.md`):**

- Identify content categories: catalog data (models.yaml), config schema (config-yaml.md), TUI behavior (tui-behavior.md), session storage, runtime capabilities.
- For each category, establish a single source-of-truth file in the repo and have the website import/render from it (no hand-copied tables).
- Add CI check that detects drift between docs and website (e.g. fails when a model name appears in `models.yaml` but not on the marketing models page).

**Coordinates with:**

- TASK-26.5 (runtime capability table) — its YAML is one of the source files this task standardizes.
- The website redesign plan (`docs/plans/2026-04-19-website-redesign-plan.md`) — ship in tandem.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 Each content category (catalog, config schema, TUI behavior, session storage, runtime capabilities) has a documented single source of truth and a one-direction publish path.
- [ ] #2 Website pages render from those sources rather than copying content by hand.
- [ ] #3 CI fails when source-of-truth content references a name/value that no longer exists in the underlying file (e.g. removed model id).
- [ ] #4 Plan's category list is fully addressed — each one either implemented or explicitly deferred with reason.
<!-- AC:END -->
