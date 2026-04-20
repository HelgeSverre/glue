# Known Issues

Consolidated issue tracker. Last updated: 2026-03-05.

Items marked **[IN-FLIGHT]** are addressed by open PRs or conductor workspaces.
Items marked **[RESOLVED]** have been fixed but are kept for reference until verified.

---

## Architecture

### ARCH-001: `app.dart` is a 723-line orchestrator **[RESOLVED]**

**Severity:** High
**Files:** `lib/src/app.dart`

`app.dart` was reduced from 2,839 lines to 723 lines and now stays in the target range (~600-800). Core responsibilities were extracted into focused modules (event routers, render pipeline, panel controller, agent orchestration, shell runtime, session runtime, splash runtime, command wiring, and supporting app models/events).

**Fix:** Keep `App` as the top-level event-loop orchestrator and continue future feature work in extracted modules.

---

### ARCH-002: `GlueHome` instantiated 8 times with no shared instance **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/app.dart` (lines 294, 489, 691, 800, 822, 878, 1036, 1939)

`GlueHome()` is created ad-hoc at every call site. No single owner, no way to override for tests without environment monkeypatching.

**Fix:** Create a `Paths` utility (or add path getters to `GlueConfig`) that is instantiated once and injected. All path resolution flows through one object.

---

### ARCH-003: `GlueConfig.load()` hardcodes `~/.glue/config.yaml` path **[RESOLVED]**

**Severity:** Medium
**Files:** `lib/src/config/glue_config.dart:161-163`

Bypasses `GlueHome` entirely with `'${Platform.environment['HOME']}/.glue/config.yaml'`. If `GlueHome.basePath` is ever overridden, `GlueConfig` still reads from the hardcoded system path.

**Fix:** `GlueConfig.load()` should accept the config file path as a parameter (from `GlueHome` or `Paths`).

---

### ARCH-004: `SkillRegistry` ignores `GlueHome.skillsDir`, re-derives HOME **[RESOLVED]**

**Severity:** Medium
**Files:** `lib/src/skills/skill_registry.dart:59-63`, `lib/src/storage/glue_home.dart:14`

`GlueHome.skillsDir` exists but is never used. `SkillRegistry.discover()` constructs `~/.glue/skills` from `Platform.environment['HOME']` independently.

**Fix:** Pass `GlueHome.skillsDir` (or `Paths.skillsDir`) into `SkillRegistry.discover()`.

---

### ARCH-005: Title generation silently skipped for non-Anthropic providers **[RESOLVED]**

**Severity:** Medium
**Files:** `lib/src/app.dart`, `lib/src/llm/title_generator.dart`

Title generation now uses `LlmClientFactory` + `TitleGenerator(LlmClient)` and resolves provider/model from config instead of hardcoding Anthropic HTTP calls.

**Fix:** Use the currently configured provider's client for title generation, or add a configurable `title_model` fallback.

---

## Dead Code

### DEAD-001: `ConfigStore` dead fields — `defaultProvider`, `defaultModel`, `debug` **[RESOLVED]**

**Severity:** High
**Files:** `lib/src/storage/config_store.dart:69-87`

Only `trustedTools` is read in production (`app.dart:428`). The other three getters are never called. The documented "config.json overrides config.yaml" mechanism does not exist. Additionally, `ConfigStore.debug` defaults to `true` while `ObservabilityConfig.debug` defaults to `false` — contradictory defaults for the same concept.

**Fix:** Remove dead getters. If override behavior is wanted later, wire it up properly through `GlueConfig.load()`.

---

### DEAD-002: `DebugLogger` is unused in production **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/storage/debug_logger.dart`

Replaced by OTel tracing (`ObservedLlmClient`, `FileSink`). Only referenced in tests and a planning doc.

**Fix:** Delete the file and its test.

---

### DEAD-003: `generateSessionId()` is never called **[RESOLVED]**

**Severity:** Medium
**Files:** `lib/src/storage/session_id.dart`

The proper SHA-256 session ID generator exists but is bypassed. `app.dart` has the same `millisecondsSinceEpoch-microsecond` pattern inlined at three locations (lines 297, 791, 1054), which produces variable-length, weaker IDs. The inline versions also call `DateTime.now()` twice per expression.

**Fix:** Replace all three inline sites with `generateSessionId()`, or delete `session_id.dart` if the inline format is preferred.

---

### DEAD-004: `SkillMeta.allowedTools` parsed but never enforced **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/skills/skill_parser.dart:24,35,120,135`

The `allowed-tools` frontmatter field is parsed into `SkillMeta.allowedTools` but no code reads it. `SkillActivation` injects skill content without consulting the allowlist.

**Fix:** Either enforce it in the agent tool pipeline or remove the field. **[IN-FLIGHT]** — skill system being refactored in missoula/salvador workspaces.

---

### DEAD-005: `sessionStore: null` discards work in `App.create()` **[RESOLVED]**

**Severity:** Medium
**Files:** `lib/src/app.dart`, `lib/src/core/service_locator.dart`

`ServiceLocator` now constructs a startup `SessionStore` and `App.create()` passes it into `App`, so observability/resource session IDs and runtime session IDs stay aligned.

**Fix:** Pass the constructed `SessionStore` through instead of discarding it.

---

## Duplication

### DUP-001: API key resolution duplicated 3 times **[RESOLVED]**

**Severity:** Medium
**Files:** `lib/src/llm/llm_factory.dart:72-76,93-97`, `lib/src/agent/agent_manager.dart:190-194`

Identical `switch (provider) => config.xApiKey ?? ''` logic in three places. Adding a new provider requires updating all three.

**Fix:** Add an `apiKeyFor(LlmProvider)` method to `GlueConfig`.

---

### DUP-002: Trusted tool lists hardcoded in two places **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/app.dart`, `lib/src/agent/agent_manager.dart`, `lib/src/orchestrator/tool_permissions.dart`

Tool permission presets now come from shared `ToolPermissions` constants. `App` uses `ToolPermissions.defaultTrustedTools` and `AgentManager` uses `ToolPermissions.subagentSafeTools` (via the existing alias), so the sets are centralized.

**Fix:** Define a single `ToolPermissions` class or constant set that both consume.

---

### DUP-003: `mistralApiKey` and `openaiApiKey` resolved twice with different env coverage **[RESOLVED]**

**Severity:** Medium
**Files:** `lib/src/config/glue_config.dart:194-200,307-310`

`mistralKey` (for LLM, line 198) reads from `MISTRAL_API_KEY` or `GLUE_MISTRAL_API_KEY` or YAML. `mistralApiKey` (for PDF OCR, line 307) only reads from `MISTRAL_API_KEY` or YAML. A user who sets `GLUE_MISTRAL_API_KEY` will find LLM calls work but OCR fails silently.

**Fix:** Resolve each API key once and pass it to both subsystems.

---

### DUP-004: `version` constant duplicated **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/config/constants.dart:6`, `bin/glue.dart:11`

Two independent `'0.1.0'` strings. Neither imports the other.

**Fix:** `bin/glue.dart` should import `AppConstants.version`.

---

## Naming & Consistency

### NAME-001: `config.json` naming confusion **[RESOLVED]**

**Severity:** Medium
**Files:** `lib/src/core/environment.dart`, `lib/src/storage/config_store.dart`

`config.yaml` and `config.json` side-by-side in `~/.glue/` was confusing. They serve different purposes (user config vs machine-managed preferences). The JSON file stores runtime preference state (`trusted_tools`).

**Fix:** Runtime preferences now use `~/.glue/preferences.json`. Legacy
`~/.glue/config.json` is still read as a fallback when the new file is missing,
and subsequent writes go to `preferences.json`.

---

### NAME-002: Model identity uses 4 different names **[RESOLVED]**

**Severity:** Medium
**Files:** `lib/src/config/glue_config.dart`, `lib/src/config/model_registry.dart`, `lib/src/agent/agent_core.dart`, `lib/src/app.dart`

`modelName`/`_modelName` were standardized to `modelId` in runtime app/agent
paths. `GlueConfig` intentionally keeps `model` for config schema
compatibility.

**Fix:** Keep `modelId` as runtime naming convention and retain
`GlueConfig.model` as the external config field.

---

### NAME-003: `isConfigured` vs `isAvailable` for the same concept **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/web/search/provider.dart`, `lib/src/web/browser/browser_endpoint.dart`, `lib/src/web/browser/providers/*`

Search and browser providers now both use `isConfigured` as the canonical property name.

**Fix:** Browser providers and tests were updated to `isConfigured`. A deprecated `isAvailable` alias remains on `BrowserEndpointProvider` for compatibility.

---

### NAME-004: Browser domain mixes "backend" and "provider" **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/web/browser/browser_config.dart`, `lib/src/web/browser/browser_endpoint.dart`, `docs/reference/config-yaml.md`

The browser domain now explicitly documents the distinction:
`backend` = runtime environment selection (local/docker/cloud), and
`provider` = provisioning implementation for that backend.

**Fix:** Documented the backend/provider terminology directly in code and docs.

---

### NAME-005: Enum suffix conventions inconsistent **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/config/glue_config.dart`, `lib/src/web/web_config.dart`, `lib/src/web/browser/browser_config.dart`

Convention is now documented:

- runtime capability interfaces use `*Provider` (e.g. `WebSearchProvider`)
- selector enums use `*ProviderType` where needed to avoid naming collisions
- browser keeps `Backend` terminology for runtime environment selection (see NAME-004)
- `LlmProviderType` alias exists for consistency with selector naming.

**Fix:** Documented naming convention and added `LlmProviderType` alias.

---

### NAME-006: `ToolCallDelta` is misleadingly named **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/agent/agent_core.dart`, `lib/src/llm/*.dart`, tests

The event is now named `ToolCallComplete` throughout runtime code. A deprecated `ToolCallDelta` alias remains for compatibility.

**Fix:** Rename to `ToolCallComplete` (touches ~50 references).

---

### NAME-007: `ShellMode` parsed via silent fallback **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/shell/shell_config.dart`, `lib/src/config/glue_config.dart`

`ShellMode.fromString()` now matches `'non_interactive'` explicitly and supports an invalid-value callback. `GlueConfig.load()` wires this to a warning message before falling back to non-interactive mode.

**Fix:** Match `'non_interactive'` explicitly, log a warning on unrecognized values.

---

### NAME-008: Span JSON mixes camelCase with snake_case **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/observability/observability.dart`, `test/observability/*`

`ObservabilitySpan.toMap()` now emits snake_case keys consistently
(`trace_id`, `span_id`, `parent_span_id`, `start_time`, `end_time`,
`duration_ms`).

**Fix:** Standardize internal span JSON serialization to snake_case.

---

## Storage

### STOR-001: `SessionStore` and `SessionState` lack atomic writes **[RESOLVED]**

**Severity:** Medium
**Files:** `lib/src/storage/session_store.dart:133-134`, `lib/src/storage/session_state.dart:71`

Only `ConfigStore` does tmp-file-then-rename. `SessionStore._writeMeta()` and `SessionState._persist()` write directly. A crash mid-write corrupts the file.

**Fix:** Extract shared atomic-write helper; use it in all storage classes.

---

### STOR-002: `SessionState` version field has no migration path **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/storage/session_state.dart:72`

`SessionState.load()` now parses `version` and safely ignores unknown future schema versions instead of attempting a naive read.

**Fix:** Either add version checking or remove the field until needed.

---

### STOR-003: `SessionState` created in `App.create()` but not stored **[RESOLVED]**

**Severity:** Medium
**Files:** `lib/src/app.dart`, `lib/src/core/service_locator.dart`

`ServiceLocator` now passes the loaded `SessionState` through `AppServices` into `App`, so runtime code has a retained reference instead of discarding it after executor creation.

**Fix:** Store `SessionState` as an `App` field.

---

## Bugs

### BUG-001: Tool confirmation happens after full argument generation (wasted tokens) **[RESOLVED]**

**Severity:** Medium
**Files:** `lib/src/agent/agent_core.dart`, `lib/src/app_agent_orchestration.dart`

Early confirmation runs on `AgentToolCallPending` (`ToolCallStart`) before
arguments are complete, and declining can cancel the active stream immediately.

Current built-in providers (`anthropic`, `openai`, `ollama`) all emit
`ToolCallStart`, so the original wasteful full-argument confirmation behavior
is resolved for supported providers.

**Fix:** Keep pending-time confirmation as the canonical path.

---

### BUG-002: `--resume` creates an empty session immediately **[RESOLVED]**

**Severity:** Medium
**Files:** `lib/src/core/service_locator.dart`

`ServiceLocator.create()` used to eagerly construct a `SessionStore` at startup, which wrote `meta.json` to disk before anyone knew whether the user was resuming or starting fresh. With `--resume`, that stray session would then outrank the user's real last session for `--continue`.

**Fix:** `ServiceLocator.create()` no longer creates a `SessionStore`. `AppServices.sessionStore` is nullable; `SessionManager.ensureSessionStore()` creates the real store lazily on resume or on the user's first message. Covered by `test/core/service_locator_test.dart`.

---

### BUG-003: Bash mode has no shell tab-completion **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/app_terminal_event_router.dart`, `lib/src/shell/shell_completer.dart`, `lib/src/ui/shell_autocomplete.dart`

Bash mode now routes `requestCompletion` to `ShellCompleter` via `ShellAutocomplete`, with keyboard navigation and accept/dismiss behavior wired in the terminal event router.

**Fix:** Add a `ShellCompleter` that uses `fish complete -C` for fish, `bash -c 'compgen ...'` for others. Wire into existing overlay system.

---

### BUG-004: Session meta not updated on model switch **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/app.dart:1317-1331`, `lib/src/storage/session_store.dart:13-14`

When the user switches models mid-session via `/model`, `_config` and `_modelName` update but `_sessionStore.meta.model` still reflects the model at session-creation time. Session history shows the wrong model for sessions where the user switched.

**Fix:** Update `SessionMeta.model` and `SessionMeta.provider` in `_switchToModelEntry()`.

---

## Documentation

### DOC-001: `config-yaml.md` massively incomplete **[RESOLVED]**

**Severity:** High
**Files:** `docs/reference/config-yaml.md`

`docs/reference/config-yaml.md` was rewritten to match `GlueConfig.load()` and now documents implemented sections, valid values, and environment overrides without claiming unsupported CLI flags.

**Fix:** Audit `GlueConfig.load()` and document every field that is actually read.

---

### DOC-002: `config-store-json.md` describes features that don't exist **[RESOLVED]**

**Severity:** High
**Files:** `docs/reference/config-store-json.md`

`docs/reference/config-store-json.md` now reflects the actual runtime schema (`trusted_tools`) and no longer claims unsupported provider/model override behavior.

**Fix:** Rewrite to document what actually exists (just `trusted_tools`).

---

### DOC-003: `session-storage.md` missing fields **[RESOLVED]**

**Severity:** Medium
**Files:** `docs/reference/session-storage.md`

`docs/reference/session-storage.md` now documents `SessionMeta` and `SessionState` fields in current code, including `forked_from` and `browser.container_ids`.

**Fix:** Add missing fields to the schema docs.

---

### DOC-004: `ollama.base_url` documented but not implemented **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/config/glue_config.dart`, `test/config/glue_config_test.dart`

`GlueConfig.load()` now reads `ollama.base_url` from YAML and supports environment overrides via `GLUE_OLLAMA_BASE_URL` / `OLLAMA_BASE_URL`.

**Fix:** Either wire up the YAML/env reading or remove from docs.

---

### DOC-005: Unimplemented plans still in docs/plans/ — **[RESOLVED]**

**Severity:** Low
**Files:** `docs/plans/`

27 implemented plans moved to `docs/plans/done/`. Only `2026-02-27-acp-webui.md` remains as active/unimplemented.

---

## Integration & Merge

### MERGE-001: PR #18 (cli-prompt-arg) conflicts with main **[RESOLVED]**

**Severity:** High
**Files:** `bin/glue.dart`, `lib/src/app.dart`, `lib/src/config/glue_config.dart`

The PR #18 feature set is already present in current mainline code paths:
prompt args, print/json output modes, resume-by-ID, and corrected
`GlueConfig.copyWith()` field preservation.

**Fix:** No branch rebase needed; treat PR #18 as superseded by integrated work.

---

### MERGE-002: PR #20 (Ollama model list) superseded by main **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/app.dart`

PR #20's goal (dynamic Ollama model fetching) already exists on main via commit `c8e3b3c`. PR #20 also removes `ModelDiscovery` caching and `SkillRuntime`, which we want to keep.

**Fix:** Close PR #20 with explanation.

---

### MERGE-003: Salvador workspace has uncommitted WIP **[RESOLVED]**

**Severity:** High
**Files:** `lib/src/session/session_manager.dart`, `lib/src/llm/message_mapper.dart`, `lib/src/observability/langfuse_sink.dart`, `lib/src/observability/otel_sink.dart`, `lib/src/app_models.dart`

Most of the identified Salvador fixes now exist in this codebase:

- Session replay with proper tool_call/tool_result grouping (fixes broken conversation replay)
- Orphaned tool_result filtering in message_mapper (prevents Anthropic API 400 errors)
- `onError` callback for Langfuse/OTel sinks (replaces noisy stderr writes)
- SubagentEntry class with JSON pretty-printing for expandable output

Audit snapshot (2026-03-05):

- Branch `HelgeSverre/dart-devtools-ideas` (`9e749ff`) is not merged into
  `main` as a branch, but the targeted fixes listed above are already present
  on mainline code paths.
- Remaining branch-only commits are mainly iterative DevTools/docs/formatting
  history and do not currently require cherry-pick.
- Local stale branch `HelgeSverre/dart-devtools-ideas` was deleted.

**Fix:** Treat branch-only leftovers as archived; keep mainline as source of truth.

---

### MERGE-004: Remaining unmerged feature branches without PRs **[RESOLVED]**

**Severity:** Medium

Branches already cleaned up locally:

- Deleted merged/closed branches: `fix-slash-cmd-during-work`, `session-id-table-layout`, `session-thread-titles`, `bash-tab-completion`, `cli-completions`, `update-website-license`, `clickable-links-ui`, `history-dialog-panel`, `multiline-prompt-input`.
- Previously targeted feature work is now present on mainline code paths (`clickable-links-ui`, `multiline-prompt-input`, and history/panel-stacking foundations), so manual re-apply is no longer required.

Remaining local non-main branches now correspond to active linked worktrees,
not stale backlog branches:

- `experiment/docked-panel` — active experiment worktree with uncommitted WIP.
- `comment-cleanup` — active external worktree (already merged content-wise).

Audit snapshot (2026-03-05):

- `HelgeSverre/sema-wasm-integration`: no local branch remains.
- `comment-cleanup` (`1e06190`): fully merged into `main`; only retained due
  active external worktree.
- `experiment/docked-panel` (`f607cf4`, `1bdd03f`, `1d5c051`): not merged and
  still experimental and intentionally isolated in its own worktree.
- `HelgeSverre/dart-devtools-ideas` (`9e749ff`): local branch deleted after
  audit; no remaining action.

**Fix:** Treat active worktree branches as intentional and exclude them from stale-branch cleanup until those worktrees are explicitly retired.

---

## Release Blockers

### REL-001: No LICENSE file **[RESOLVED]**

**Severity:** Critical
**Files:** repo root, `cli/LICENSE`

MIT license files exist at repo root and `cli/LICENSE`, covering release and pub.dev packaging expectations.

**Fix:** Add MIT license file at repo root and `cli/LICENSE`.

---

### REL-002: `pubspec.yaml` incomplete for pub.dev **[RESOLVED]**

**Severity:** High
**Files:** `cli/pubspec.yaml`

`pubspec.yaml` now includes release metadata fields (`homepage`, `repository`, `issue_tracker`, `topics`, `executables`) required for a strong pub.dev score.

**Fix:** Add `repository: https://github.com/HelgeSverre/glue`, `topics: [cli, ai, llm, agent, terminal]`, `executables: {glue: glue}`.

---

### REL-003: No CONTRIBUTING.md or SECURITY.md **[RESOLVED]**

**Severity:** Medium
**Files:** `CONTRIBUTING.md`, `SECURITY.md`

Contributor and security disclosure docs now exist at repository root.

**Fix:** Create both files before public announcement. See `RELEASE.md` for checklist.

---

## Portability

### PORT-001: "Copy to clipboard" uses macOS-specific `pbcopy` **[RESOLVED]**

**Severity:** Low
**Files:** `lib/src/ui/panel_controller.dart`

The history action panel now detects the OS and uses clipboard command fallbacks: `pbcopy` (macOS), `clip` (Windows), and `wl-copy`/`xclip`/`xsel` (Linux). When none are available, Glue shows a failure message instead of pretending copy succeeded.

**Fix:** Use a cross-platform clipboard package or detect the OS and use the appropriate command.

---

## Configuration

### CONF-001: `GlueConfig.load()` does not support custom base paths **[RESOLVED]**

**Severity:** Medium
**Files:** `lib/src/config/glue_config.dart`, `test/config/glue_config_test.dart`

`GlueConfig.load()` now accepts an explicit `configPath` override (in addition to injected `Environment`), allowing custom configuration locations without depending on `HOME` path tricks.

**Fix:** Add an optional `basePath` or `configPath` parameter to `GlueConfig.load()`.
