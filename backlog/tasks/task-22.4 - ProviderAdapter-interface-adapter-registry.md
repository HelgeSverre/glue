---
id: TASK-22.4
title: ProviderAdapter interface + adapter registry
status: Done
assignee: []
created_date: '2026-04-19 00:36'
updated_date: '2026-04-19 04:02'
labels:
  - model-provider-2026-04
  - llm
  - refactor
dependencies:
  - TASK-22.1
  - TASK-22.3
documentation:
  - cli/docs/plans/2026-04-19-provider-adapter-contract-plan.md
parent_task_id: TASK-22
priority: high
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Consolidate provider-specific logic behind one interface. Keep app/agent code provider-neutral.

**Interface (from Provider Adapter Contract plan):**
```dart
abstract class ProviderAdapter {
  String get adapterId;
  Future<ProviderHealth> validate(ProviderConfig provider);
  LlmClient createClient({
    required ProviderConfig provider,
    required ModelConfig model,
    required String systemPrompt,
  });
  Future<List<ModelConfig>> discoverModels(ProviderConfig provider) async {
    return const [];
  }
}
```

`discoverModels` is **optional and explicit** — must NOT run during normal startup.

**Adapter vs compatibility distinction:**
- `adapter` picks the wire protocol (`anthropic` / `openai` / `gemini` / `mistral`)
- `compatibility` tunes provider-specific quirks (auth header shape, required headers, `/models` availability, streaming tool deltas, partial JSON streaming, image input, tool-result images, error parser, model ID prefix handling)

**Files to create/modify:**
- Create: `cli/lib/src/llm/adapters/provider_adapter.dart`
- Create: `cli/lib/src/llm/adapters/adapter_registry.dart`
- Create/refactor: `cli/lib/src/llm/adapters/{anthropic,openai,gemini,mistral}_adapter.dart`
- Modify: `cli/lib/src/llm/llm_factory.dart` — becomes a thin dispatcher over the registry
- Existing `{anthropic,openai,ollama}_client.dart` get called through their adapter

**Acceptance:** no `switch (provider)` chains in app/agent code for normal requests.

**Depends on:** MP1 (catalog), MP3 (credentials).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `ProviderAdapter` interface defined
- [ ] #2 Each built-in adapter (anthropic/openai/gemini/mistral) implemented
- [ ] #3 `LlmClientFactory.create(providerConfig, modelConfig)` dispatches via registry
- [ ] #4 `discoverModels` is optional and never runs during startup
- [ ] #5 No `switch (LlmProvider)` chains remain for normal requests in app/agent code
- [ ] #6 Existing SSE/NDJSON parsing preserved (wire-level clients unchanged)
- [ ] #7 Tests cover adapter selection for each built-in adapter
<!-- AC:END -->
