# Ollama context-window resolution + context-occupancy gauge

**Date:** 2026-06-23
**Status:** Approved design, pending implementation plan
**Branch:** thermo-nuclear-fixes

## Background

Investigation of a Gemma session (`ollama/gemma4:latest`) surfaced two distinct
issues that look like one "token counting is broken" complaint but are not:

1. **`token_count` is not broken.** `SessionMeta.tokenCount` (126771 in the
   sample session) is the exact cumulative sum of input+output across every
   billed LLM call, including background title generation. It is a *spend
   odometer* (documented at `session_store.dart:52-56`), not a context-window
   gauge. Comparing it to the ~14k single-turn context size is a category
   error. No fix needed here.

2. **A real latent footgun.** `GlueConfig.resolveModel` (`glue_config.dart:184-192`)
   does an exact-string catalog lookup; a miss yields a synthetic `ModelDef`
   with `contextWindow == null`. The catalog ships `gemma4:26b` but users run
   `gemma4:latest` (the common pulled tag). Null flows through
   `OllamaAdapter.createClient` (`ollama_adapter.dart:59`) to `OllamaClient`,
   which then **skips** the `num_ctx` injection (`ollama_client.dart:64`) — the
   very protection its own docstring calls "the fix for Ollama's
   silent-truncation-at-2048 footgun." Any Ollama model run by an uncatalogued
   tag is exposed to Ollama's 2048-token silent truncation, which on a model
   whose Modelfile defaults to 2048 would cause genuine context loss
   ("forgetting").

Separately, there is **no context-occupancy indicator** anywhere in the UI —
only the cumulative spend figure — so users have no signal for how full the
window is.

This spec covers two fixes:

- **Fix 1** — resolve an Ollama model's real context window robustly, so
  `num_ctx` is always sized correctly (never the silent 2048).
- **Fix 2** — add a context-occupancy gauge to the status bar.

`token_count` semantics are left unchanged by design.

## Fix 1 — Ollama `num_ctx` resolution

### Resolution order

Resolved **once**, lazily, on the first `OllamaClient.stream()` call (because
`ProviderAdapter.createClient` is synchronous and cannot await a daemon call):

1. **Exact catalog window** — the constructor `contextWindow` arg, when
   non-null (e.g. catalogued `gemma4:26b` → 256000).
2. **Daemon `/api/show`** — query the running Ollama daemon for the loaded
   model's actual trained `context_length`. This is the uncatalogued-`:latest`
   path and the most accurate source.
3. **Catalog base-name fallback** — a secondary hint passed from the adapter:
   strip the tag and match the family (`gemma4:latest` → `gemma4:26b`).
4. **Default `8192`** — a new `ollamaDefaultNumCtx` constant, used **only** to
   size `num_ctx` so we never fall back to Ollama's 2048.

`num_ctx = min(resolved, ollamaNumCtxCeiling)` where the ceiling is the existing
131072. `num_ctx` is **always** injected after this change.

### Real-window vs. guessed-window distinction

The client tracks the *real* resolved window (steps 1-3) separately from the
8192 default (step 4):

- `num_ctx` sizing uses `realWindow ?? ollamaDefaultNumCtx`.
- The window **exposed for the gauge** (`contextWindow` getter) returns
  `realWindow` — i.e. **null** when only the 8192 default applied. A pure guess
  must never become a fake gauge denominator.

### Component changes

- **`OllamaDiscovery.showContextLength(String tag) -> Future<int?>`** (new):
  `POST /api/show {name: tag}`, scan `model_info` for any key ending in
  `.context_length`, return its int value. Fail-soft (timeout / non-200 /
  malformed → null) and cached, matching the existing `/api/tags` method.
- **`OllamaClient`**: accept an exact `contextWindow` and a
  `contextWindowFallback` (base-name hint). Resolve lazily and cache. Always
  inject `num_ctx`. Override `int? get contextWindow` to return the real
  resolved window (null when only-default).
- **`OllamaAdapter.createClient`**: compute the base-name fallback from
  `provider.models` and pass both exact (`model.def.contextWindow`) and
  fallback to the client.
- **`LlmClient`**: add `int? get contextWindow => null;` (default
  implementation — non-breaking for all other clients).
- **`ollama_client.dart`**: add `const int ollamaDefaultNumCtx = 8192;`.

## Fix 2 — Context-occupancy gauge

### Numerator (current occupancy)

- **`AgentCore.lastTurnInputTokens`** (new `int`, default 0): set to
  `inputTokens + cacheReadTokens` (the billed input — what the model actually
  saw) after each turn's stream completes. This is computed already at
  `agent_core.dart:240` (`billableInput`); we capture it to a field. Not
  updated on the tools-not-supported retry path (the next real turn overwrites
  it).

### Denominator (window)

Resolved in the App:
`resolveModel(activeModel).def.contextWindow ?? agent.llm.contextWindow`
— catalog value for known models; the Ollama client's daemon-resolved value for
uncatalogued tags. Null when neither is available.

### Rendering

- **`formatContextGauge(int used, int? window) -> String?`** (in
  `cli/lib/src/extensions/token_format.dart`): returns e.g.
  `14.3k/131k ctx (11%)`, reusing `formatCompactTokens`. Returns **null** when
  `window` is null/≤0 **or** `used` is 0 — the caller omits the segment
  entirely (the "hide when unknown" behavior).
- **`app.dart` status bar**: insert the gauge segment (when non-null) into
  `rightSegs` immediately before the existing
  `'${formatCompactTokens(agent.stats.totalTokens)} tokens'` cumulative-spend
  segment. The spend segment is unchanged. The two numbers are intentionally
  distinct: occupancy (`14.3k/131k ctx`) vs lifetime spend (`126k tokens`).

## Testing

- **`OllamaClient`**: injects `num_ctx` from an exact catalog window; lazily
  queries the daemon when uncatalogued; uses the base-name fallback; uses the
  8192 default when all else fails; caps at the 131072 ceiling; `contextWindow`
  getter returns null when only the default applied. Uses a fake
  `requestClientFactory` (existing test pattern).
- **`OllamaDiscovery.showContextLength`**: parses `model_info.*.context_length`
  across arch prefixes; fail-soft → null on error/malformed.
- **`OllamaAdapter`**: base-name fallback resolution from `provider.models`.
- **`formatContextGauge`**: pct rounding, compaction, null/≤0 window → null,
  zero used → null.
- **`AgentCore.lastTurnInputTokens`**: updates to billed input after a turn
  (fake `LlmClient` yielding `UsageInfo` with input + cache-read tokens).

## Scope guard

- No change to `token_count` / `SessionMeta` semantics.
- No change to non-Ollama LLM clients beyond inheriting the `null` default
  `contextWindow` getter; their gauge denominator comes from the catalog as
  today.
- No refactor beyond the listed touch-points.

## Touch-point reference

| Area | File |
| --- | --- |
| Daemon `/api/show` | `packages/glue_strategies/lib/src/providers/ollama_discovery.dart` |
| num_ctx resolution + getter | `packages/glue_strategies/lib/src/llm/ollama_client.dart` |
| Adapter base-name hint | `packages/glue_strategies/lib/src/providers/ollama_adapter.dart` |
| LlmClient default getter | `packages/glue_core/lib/src/llm_client.dart` |
| last-turn input | `packages/glue_harness/lib/src/agent/agent_core.dart` |
| gauge formatter | `cli/lib/src/extensions/token_format.dart` |
| status bar wiring | `cli/lib/src/app.dart` (~line 1103) |
