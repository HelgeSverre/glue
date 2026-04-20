---
id: TASK-22.7
title: Model picker + /provider + /models commands
status: To Do
assignee: []
created_date: "2026-04-19 00:36"
updated_date: "2026-04-20 00:05"
labels:
  - model-provider-2026-04
  - ui
  - commands
milestone: m-0
dependencies:
  - TASK-22.1
  - TASK-22.3
  - TASK-22.4
documentation:
  - cli/docs/plans/2026-04-19-model-provider-config-redesign.md
parent_task_id: TASK-22
priority: medium
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

**Progress (2026-04-19):** Model picker rewrite shipped in commit `c428576` (MP7 hard swap). `/provider`/`/models` command surface deferred to TASK-22.8 with a simplified scope (only `/provider` namespace, OAuth support).

Replace the current single-level `/model` picker with a curated multi-provider picker and add provider/catalog commands.

**New/updated commands:**

- `/model` — opens picker (filtered to curated, tool-capable, credentials-available models)
- `/model anthropic/claude-sonnet-4.6` — direct switch
- `/models` — list all catalog entries (including hidden)
- `/providers` — list configured providers + health status (via `ProviderAdapter.validate()`)
- `/provider add` — interactive flow: name, adapter, base_url, compatibility, auth
- `/provider test <id>` — validate credentials via connector (no side effects)
- `/models refresh <provider>` — **explicit** catalog refresh via `discoverModels()` (no auto-refresh on startup)
- `/models import <provider>` — prompt user to pick models and append to `~/.glue/models.yaml`

**Picker filters:**

- Default: `selection.default_filter.capabilities` from catalog (typically `chat` + `tools`)
- Hidden models (`hidden_models` in user config) excluded from default view
- User filters: `@provider:openai`, `@capability:vision`, `@capability:local`, `@speed:fast`, `@cost:low`, `@visible:true`

**Files:**

- Modify: `cli/lib/src/commands/builtin_commands.dart`
- Create: `cli/lib/src/commands/provider_commands.dart`, `model_commands.dart`
- Modify: model picker UI in `cli/lib/src/ui/` (find existing via grep)

**Depends on:** MP1, MP3, MP4.

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 Picker default-filters by `selection.default_filter.capabilities` from catalog
- [ ] #2 Hidden models excluded from default picker view
- [ ] #3 Picker supports filters: `@provider:`, `@capability:`, `@speed:`, `@cost:`, `@visible:`
- [ ] #4 `/provider add` successfully adds a new OpenAI-compatible provider without code changes
- [ ] #5 `/provider test <id>` reports health without writing anywhere
- [ ] #6 `/models refresh` never runs automatically; writes nothing without explicit user action
- [ ] #7 `/models import` asks per-model confirmation before appending to `~/.glue/models.yaml`
- [ ] #8 Tests cover picker filtering + each command
<!-- AC:END -->
