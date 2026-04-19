---
id: TASK-22.1
title: Catalog parser + bundled models.yaml
status: To Do
assignee: []
created_date: '2026-04-19 00:36'
labels:
  - model-provider-2026-04
  - config
dependencies: []
documentation:
  - cli/docs/plans/2026-04-19-model-provider-config-redesign.md
  - cli/docs/plans/2026-04-19-provider-adapter-contract-plan.md
  - cli/docs/reference/models.yaml
parent_task_id: TASK-22
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Load a curated model catalog from YAML instead of hardcoded Dart `ModelRegistry`. The canonical catalog shape lives in `cli/docs/reference/models.yaml` — a reference example.

**Catalog shape (top-level keys):** `version`, `updated_at`, `defaults`, `catalog`, `selection`, `capabilities`, `providers`, `profiles`

**Providers carry:** `name`, `adapter`, `enabled`, `base_url?`, `docs_url?`, `auth.api_key` (`env:NAME` / `none` / inline), `request_headers?`, `models: { id: { name, recommended, default?, capabilities[], context_window, speed, cost, notes } }`

**Capabilities (per Provider Adapter Contract plan):** `chat`, `streaming`, `tools`, `parallel_tools`, `vision`, `files`, `json`, `reasoning`, `coding`, `local`, `browser`, `binary_tool_results` — plus model-level fine-grained `tool_calling.{supported, parallel, argument_format}`, `streaming.{supported, emits_tool_call_start}`, `tool_results.{images, binary}`, `reasoning.{effort_control, summary_control}`.

**Rule:** Missing capability = false/unknown, NOT "probably supported". App checks capabilities before enabling features.

**Files to create:**
- `cli/lib/src/config/catalog/catalog_parser.dart`
- `cli/lib/src/config/catalog/model_entry.dart`, `provider_entry.dart`, `profile_entry.dart`, `capability.dart`
- `cli/assets/models.yaml` — bundled copy (initially identical to `cli/docs/reference/models.yaml`)
- `cli/test/config/catalog/catalog_parser_test.dart`

**Gotchas:**
- Ollama `api_key: none` is a valid distinct value, not empty string
- Parse errors must include YAML path + key path + reason
- Unknown fields ignored gracefully (forward-compat)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Parser produces typed structs for every field in `cli/docs/reference/models.yaml`
- [ ] #2 Unknown fields ignored gracefully (forward-compat)
- [ ] #3 Parse errors include YAML file path + key path + reason
- [ ] #4 Capability enum covers all 12 values from adapter contract plan
- [ ] #5 Tests cover happy path + each error case + empty/partial catalog
- [ ] #6 Tests cover `api_key: none` vs empty string distinction
<!-- AC:END -->
