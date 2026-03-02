# Known Issues

Consolidated issue tracker. Last updated: 2026-03-02.

Items marked **[IN-FLIGHT]** are addressed by open PRs or conductor workspaces.
Items marked **[RESOLVED]** have been fixed but are kept for reference until verified.

---

## Architecture

### ARCH-001: `app.dart` is a 2,500-line god class

**Severity:** High
**Files:** `lib/src/app.dart`

The `App` class handles: terminal events, agent orchestration, permissions, bash mode, session management, slash commands, 7 UI panels, title generation, rendering, splash animation, and spinner state. 14 constructor parameters, 35+ private fields, `create()` factory is 173 lines alone.

**Fix:** Extract into focused modules: `PermissionManager`, `SessionController`, `PanelManager`, `SlashCommandHandler`, `RenderPipeline`.

---

### ARCH-002: `GlueHome` instantiated 8 times with no shared instance

**Severity:** Low
**Files:** `lib/src/app.dart` (lines 294, 489, 691, 800, 822, 878, 1036, 1939)

`GlueHome()` is created ad-hoc at every call site. No single owner, no way to override for tests without environment monkeypatching.

**Fix:** Create a `Paths` utility (or add path getters to `GlueConfig`) that is instantiated once and injected. All path resolution flows through one object.

---

### ARCH-003: `GlueConfig.load()` hardcodes `~/.glue/config.yaml` path

**Severity:** Medium
**Files:** `lib/src/config/glue_config.dart:161-163`

Bypasses `GlueHome` entirely with `'${Platform.environment['HOME']}/.glue/config.yaml'`. If `GlueHome.basePath` is ever overridden, `GlueConfig` still reads from the hardcoded system path.

**Fix:** `GlueConfig.load()` should accept the config file path as a parameter (from `GlueHome` or `Paths`).

---

### ARCH-004: `SkillRegistry` ignores `GlueHome.skillsDir`, re-derives HOME

**Severity:** Medium
**Files:** `lib/src/skills/skill_registry.dart:59-63`, `lib/src/storage/glue_home.dart:14`

`GlueHome.skillsDir` exists but is never used. `SkillRegistry.discover()` constructs `~/.glue/skills` from `Platform.environment['HOME']` independently.

**Fix:** Pass `GlueHome.skillsDir` (or `Paths.skillsDir`) into `SkillRegistry.discover()`.

---

### ARCH-005: Title generation silently skipped for non-Anthropic providers

**Severity:** Medium
**Files:** `lib/src/app.dart:753-780`

`_generateTitle()` checks for `anthropicApiKey` and returns early if absent. Users on OpenAI/Ollama/Mistral get no session titles with no indication why.

**Fix:** Use the currently configured provider's client for title generation, or add a configurable `title_model` fallback.

---

## Dead Code

### DEAD-001: `ConfigStore` dead fields — `defaultProvider`, `defaultModel`, `debug`

**Severity:** High
**Files:** `lib/src/storage/config_store.dart:69-87`

Only `trustedTools` is read in production (`app.dart:428`). The other three getters are never called. The documented "config.json overrides config.yaml" mechanism does not exist. Additionally, `ConfigStore.debug` defaults to `true` while `ObservabilityConfig.debug` defaults to `false` — contradictory defaults for the same concept.

**Fix:** Remove dead getters. If override behavior is wanted later, wire it up properly through `GlueConfig.load()`.

---

### DEAD-002: `DebugLogger` is unused in production

**Severity:** Low
**Files:** `lib/src/storage/debug_logger.dart`

Replaced by OTel tracing (`ObservedLlmClient`, `FileSink`). Only referenced in tests and a planning doc.

**Fix:** Delete the file and its test.

---

### DEAD-003: `generateSessionId()` is never called

**Severity:** Medium
**Files:** `lib/src/storage/session_id.dart`

The proper SHA-256 session ID generator exists but is bypassed. `app.dart` has the same `millisecondsSinceEpoch-microsecond` pattern inlined at three locations (lines 297, 791, 1054), which produces variable-length, weaker IDs. The inline versions also call `DateTime.now()` twice per expression.

**Fix:** Replace all three inline sites with `generateSessionId()`, or delete `session_id.dart` if the inline format is preferred.

---

### DEAD-004: `SkillMeta.allowedTools` parsed but never enforced

**Severity:** Low
**Files:** `lib/src/skills/skill_parser.dart:24,35,120,135`

The `allowed-tools` frontmatter field is parsed into `SkillMeta.allowedTools` but no code reads it. `SkillActivation` injects skill content without consulting the allowlist.

**Fix:** Either enforce it in the agent tool pipeline or remove the field. **[IN-FLIGHT]** — skill system being refactored in missoula/salvador workspaces.

---

### DEAD-005: `sessionStore: null` discards work in `App.create()`

**Severity:** Medium
**Files:** `lib/src/app.dart:296-349, 429`

`App.create()` builds a `SessionMeta` and session directory, then passes `sessionStore: null` to the `App` constructor. The session store is re-created lazily on first user message. The initial session ID (used for observability `resourceAttrs`) may diverge from the actual session.

**Fix:** Pass the constructed `SessionStore` through instead of discarding it.

---

## Duplication

### DUP-001: API key resolution duplicated 3 times

**Severity:** Medium
**Files:** `lib/src/llm/llm_factory.dart:72-76,93-97`, `lib/src/agent/agent_manager.dart:190-194`

Identical `switch (provider) => config.xApiKey ?? ''` logic in three places. Adding a new provider requires updating all three.

**Fix:** Add an `apiKeyFor(LlmProvider)` method to `GlueConfig`.

---

### DUP-002: Trusted tool lists hardcoded in two places

**Severity:** Low
**Files:** `lib/src/app.dart:176-186`, `lib/src/agent/agent_manager.dart:14`

`App._autoApprovedTools` and `AgentManager.safeSubagentTools` are related but not derived from each other. Neither references the other.

**Fix:** Define a single `ToolPermissions` class or constant set that both consume.

---

### DUP-003: `mistralApiKey` and `openaiApiKey` resolved twice with different env coverage

**Severity:** Medium
**Files:** `lib/src/config/glue_config.dart:194-200,307-310`

`mistralKey` (for LLM, line 198) reads from `MISTRAL_API_KEY` or `GLUE_MISTRAL_API_KEY` or YAML. `mistralApiKey` (for PDF OCR, line 307) only reads from `MISTRAL_API_KEY` or YAML. A user who sets `GLUE_MISTRAL_API_KEY` will find LLM calls work but OCR fails silently.

**Fix:** Resolve each API key once and pass it to both subsystems.

---

### DUP-004: `version` constant duplicated

**Severity:** Low
**Files:** `lib/src/config/constants.dart:6`, `bin/glue.dart:11`

Two independent `'0.1.0'` strings. Neither imports the other.

**Fix:** `bin/glue.dart` should import `AppConstants.version`.

---

## Naming & Consistency

### NAME-001: `config.json` naming confusion

**Severity:** Medium
**Files:** `lib/src/storage/config_store.dart`, `lib/src/storage/glue_home.dart:11`

Having `config.yaml` and `config.json` side-by-side in `~/.glue/` is confusing. They serve different purposes (user config vs machine-managed preferences). The JSON file currently only stores `trusted_tools` in practice.

**Fix:** Rename to better reflect purpose. Consider consolidating with `config.yaml` if the override mechanism is not needed. See DEAD-001.

---

### NAME-002: Model identity uses 4 different names

**Severity:** Medium
**Files:** `lib/src/config/glue_config.dart:50`, `lib/src/config/model_registry.dart:15`, `lib/src/agent/agent_core.dart:217`, `lib/src/app.dart:171`

The same API model string is called `model`, `modelId`, `modelName`, and `_modelName` in different files.

**Fix:** Standardize on `modelId` everywhere.

---

### NAME-003: `isConfigured` vs `isAvailable` for the same concept

**Severity:** Low
**Files:** `lib/src/web/search/provider.dart:5`, `lib/src/web/browser/browser_endpoint.dart:34`

Search providers use `isConfigured`, browser providers use `isAvailable`. Same boolean concept.

**Fix:** Pick one name and use it consistently.

---

### NAME-004: Browser domain mixes "backend" and "provider"

**Severity:** Low
**Files:** `lib/src/web/browser/browser_config.dart:4`, `lib/src/web/browser/browser_endpoint.dart:32`

The enum is `BrowserBackend`, the interface is `BrowserEndpointProvider`, the config field is `backend`. Search domain consistently uses "provider" everywhere.

**Fix:** Align browser domain to use "provider" consistently, or document the distinction.

---

### NAME-005: Enum suffix conventions inconsistent

**Severity:** Low
**Files:** `lib/src/config/glue_config.dart:23`, `lib/src/web/web_config.dart:22,61`, `lib/src/web/browser/browser_config.dart:4`

`LlmProvider` (no suffix), `WebSearchProviderType` (`Type` suffix), `OcrProviderType` (`Type` suffix), `BrowserBackend` (different word entirely).

**Fix:** Pick a convention (`XxxProvider` or `XxxProviderType`) and apply it.

---

### NAME-006: `ToolCallDelta` is misleadingly named

**Severity:** Low
**Files:** `lib/src/agent/agent_core.dart:84-90`

Already has a TODO comment acknowledging it should be `ToolCallComplete`. The "Delta" name suggests incremental update but it carries the fully-formed call.

**Fix:** Rename to `ToolCallComplete` (touches ~50 references).

---

### NAME-007: `ShellMode` parsed via silent fallback

**Severity:** Low
**Files:** `lib/src/shell/shell_config.dart:16-20`

`'non_interactive'` is never explicitly matched — it works only because unrecognized strings fall through to the default. A typo like `'noninteractive'` also silently succeeds.

**Fix:** Match `'non_interactive'` explicitly, log a warning on unrecognized values.

---

### NAME-008: Span JSON mixes camelCase with snake_case

**Severity:** Low
**Files:** `lib/src/observability/observability.dart:48-57`

`ObservabilitySpan.toMap()` emits camelCase (`traceId`, `spanId`) except `duration_ms` which is snake_case. Storage layer uses snake_case consistently.

**Fix:** Pick one convention for internal JSON serialization.

---

## Storage

### STOR-001: `SessionStore` and `SessionState` lack atomic writes

**Severity:** Medium
**Files:** `lib/src/storage/session_store.dart:133-134`, `lib/src/storage/session_state.dart:71`

Only `ConfigStore` does tmp-file-then-rename. `SessionStore._writeMeta()` and `SessionState._persist()` write directly. A crash mid-write corrupts the file.

**Fix:** Extract shared atomic-write helper; use it in all storage classes.

---

### STOR-002: `SessionState` version field has no migration path

**Severity:** Low
**Files:** `lib/src/storage/session_state.dart:72`

`_persist()` writes `'version': 1` but `load()` reads naively regardless of version. No upgrade logic exists.

**Fix:** Either add version checking or remove the field until needed.

---

### STOR-003: `SessionState` created in `App.create()` but not stored

**Severity:** Medium
**Files:** `lib/src/app.dart:350-355`

`SessionState` is loaded, its docker mounts are passed to `ExecutorFactory`, then the instance is discarded. Any subsequent `addMount()` calls would need a reference that doesn't exist.

**Fix:** Store `SessionState` as an `App` field.

---

## Bugs

### BUG-001: Tool confirmation happens after full argument generation (wasted tokens)

**Severity:** Medium
**Files:** `lib/src/llm/anthropic_client.dart:98-137`, `lib/src/agent/agent_core.dart:238-256`, `lib/src/app.dart:1310-1369`

When the agent calls a tool requiring confirmation (`write_file`, `edit_file`, `bash`), the LLM streams the entire argument payload before the user is asked for permission. Declining wastes all generated tokens. This is an industry-wide pattern (Claude Code, OpenCode, Ampcode all have the same behavior), but the `ToolCallStart` event provides an early intervention point.

**Fix:** Show a lightweight pre-confirmation on `AgentToolCallPending` for non-auto-approved tools. If declined, cancel the LLM stream before arguments finish generating.

---

### BUG-002: `--resume` creates an empty session immediately

**Severity:** Medium
**Files:** `lib/src/app.dart:486-501, 811-825`

When launching with `--resume`, a new empty session is created before the user selects which session to resume. If the user quits the resume dialog, this empty session becomes the most recent one, causing `--continue` to resume it instead of the user's actual last session.

**Fix:** Defer session store creation until after the resume dialog resolves.

---

### BUG-003: Bash mode has no shell tab-completion

**Severity:** Low
**Files:** `lib/src/app.dart` (bash mode), `lib/src/input/line_editor.dart`

In bash mode (`!` prefix), Tab does nothing. `LineEditor` emits `requestCompletion` but only slash-command and @-file completions are wired. Shell completions (commands, paths, flags) are unavailable.

**Fix:** Add a `ShellCompleter` that uses `fish complete -C` for fish, `bash -c 'compgen ...'` for others. Wire into existing overlay system.

---

### BUG-004: Session meta not updated on model switch

**Severity:** Low
**Files:** `lib/src/app.dart:1317-1331`, `lib/src/storage/session_store.dart:13-14`

When the user switches models mid-session via `/model`, `_config` and `_modelName` update but `_sessionStore.meta.model` still reflects the model at session-creation time. Session history shows the wrong model for sessions where the user switched.

**Fix:** Update `SessionMeta.model` and `SessionMeta.provider` in `_switchToModelEntry()`.

---

## Documentation

### DOC-001: `config-yaml.md` massively incomplete

**Severity:** High
**Files:** `docs/reference/config-yaml.md`

10+ real config sections are undocumented: `web.fetch`, `web.search`, `web.pdf`, `web.browser`, `telemetry.langfuse`, `telemetry.otel`, `permission_mode`, `skills.paths`, `debug`, `title_model`, `mistral`. All docker/shell CLI flags (`--docker`, `--shell`, etc.) are documented but don't exist in `bin/glue.dart`.

**Fix:** Audit `GlueConfig.load()` and document every field that is actually read.

---

### DOC-002: `config-store-json.md` describes features that don't exist

**Severity:** High
**Files:** `docs/reference/config-store-json.md`

Claims `config.json` overrides `config.yaml` for `default_provider`/`default_model` — this mechanism is not implemented. References `/set provider` command which doesn't exist. See DEAD-001.

**Fix:** Rewrite to document what actually exists (just `trusted_tools`).

---

### DOC-003: `session-storage.md` missing fields

**Severity:** Medium
**Files:** `docs/reference/session-storage.md`

`SessionState`'s `browser.container_ids` field and `SessionMeta`'s `forked_from` field are undocumented.

**Fix:** Add missing fields to the schema docs.

---

### DOC-004: `ollama.base_url` documented but not implemented

**Severity:** Low
**Files:** `docs/reference/config-yaml.md`, `lib/src/config/glue_config.dart`

The YAML schema shows `ollama.base_url` as configurable, but `GlueConfig.load()` never reads it. The field exists on the class with a hardcoded default.

**Fix:** Either wire up the YAML/env reading or remove from docs.

---

### DOC-005: Unimplemented plans still in docs/plans/ — **[RESOLVED]**

**Severity:** Low
**Files:** `docs/plans/`

27 implemented plans moved to `docs/plans/done/`. Only `2026-02-27-acp-webui.md` remains as active/unimplemented.

---

## Integration & Merge

### MERGE-001: PR #18 (cli-prompt-arg) conflicts with main **[IN-FLIGHT]**

**Severity:** High
**Files:** `bin/glue.dart`, `lib/src/app.dart`, `lib/src/config/glue_config.dart`

PR #18 adds prompt args, print mode, model aliases, JSON output, resume-by-ID, and removes `--provider` flag. Conflicts in `app.dart` and `glue.dart` due to main divergence. `GlueConfig.copyWith()` drops `titleModel`, `skillPaths`, `permissionMode` fields — must be restored.

**Fix:** Rebase onto main, resolve conflicts, restore copyWith fields, verify tests.

---

### MERGE-002: PR #20 (Ollama model list) superseded by main

**Severity:** Low
**Files:** `lib/src/app.dart`

PR #20's goal (dynamic Ollama model fetching) already exists on main via commit `c8e3b3c`. PR #20 also removes `ModelDiscovery` caching and `SkillRuntime`, which we want to keep.

**Fix:** Close PR #20 with explanation.

---

### MERGE-003: Salvador workspace has uncommitted WIP **[IN-FLIGHT]**

**Severity:** High
**Files:** `lib/src/app.dart`, `lib/src/llm/message_mapper.dart`, `lib/src/observability/langfuse_sink.dart`, `lib/src/observability/otel_sink.dart`

Uncommitted changes in `/Users/helge/conductor/workspaces/glue/salvador/cli` on the `dart-devtools-ideas` branch. Contains:

- Session replay with proper tool_call/tool_result grouping (fixes broken conversation replay)
- Orphaned tool_result filtering in message_mapper (prevents Anthropic API 400 errors)
- `onError` callback for Langfuse/OTel sinks (replaces noisy stderr writes)
- SubagentEntry class with JSON pretty-printing for expandable output
- Comprehensive tests for all changes

**Fix:** Commit, create branch from main, cherry-pick changes, merge.

---

### MERGE-004: 8 unmerged feature branches without PRs

**Severity:** Medium

Complete, tested features sitting in branches with no PRs:

- `clickable-links-ui` (+7 commits) — OSC 8 terminal hyperlinks
- `fix-slash-cmd-during-work` (+1) — slash commands during streaming
- `history-dialog-panel` (+4) — history browser, panel stacking, ANSI styling API
- `multiline-prompt-input` (+2) — Shift+Enter multiline, bracketed paste
- `session-id-table-layout` (+1) — short session IDs, table layout refactor
- `session-thread-titles` (+2) — auto-generated session titles via Haiku
- `update-website-license` (+1) — website MIT license, nav, docs layout
- `experiment/docked-panel` (+3) — dockable panel system, tool description injection

**Fix:** Create PRs or merge directly after the primary PR consolidation is complete. Two branches (`bash-tab-completion`, `cli-completions`) appear incomplete/abandoned and should be evaluated for closure.

---

## Release Blockers

### REL-001: No LICENSE file

**Severity:** Critical
**Files:** repo root, `cli/`

No LICENSE file exists anywhere in the repository. Required for open-source release and pub.dev publishing.

**Fix:** Add MIT license file at repo root and `cli/LICENSE`.

---

### REL-002: `pubspec.yaml` incomplete for pub.dev

**Severity:** High
**Files:** `cli/pubspec.yaml`

Missing fields: `homepage`, `repository`, `issue_tracker`, `topics`, `executables`. pub.dev score estimated ~90/160 without these. With fixes: ~130-140/160.

**Fix:** Add `repository: https://github.com/HelgeSverre/glue`, `topics: [cli, ai, llm, agent, terminal]`, `executables: {glue: glue}`.

---

### REL-003: No CONTRIBUTING.md or SECURITY.md

**Severity:** Medium

Standard open-source governance files are missing. Expected by contributors and security researchers.

**Fix:** Create both files before public announcement. See `RELEASE.md` for checklist.

---

## Portability

### PORT-001: "Copy to clipboard" uses macOS-specific `pbcopy`

**Severity:** Low
**Files:** `lib/src/app.dart:1262`

The history action panel uses `Process.start('pbcopy', [])` to copy text to the clipboard. This command only exists on macOS. Linux (xclip/xsel) and Windows (clip.exe) users will find this feature non-functional.

**Fix:** Use a cross-platform clipboard package or detect the OS and use the appropriate command.

---

## Configuration

### CONF-001: `GlueConfig.load()` does not support custom base paths

**Severity:** Medium
**Files:** `lib/src/config/glue_config.dart`

Unlike `GlueHome`, which accepts an optional `basePath`, `GlueConfig.load()` hardcodes the look-up of `~/.glue/config.yaml`. This makes it impossible to use Glue with a different configuration directory (e.g., for integration tests) without mocking the `HOME` environment variable.

**Fix:** Add an optional `basePath` or `configPath` parameter to `GlueConfig.load()`.

