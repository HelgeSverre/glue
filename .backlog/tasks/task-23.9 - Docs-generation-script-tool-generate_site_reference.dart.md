---
id: TASK-23.9
title: Docs generation script (tool/generate_site_reference.dart)
status: To Do
assignee: []
created_date: '2026-04-19 00:39'
labels:
  - website-2026-04
  - automation
dependencies:
  - TASK-23.1
references:
  - cli/docs/reference/models.yaml
  - cli/docs/reference/config-yaml.md
  - cli/docs/reference/session-storage.md
documentation:
  - docs/plans/2026-04-19-docs-site-source-of-truth-plan.md
parent_task_id: TASK-23
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Prevent website/docs from drifting from code. Add a lightweight generator that produces derived docs from the canonical sources.

**Create script:** `tool/generate_site_reference.dart`

**Inputs:**
- `cli/docs/reference/models.yaml` — canonical model catalog
- `cli/docs/reference/config-yaml.md` — config examples
- Future session JSONL schema doc (from SE parent)
- TUI demo fixture outputs (from T parent, future)
- `cli/CHANGELOG.md` — release metadata

**Outputs (under `devdocs/generated/`):**
- `devdocs/generated/models.md` — consumed by `ModelTable.vue` (W6)
- `devdocs/generated/config-examples.md`
- `devdocs/generated/session-events.md`
- `devdocs/public/tui/*.svg` or ANSI text blocks (later, after TUI contract stabilizes)
- `docs/snippets/install.md` — single source for install commands, included by every page

**Mark generated files clearly:**
```md
<!-- Generated from cli/docs/reference/models.yaml. Do not edit by hand. -->
```

**Open question (decide during execution):** commit generated files, or generate during site build? Default to commit — easier to review changes.

**Depends on:** W1.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Script exists at `tool/generate_site_reference.dart`
- [ ] #2 Generates `devdocs/generated/models.md` from `cli/docs/reference/models.yaml`
- [ ] #3 Generates `devdocs/generated/config-examples.md`
- [ ] #4 Install command snippet exists at `docs/snippets/install.md` and is used by home + getting-started
- [ ] #5 Generated files carry a "Do not edit by hand" comment
- [ ] #6 Decision documented: commit generated vs build-time
<!-- AC:END -->
