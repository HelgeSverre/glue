# Glue Simplification Removal Plan

Status: proposed
Owner: implementation agent
Date: 2026-04-19

## Goal

Reduce Glue's policy and telemetry complexity without walking back the parts
that are still strategically useful: panels, Docker/runtime isolation, web
research/browser automation, and the terminal-first application shell.

The current pain is not that Glue has a TUI. The pain is that the app has too
many overlapping behavior systems:

- UI interaction modes (`code`, `architect`, `ask`)
- approval modes (`confirm`, `auto`)
- permission gates layered over tool prompts
- plan-related UI and mode concepts
- OTEL/Langfuse/devtools observability wrappers
- local debug/session persistence that partially overlaps with observability

This plan removes the mode/telemetry systems that add runtime complexity and
keeps the systems that are still worth evolving.

## Keep

### Panels and terminal takeover

Keep the panel/modal infrastructure. It already exists, it works, and Glue has
already chosen a full terminal application architecture. Do not spend this pass
trying to convert Glue back to append-only scrollback.

Keep:

- `PanelController`
- `PanelOverlay`
- `DockManager`
- model/session/help-style panels that are actively useful
- output viewport repainting
- autocomplete overlays

### Docker and future remote runtimes

Keep the command executor abstraction. The Docker sandbox is useful on its own
and should become the bridge to remote runtimes later.

Keep:

- `CommandExecutor`
- `HostExecutor`
- `DockerExecutor`
- `ExecutorFactory`
- `SessionState` mount persistence, unless a later pass replaces it with a
  better runtime-state file

Future direction:

- local host executor
- local Docker executor
- cloud runtime executor for providers like E2B, Modal, Daytona, or similar
- runtime selection through config, not UI mode policy

### Web and browser tools

Keep web research and browser automation. These are core to the intended
workflow: scraping, research, data extraction, malware/static-analysis
isolation, and offloading risky browsing away from the local machine.

Keep:

- `web_fetch`
- `web_search`
- `web_browser`
- browser endpoint/provider abstraction
- fetch/search provider routing

## Remove

### 1. Remove interaction modes

Remove the `code` / `architect` / `ask` mode system.

Why:

- It is a UI-level policy layer that competes with prompts and tool approval.
- It is not nice to use in practice.
- It creates surprising behavior: the model may be capable of a task, but the
  current mode silently hides or denies tools.
- It adds state to config, status bar, tests, permission resolution, and docs.
- It encourages "plan mode" UX instead of normal agent conversation.

Target behavior:

- There is no visible interaction mode.
- There is no Shift+Tab mode cycling.
- Tools are always present according to normal configuration.
- Planning is just a prompt or slash command, not a mode.

Likely removal targets:

- `lib/src/config/interaction_mode.dart`
- `InteractionMode` references in `App`
- `_interactionMode`
- `_syncToolFilter`
- Shift+Tab mode cycling in terminal event handling
- mode label in the status bar
- `GLUE_INTERACTION_MODE`
- `interaction_mode` in config docs and config parsing
- interaction-mode tests
- architect/ask cases in permission gate tests

Keep or collapse:

- `ApprovalMode` may remain temporarily if we still want `confirm` versus
  `auto`.
- If approval stays, rename the concept to plain tool approval, not interaction
  mode.

### 2. Remove plan-mode and plan-related UI

Remove the plan-mode experience and related panels if they are only supporting
the interaction-mode workflow.

Why:

- It does not work well enough to justify a top-level UX concept.
- It duplicates what the agent can do in normal chat.
- It adds a planning data model and panel surface that are not central to
  coding-agent execution.

Target behavior:

- A user can still ask: "make a plan".
- A slash command may print a simple markdown task list into the transcript.
- There is no special plan mode or plan panel required for normal operation.

Likely removal targets:

- `PlanStore` if it is only used by plan panels/workflows
- plan panel commands
- plan-related slash commands that open panels
- plan-related tests
- plan docs that describe plan mode as a first-class UX

Be careful:

- Do not remove normal markdown rendering.
- Do not remove task-like text in assistant output.
- Do not remove panels generally.

### 3. Collapse permission gate to simple approval

The current `PermissionGate` combines interaction mode and approval mode. Once
interaction modes are removed, the gate should either disappear or shrink to a
small approval decision.

Why:

- The mode matrix is the hard part.
- A simple "ask before mutating tools" prompt is understandable.
- A persistent trusted-tools list is acceptable if it stays simple.

Target behavior options:

Option A, simplest:

- Remove `PermissionGate`.
- `approval_mode: auto` means run tools.
- `approval_mode: confirm` means ask before mutating tools.
- Safe tools run without prompting.

Option B, slightly more conservative:

- Keep `PermissionGate`, but delete all interaction-mode checks.
- It only decides `allow` versus `ask` based on approval mode, trusted tools,
  and `ToolTrust`.

Suggested default:

- Keep confirmation support for now, but remove mode-based deny behavior.
- Revisit later once the app feels simpler.

### 4. Remove OTEL/Langfuse/devtools observability

Remove external observability integration from the runtime path.

Why:

- It complicates startup and service wiring.
- It causes runtime issues when partially configured or unavailable.
- It duplicates local session/debug logs.
- Glue is a local CLI first; local JSONL is enough for debugging.

Target behavior:

- Write debug events to known local files under `GLUE_HOME`.
- Use JSONL for append-only trace/event streams.
- Use JSON files for config/state snapshots.
- No OTEL exporter.
- No Langfuse sink.
- No devtools sink required for normal execution.
- No HTTP-client observability wrapper required for normal execution.

Suggested local files:

```text
~/.glue/
  logs/
    glue-debug-YYYY-MM-DD.jsonl
  traces/
    <session-id>.jsonl
  sessions/
    <session-id>/
      meta.json
      conversation.jsonl
```

Event examples:

```json
{"ts":"...","type":"llm_start","provider":"anthropic","model":"...","session_id":"..."}
{"ts":"...","type":"llm_usage","input_tokens":1234,"output_tokens":456}
{"ts":"...","type":"tool_start","name":"bash","call_id":"..."}
{"ts":"...","type":"tool_end","name":"bash","call_id":"...","ok":true,"ms":1820}
{"ts":"...","type":"error","where":"web_fetch","message":"..."}
```

Likely removal targets:

- `lib/src/observability/otel_sink.dart`
- `lib/src/observability/langfuse_sink.dart`
- `lib/src/observability/devtools_sink.dart`
- `ObservedLlmClient`
- `ObservedTool`
- `LoggingHttpClient`
- OTEL/Langfuse config parsing
- OTEL/Langfuse docs
- observability integration tests

Keep or replace:

- Keep a tiny local debug logger if useful.
- Keep `--debug`, but make it mean "write local JSONL and optionally verbose
  stderr", not "wire external telemetry".

### 5. Keep the CLI stable while removing config keys

Do not break basic startup with stale user config.

When removing config keys:

- Ignore old `interaction_mode` with a warning at most.
- Ignore old telemetry config with a warning at most.
- Keep `approval_mode` only if simple approval remains.
- Update `cli/docs/reference/config-yaml.md`.
- Update README environment-variable lists.

## Implementation Order

1. Add tests that lock the new behavior:
   - no interaction mode in status bar
   - Shift+Tab no longer cycles modes
   - mutating tool approval still works if approval remains
   - safe tools still run without prompt
   - app starts with stale `interaction_mode` config
   - app starts with stale OTEL/Langfuse config

2. Remove interaction modes:
   - delete or collapse `InteractionMode`
   - remove `_interactionMode`
   - remove `_syncToolFilter`
   - remove status-bar mode label
   - remove Shift+Tab mode cycling

3. Collapse permission gate:
   - remove mode-based deny branches
   - keep only `ToolTrust` and trusted-tools approval if needed
   - simplify tests

4. Remove plan-mode UX:
   - delete plan panel commands if they only exist for mode UX
   - delete `PlanStore` only if no remaining command uses it
   - keep plain markdown planning in normal chat

5. Remove external observability:
   - remove OTEL/Langfuse/devtools sinks
   - remove observed wrappers
   - wire direct LLM client and direct tools
   - add local JSONL debug logger if needed

6. Clean docs:
   - README
   - config reference
   - architecture docs
   - any plan docs that recommend architect/ask modes

7. Run:
   - `dart analyze`
   - focused tests around config, permission/approval, app render, slash commands
   - full `dart test` when the focused pass is green

## Non-Goals For This Pass

Do not remove:

- panels generally
- Docker executor
- shell executor abstraction
- web fetch/search/browser tools
- subagents
- model picker/session picker if they are useful
- markdown renderer
- multiline input

Do not attempt:

- append-only scrollback rewrite
- full TUI redesign
- provider/client rewrite
- cloud runtime implementation

## Top 10 Smaller Simplification Candidates

These are not the main removal items above. They are smaller papercuts worth
revisiting after the interaction-mode and observability cleanup.

1. **Unify debug logs and traces**

   Today there are logs, traces, observability sinks, and session logs. After
   external telemetry is removed, define one local event schema and write all
   debug/runtime events as JSONL.

2. **Reduce startup service construction**

   `ServiceLocator.create()` eagerly constructs many services. Consider lazy
   creation for browser manager, search router, skill runtime, title generator,
   and cloud/runtime clients. Startup should only build what the initial screen
   needs.

3. **Make title generation optional and obviously background-only**

   Session titles are useful, but title generation should never affect startup,
   shutdown, or turn completion. If it fails, no UI or runtime error should be
   visible unless debug logging is enabled.

4. **Simplify shell completion support**

   Shell completions are nice, but the install/uninstall command code is large
   relative to its importance. Keep generated completions if they are cheap;
   otherwise move completion installers out of the critical CLI path.

5. **Collapse old config compatibility paths**

   Keep one compatibility layer for one or two releases, then delete legacy
   config paths and aliases. Long-lived migration code makes config bugs harder
   to reason about.

6. **Standardize tool result summaries**

   Tools currently return ad hoc strings. Define a small display contract:
   `summary`, `details`, `is_error`, `bytes`, `line_count`, maybe `artifacts`.
   This will make render output cleaner without changing tool execution.

7. **Make write/edit output diff-aware**

   `write_file` and `edit_file` should return enough metadata for Codex-style
   `Edited N files (+x -y)` blocks. This is a UX improvement and also reduces
   the need to inspect raw tool results.

8. **Trim provider/model registry surface**

   If model aliases, provider defaults, title models, and profiles all overlap,
   pick one clear model-resolution path and make everything else call into it.

9. **Move rare slash commands out of the hot path**

   Keep common commands built in. Rare commands can be registered lazily or
   moved behind a help/discover command so the command registry stays readable.

10. **Prefer one autocomplete stack**

Slash autocomplete, `@file` hints, and shell completion all compete in the
terminal event path. Keep all three if useful, but define one shared overlay
interface and one shared navigation/accept/cancel behavior.

## Success Criteria

- No `code` / `architect` / `ask` mode visible in UI, config, docs, or tests.
- No plan-mode panel required for normal planning workflows.
- No OTEL/Langfuse/devtools observability dependency in normal startup.
- `--debug` writes local files under `GLUE_HOME` or `~/.glue`.
- Docker, web/browser tools, panels, and normal agent execution still work.
- Stale config files do not crash startup.
- Full test suite passes after docs and tests are updated.
