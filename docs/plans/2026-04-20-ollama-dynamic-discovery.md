# Ollama Dynamic Discovery Plan

Status: proposed
Owner: implementation agent
Date: 2026-04-20

## Goal

When Glue talks to Ollama, the `/model` picker should reflect the user's
*actual* installed models — merged with our curated catalog — instead of
showing only curated rows that may or may not be pulled locally.

Concretely:

- Pulled-but-uncatalogued models appear in the picker tagged "local only".
- Catalogued-but-not-pulled models appear with a visible "not pulled" marker.
- Catalogued-and-pulled models appear normally (the happy path).
- If Ollama isn't running or is unreachable, the picker falls back to the
  bundled catalog silently — it never blocks startup or the picker open.

## Why now

Three related pains converge on this work:

1. **Discoverability.** Users who've pulled `gemma4:latest` don't see it in
   `/model`; they have to type it by hand and hope the adapter doesn't choke.
2. **Honesty.** The curated list currently asserts 10 Ollama entries regardless
   of what the user has. If they've pulled nothing, picking any row triggers a
   many-GB download on first use with no warning.
3. **Drift.** Today we rely on `test/integration/ollama_catalog_registry_test.dart`
   to catch tags that Ollama has removed. Dynamic discovery makes that test
   guard rails only — the picker stops lying about availability in real time.

Closely related (not in scope for this plan but should ship as sibling PRs —
see "Adjacent Ollama hardening" below):

- `num_ctx=2048` injection (Ollama's silent-truncation default).
- Pre-0.17.3 version check.
- `think=false` default for Qwen3 thinking variants under tool use.

## Current Code Context

Relevant files:

- `lib/src/catalog/model_catalog.dart` — `ProviderDef.models: Map<String, ModelDef>`
- `lib/src/catalog/models_generated.dart` — bundled Ollama catalog
- `lib/src/providers/compatibility_profile.dart` — `CompatibilityProfile.ollama`
- `lib/src/providers/openai_compatible_adapter.dart` — builds `OpenAiClient` for Ollama
- `lib/src/llm/openai_client.dart` — HTTP layer; does not speak Ollama-native APIs today
- `lib/src/ui/model_panel_formatter.dart` — `flattenCatalog`, `buildModelPanel`, `CatalogRow`
- `lib/src/ui/panel_controller.dart` — opens picker, wires `entries: List<CatalogRow>`
- `lib/src/app.dart` — `_switchToModelRow(CatalogRow)` handles selection

Current behavior:

- `/model` picker is built from `catalog.providers['ollama'].models` only.
- No runtime check whether Ollama is reachable or which models are pulled.
- `ModelDef` has no notion of "installed" vs "catalog-only".
- `CatalogRow` is `{providerId, providerName, ModelDef model}` — flat and static.

## Design

### New module: `lib/src/llm/ollama_discovery.dart`

A small, single-purpose client for Ollama's metadata endpoints. Does not
depend on `ModelCatalog` or UI types — returns plain value objects.

```dart
class OllamaDiscovery {
  OllamaDiscovery({required this.baseUrl, http.Client? httpClient, Duration? timeout});

  final Uri baseUrl;
  final Duration timeout; // default 2s

  /// GET /api/tags. Returns installed model names (e.g. "qwen3-coder:30b").
  /// Empty list on error/timeout/daemon-down — never throws.
  Future<List<OllamaInstalledModel>> listInstalled();

  /// GET /api/version. Null on error. Used for the pre-0.17.3 warning
  /// (delivered by a sibling PR, hook exposed here so both can share the client).
  Future<String?> version();
}

class OllamaInstalledModel {
  final String tag;          // "qwen3-coder:30b"
  final int sizeBytes;       // raw bytes on disk
  final DateTime modifiedAt; // from API
  // Plus `digest`, `family`, `parameter_size` if we want them later.
}
```

Fail-soft is non-negotiable: every network error swallows to an empty list or
null. The picker must never hang or surface a red error because Ollama isn't
running.

### Caching

Discovery runs at picker-open time, not at startup:

- **Scope:** single process, invalidated when the picker closes.
- **Keying:** the resolved Ollama `base_url` (rarely changes; still worth keying).
- **TTL:** 30 seconds within a single picker session. Reopening the picker
  within 30 s reuses cached results; otherwise re-fetches.
- Not persisted to disk — it's cheap enough to re-query and avoids stale data
  across long-running sessions.

### Picker integration

Extend `CatalogRow` with a per-row availability hint:

```dart
enum ModelAvailability { catalogued, installed, installedButUncatalogued, notInstalled, unknown }

typedef CatalogRow = ({
  String providerId,
  String providerName,
  ModelDef model,
  ModelAvailability availability,  // new
});
```

For non-Ollama providers, always `unknown` (no-op). For Ollama:

- `installed` — catalogued **and** pulled.
- `notInstalled` — catalogued but not pulled.
- `installedButUncatalogued` — pulled but not in our curated list; synthesised
  into a `ModelDef` with `id = tag`, `apiId = tag`, `recommended = false`,
  `name = tag`, `notes = "Installed locally."`.

`flattenCatalog` becomes async (returns `Future<List<CatalogRow>>`) or gains a
sibling async helper that wraps it. The panel controller awaits before
rendering. While the future is pending — typically <100 ms when Ollama is
running locally — render the catalog-only view immediately and re-render when
the merge lands. No spinner unless the wait actually exceeds 300 ms.

### UX in the picker

The existing `ModelPanelBuilder` already has a `marker` column for "current
model". Reuse the notes column for availability badges; don't add a new column.

| Availability | Rendered |
|---|---|
| `installed` | normal |
| `notInstalled` | notes prefixed with `[pull]` dimmed; on enter, show a hint to run `ollama pull …` |
| `installedButUncatalogued` | notes prefixed with `[local]` dimmed |
| `unknown` / non-Ollama | normal |

No new keybindings. No pull-triggering from inside the picker — keep the TUI
shell-free; tell the user the exact `ollama pull` command instead.

## Files to Create / Modify

### Create

- `lib/src/llm/ollama_discovery.dart` — `OllamaDiscovery` client (listInstalled, version).
- `test/llm/ollama_discovery_test.dart` — fake-HTTP-based unit tests covering
  happy path, timeout, daemon-down, and malformed-response responses.

### Modify

- `lib/src/ui/model_panel_formatter.dart` — add `availability` to `CatalogRow`;
  add `Future<List<CatalogRow>> discoverAndFlattenCatalog(...)` that wraps the
  existing sync `flattenCatalog` and merges Ollama discovery.
- `lib/src/ui/panel_controller.dart` — call the async variant when opening the
  model picker; render optimistically while discovery is in flight.
- `lib/src/app.dart` — no changes to `_switchToModelRow` logic. Uncatalogued
  synthetic rows already flow correctly through `ModelRef` + `resolveModel`
  (the existing synthetic-ModelDef fallback in `glue_config.dart` handles them).

No schema change to `docs/reference/models.yaml` or `ModelDef`. The catalog
remains the source of truth for *what we recommend*; discovery is a view layer.

## Verification

- Unit: fake-HTTP tests for `OllamaDiscovery` covering
  (a) 200 with model list, (b) connection refused (daemon down),
  (c) slow response > timeout, (d) 200 with malformed JSON.
- Unit: picker-flatten test that merges a fake discovery result with the
  bundled catalog and verifies the four `ModelAvailability` buckets.
- Integration (opt-in, tag `ollama_registry` or new `ollama_live`):
  with `ollama serve` running locally, open the picker and confirm
  `ollama list` entries appear with the right badges.
- Manual smoke: stop Ollama → open picker → catalog-only renders, no
  errors, no hang.

## Adjacent Ollama hardening (sibling PRs, same provider area)

Recommended order of shipping, small to large:

1. **Version check** — `OllamaDiscovery.version()` + a one-shot log warning
   on the first Ollama call if `< 0.17.3`. Zero user-visible surface beyond
   the log line. ~30 LOC.
2. **`num_ctx` injection** — extend `CompatibilityProfile.mutateBody` to
   accept a `ModelDef` (or pass `contextWindow` via `OpenAiClient` field) and
   inject `options.num_ctx = min(model.contextWindow, 131072)` when
   profile=ollama. Biggest bang-for-buck: fixes the silent 2048-truncation
   footgun. Requires touching `openai_client.dart` and every `mutateBody`
   caller — medium surface.
3. **`think=false` default** — same hook as (2), keyed on a `no_think_by_default`
   marker in the catalog entry for known Qwen3 thinking variants, or a
   `provider.options.think` field. Smaller and less urgent than (2).
4. **This plan (dynamic discovery)** — ships last because it's the largest
   and depends on `OllamaDiscovery` being in place (which the version-check
   PR creates).

## Risks

- **False positives on "installed".** `ollama list` reports what's on disk,
  not what's *loadable right now* (model might be corrupt). Acceptable —
  the user finds out on first inference attempt, same as today.
- **Latency spike** on slow disks when Ollama is starting up. Mitigated by
  the 2 s hard timeout and fail-soft merge.
- **Schema drift** in `/api/tags` payload. Low — the endpoint is stable, and
  a malformed response just yields zero installed models (catalog-only view).
- **Uncatalogued bad picks.** A user might have pulled `codellama:13b` (which
  we list as discouraged). We surface it as `installedButUncatalogued` with
  no warning text. Known-bad surfacing is tracked as a separate (deferred)
  piece of work, not this plan.

## Out of scope

- Pulling models from inside the picker. Give the command; don't run it.
- Disk-space / VRAM gating. Estimated VRAM display would be a nice-add later
  but needs device detection we don't have.
- Non-Ollama dynamic discovery (LM Studio, vLLM listing endpoints). Possible
  next step once this pattern lands.
