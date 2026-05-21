# Plan: Gate Ollama models that lack tool-calling capability

## Context

When a user starts Glue with an Ollama model that doesn't support function calling (e.g. `ollama/qwen2.5:7b`, `ollama/llama3.2:1b`), Ollama returns `400 {"error": "<model> does not support tools"}` on the first agent turn. Glue currently throws a raw `Exception` (see `packages/glue_strategies/lib/src/llm/ollama_client.dart:174-176`) and the user sees a stack trace mid-session — usually after they've already typed a prompt.

The catalog already declares per-model `capabilities: Set<String>` including `'tools'`, and the `/model` picker filters by it (`cli/lib/src/commands/slash/model.dart:65`), but:

- `--model` and direct selection of a previously-picked model bypass the picker.
- Uncatalogued passthrough tags (user pulled their own) have an empty `capabilities` set — indistinguishable from "we don't know".
- The runtime never consults `model.def.capabilities` once a client is constructed.

**Intended outcome:** when the user picks a tool-incapable Ollama model for the agent role, Glue refuses to start with a clear, actionable error (listing tool-capable alternatives) — instead of crashing on the first turn. Chat-only callers (`RecapGenerator`, `TitleGenerator`, slash commands) remain unaffected so a tool-less model can still be used as `small_model` for summaries.

## Approach

Three pieces, one PR:

1. **`/api/show` probe + cache** in a new `OllamaShow` strategy class (mirrors the existing `OllamaDiscovery` pattern), so uncatalogued tags can be classified without bricking the catalogued happy path.
2. **`ToolCapabilityProbe`** in `glue_harness` — catalog-first, daemon-fallback resolution with explicit "unknown" semantics.
3. **`createForAgent`** on `LlmClientFactory` — a new opt-in code path that gates on the probe. Only `ServiceLocator` (main agent boot) and `AgentManager` (subagent spawn) call it. The existing `createFor` / `createFromConfig` stay capability-agnostic for chat-only consumers.

### Behavior decisions

- **Probe unreachable** (daemon down, timeout, malformed): let the model through with a warning to observability. The eventual `400` from Ollama still produces the existing error path — no worse than today for the offline-daemon edge case.
- **`glue doctor` scope**: active model + named roles (`defaults.model`, `defaults.small_model`, `defaults.local_model`) only. Avoids N probes for everything in the catalog.
- **Ship as one PR**: probe and gate together. Single behavior change, single revert if needed.

## Files

### New

| Path | Purpose |
|---|---|
| `packages/glue_strategies/lib/src/providers/ollama_show.dart` | `class OllamaShow` — `Future<Set<String>?> capabilitiesFor(String tag)` hitting `POST /api/show`. Same cache/TTL pattern as `OllamaDiscovery` (lines 78-94). Returns `null` on any failure (unknown), empty set when daemon says no capabilities, populated set on success. Fail-soft like discovery. |
| `packages/glue_harness/lib/src/agent/tool_capability.dart` | `class ToolCapabilityProbe` constructed with `ModelCatalog` + `OllamaShow`. Method `Future<void> requireToolsFor(ModelRef ref)` throws `ModelLacksToolsException` if catalog or probe confirms `'tools'` is missing; returns normally on success or "unknown". Plus the `ModelLacksToolsException` itself (`implements Exception`, not a `ConfigError` subtype — different exit code, different remediation language). |

### Modified

| Path | Change |
|---|---|
| `packages/glue_harness/lib/src/agent/llm_factory.dart` | Add `Future<LlmClient> createForAgent(ModelRef ref, {required String systemPrompt, required ToolCapabilityProbe probe})`. Calls `probe.requireToolsFor(ref)` *before* `adapter.createClient`. Existing `createFor` / `createFromConfig` untouched. |
| `packages/glue_harness/lib/src/core/service_locator.dart:101` | Construct a shared `OllamaShow` instance (reused by doctor via `services.ollamaShow` getter or similar). Build `ToolCapabilityProbe(catalog: config.catalogData, show: ollamaShow)`. Switch `llmFactory.createFromConfig(...)` to `llmFactory.createForAgent(config.activeModel, ..., probe: probe)`. |
| `packages/glue_harness/lib/src/agent/agent_manager.dart:127` | Subagent spawn switches from `createFor` to `createForAgent` so subagent model overrides are gated too. |
| `cli/bin/glue.dart:58-75` | New catch arm above the generic handler: `on ModelLacksToolsException catch (e) { stderr.writeln(e.message); exit(69); }` (`EX_UNAVAILABLE`). Keeps the existing `ConfigError` / `ModelRefParseException` shape — typed exception + stderr + meaningful exit code. |
| `cli/lib/src/doctor/doctor.dart` | New `_checkOllamaToolCapability(findings, config, ollamaShow)` invoked from the main report flow. Skips silently when no provider with `adapter: ollama` exists in the catalog. For each in-scope model (active + named-role pointers): catalog check first, then `OllamaShow` probe. Findings use `DoctorFinding(severity, section, message, hint?)` matching the existing `_checkRuntime` style. Output follows brand-marker convention per `docs/design/cli-output-formatting.md` (referenced from CLAUDE.md). |

## Reused existing functions / utilities

- `OllamaDiscovery._cache` pattern (`packages/glue_strategies/lib/src/providers/ollama_discovery.dart:78-94`) — `OllamaShow` clones this 30s TTL cache verbatim, keyed by `(baseUrl, tag)`.
- `OllamaDiscovery._fetch()` pattern (lines 164-192) — same NDJSON-less JSON request shape; reuse the timeout (`Duration(seconds: 2)`) and fail-soft envelope.
- `OllamaDiscovery.invalidateCache()` — call it whenever a refresh happens (e.g. after `ollama pull` via the model picker) so probe and tag-list stay coherent.
- `ConfigError` typed-exception + top-level catch pattern (`packages/glue_harness/lib/src/config/glue_config.dart`, caught in `bin/glue.dart:66-71`) — `ModelLacksToolsException` follows the same shape but stays stand-alone for distinct exit code (69 vs 78) and message tone.
- `ModelCatalog.providers[id].models[id].capabilities` (`packages/glue_core/lib/src/model_catalog.dart:62`) — already a `Set<String>`, already populated by the catalog parser. No catalog-schema changes needed.
- `flattenCatalog(...)` filter pattern in `cli/lib/src/commands/slash/model.dart:59-65` — adapt for the "list alternatives" suggestion in the error message.

## Error message shape

```
Error: model "ollama/qwen2.5:7b" does not support tool calling, which Glue
requires to run as an agent.

Try a tool-capable model instead:
  glue --model ollama/qwen3-coder:30b
  glue --model ollama/devstral:24b
  glue --model anthropic/claude-sonnet-4-6

Run `glue doctor` to see all tool-capable models in your catalog.
```

Alternatives pulled from `config.catalogData` via `flattenCatalog`, filtered `capabilities.contains('tools')`, sorted: same-provider first (other Ollama tags), then by a small priority list (anthropic, openai, gemini), capped at 3.

## Probe protocol

- **Endpoint**: `POST {base}/api/show` with body `{"model": "<tag>", "verbose": false}`.
- **Field of interest**: top-level `capabilities: ["completion", "tools", "vision", ...]` — parse to `Set<String>`.
- **Timeout**: 2s (matches `OllamaDiscovery.timeout`).
- **Failure modes**: non-200, timeout, JSON parse error, connection refused → return `null` (unknown).
- **Cache**: `{(baseUrl, tag) → Set<String>}` with 30s TTL.
- **Invalidation**: piggyback on `OllamaDiscovery.invalidateCache()` callers (the `/model` refresh path).

## Probe resolution order (inside `ToolCapabilityProbe.requireToolsFor`)

1. Lookup `catalog.providers[ref.providerId]?.models[ref.modelId]`. If found with non-empty `capabilities`:
   - Contains `'tools'` → return (OK).
   - Lacks `'tools'` → throw `ModelLacksToolsException`.
2. Not catalogued or empty capabilities, and provider adapter is `ollama` → `OllamaShow.capabilitiesFor(ref.modelId)`.
   - Returns `null` (daemon unreachable) → log warning to obs, return (let it through).
   - Returns set lacking `'tools'` → throw `ModelLacksToolsException`.
   - Returns set containing `'tools'` → return (OK).
3. Non-Ollama uncatalogued model → return (let it through; not our problem to verify).

## Verification

### Unit tests

- `packages/glue_strategies/test/providers/ollama_show_test.dart` — clones `ollama_discovery_test.dart` patterns: 200 happy path with `capabilities` array, 404, timeout, malformed JSON, cache TTL hit/miss, `resetCacheForTesting`.
- `packages/glue_harness/test/agent/tool_capability_test.dart` — full resolution table: catalog-yes / catalog-no / catalog-empty × daemon-yes / daemon-no / daemon-unreachable. Fake `OllamaShow` injected.
- `packages/glue_harness/test/agent/llm_factory_test.dart` — `createForAgent` throws `ModelLacksToolsException` containing the model id and at least one alternative; `createForAgent` succeeds for tool-capable models; existing `createFor` is unchanged.

### CLI tests

- `cli/test/bin/glue_startup_test.dart` — boot with `--model ollama/qwen2.5:7b` against a fake adapter that reports no tools → exit code 69, stderr matches the error template.
- `cli/test/doctor/doctor_test.dart` — three injected fixtures: daemon-down (info), active model lacks tools (error), active model OK (silent or info).

### Integration

- `cli/test/integration/ollama_e2e_test.dart` — add scenario tagged `@Tags(['e2e'])`: boot with a real tool-less Ollama model, assert exit 69 + expected stderr.
- Existing recap/title flow against any model — regression guard that chat-only consumers still work after `createFor` stays untouched.

### Manual smoke

1. `glue --model ollama/qwen2.5:7b` (or any tool-less local tag) → clean error with 3 alternatives + `glue doctor` hint, exit 69.
2. `glue --model ollama/qwen3-coder:30b` → starts normally.
3. `glue doctor` on a system with a tool-less `defaults.local_model` → `✗` line with hint.
4. Stop the Ollama daemon, then `glue --model ollama/<some-uncatalogued-tag>` → starts (lets it through), error surfaces only if the model really lacks tools mid-call.

## Risks

- **`/api/show` cache staleness across `ollama pull`**: 30s window after a user upgrades a model that gained tool support. Mirror `OllamaDiscovery.invalidateCache()` from the `/model` refresh path so picker and probe stay coherent.
- **Subagent spawn latency**: `createForAgent` adds a catalog lookup per spawn; for catalogued models this is a single Set lookup and won't be measurable. Probe path is async but only fires for uncatalogued tags — rare in subagent overrides.
- **Future providers gaining the same problem**: if OpenRouter or Gemini ship local tool-less routes, the `ToolCapabilityProbe` is extensible — drop the Ollama-only check in step 2 and add per-adapter probe support. Plan does not require that today.

## Sequence

Single PR:
1. Add `OllamaShow` + tests.
2. Add `ToolCapabilityProbe` + `ModelLacksToolsException` + tests.
3. Add `createForAgent` to `LlmClientFactory` + tests.
4. Switch `ServiceLocator` and `AgentManager` call sites.
5. Add `bin/glue.dart` catch arm.
6. Add `doctor.dart` block + tests.
7. Manual smoke; ship.
