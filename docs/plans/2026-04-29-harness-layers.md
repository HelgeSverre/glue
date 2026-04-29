# Harness Layers — Architecture & Migration Plan

**Status:** proposed
**Date:** 2026-04-29
**Branch:** `claude/architect-harness-layers-maSVJ`

## Why this document exists

We are not designing greenfield. We are describing the target state that
today's Glue can evolve into through a sequence of preparatory PRs and a final
harness extraction. Where today's code already matches the target, this doc
says so. Where it doesn't, this doc is explicit about what changes.

The goal is to make it possible to add new surfaces (ACP server, web UI) on
top of the existing CLI without dragging surface concerns into core code.

## The four layers

```
┌───────────────────────────────────────────────────────────────────┐
│ SURFACES                                                          │
│   glue_cli (TUI)    glue_server (ACP)    glue_web (later)         │
│   • view state      • transport          • view state             │
│   • input handling  • auth               • input handling         │
│   • rendering       • session adapters   • rendering              │
└─────────────────────────┬─────────────────────────────────────────┘
                          │  Glue.open() returns Glue
                          │  All interaction via Glue API + Streams
                          ▼
┌───────────────────────────────────────────────────────────────────┐
│ HARNESS                                                           │
│   • Glue (root)     • ProjectRegistry   • SessionStore            │
│   • AgentCore       • ToolRegistry      • SkillRegistry           │
│   • CatalogService  • ObservabilityHub  • SettingsResolver        │
└─────────────────────────┬─────────────────────────────────────────┘
                          │  Strategy interfaces (pluggable)
                          ▼
┌───────────────────────────────────────────────────────────────────┐
│ STRATEGIES (pluggable interfaces with shipping implementations)   │
│   Provider     CommandExecutor    BrowserEndpoint    SearchProv   │
│   FetchClient  CredentialStore    SessionPersistence              │
└─────────────────────────┬─────────────────────────────────────────┘
                          │  Pure transport, no LLM/agent semantics
                          ▼
┌───────────────────────────────────────────────────────────────────┐
│ TRANSPORT                                                         │
│   HTTP clients · SSE · NDJSON · vsock · process spawning · git    │
└───────────────────────────────────────────────────────────────────┘
```

**Rule:** a layer may import only from layers below it. Same-layer imports
are allowed within reason. Cross-layer-up imports are bugs. The linter
introduced in this PR enforces this rule (warn-only initially).

## Subsystem → layer mapping (today's tree)

Today's `cli/lib/src/` directories map to layers as follows:

| Subsystem         | Layer       | Notes                                     |
|-------------------|-------------|-------------------------------------------|
| `agent/`          | harness     | AgentCore, AgentRunner, AgentManager      |
| `app/`, `app.dart`| surface     | App controller, event-merge loop          |
| `catalog/`        | harness     | Bundled + remote model catalog            |
| `commands/`       | surface     | CLI subcommands (config, doctor)          |
| `config/`         | harness     | GlueConfig resolver                       |
| `core/`           | harness     | Environment, service locator (see below)  |
| `credentials/`    | strategies  | CredentialStore impls                     |
| `doctor/`         | surface     | Doctor checks + output formatting         |
| `extensions/`     | harness     | Internal extension methods                |
| `input/`          | surface     | LineEditor, TextAreaEditor                |
| `llm/`            | strategies  | Provider wire-format clients              |
| `observability/`  | harness     | Tracing, OTEL, Langfuse                   |
| `orchestrator/`   | harness     | Permission gating                         |
| `providers/`      | strategies  | Higher-level provider adapters            |
| `rendering/`      | surface     | ANSI + markdown rendering                 |
| `session/`        | harness     | SessionStore, SessionManager              |
| `share/`          | harness     | Session export/share                      |
| `shell/`          | strategies  | CommandExecutor (host, docker)            |
| `skills/`         | harness     | Skill discovery + execution               |
| `storage/`        | harness     | Persistence helpers                       |
| `terminal/`       | surface     | Raw terminal I/O                          |
| `tools/`          | harness     | Tool definitions                          |
| `ui/`             | surface     | Modals, panels, autocomplete              |
| `web/`            | strategies  | Search/Browser/Fetch providers            |

Known coupling that the linter will surface as a worklist item:
- `core/service_locator.dart` imports `input/text_area_editor.dart`. This is
  a known violation — service_locator straddles the surface/harness boundary
  today. Will be addressed in a later decoupling PR.

## Target package structure

```
glue/
├── packages/
│   ├── glue_core/        ← data model. No behavior, no I/O.
│   ├── glue_transport/   ← HTTP clients, SSE/NDJSON, vsock, process.
│   ├── glue_strategies/  ← Provider/Executor/Browser/Search interfaces + impls.
│   ├── glue_harness/     ← orchestration. Imports core + strategies + transport.
│   ├── glue_cli/         ← TUI surface.
│   ├── glue_server/      ← ACP surface (later).
│   └── glue_web/         ← Web surface (much later).
```

`glue_core` is the highest-leverage extraction because everything else's
purity depends on it being clean. It is a pure data package: identity types,
domain types, event types, command types. No behavior.

## Data model

### Identity types

Wrap every ID in a typed `extension type`. No raw strings.

```dart
extension type const ProjectId(String value) {}
extension type const SessionId(String value) {}
extension type const TurnId(String value) {}
extension type const ToolCallId(String value) {}
extension type const SubagentId(String value) {}
extension type const SkillId(String value) {}
extension type const PermissionRequestId(String value) {}
extension type const ModelRef(String value) {}    // already in your code
extension type const ProviderId(String value) {}  // 'anthropic', 'openai', ...
```

### Sealed event hierarchy

Every event has:
- `turnId` for grouping
- `sequence` (monotonic per session) for ordering
- `timestamp` for display

Permission and OAuth flows are **events**, not callbacks. The agent emits
`PermissionRequestedEvent` and the surface responds via
`session.dispatch(ResolvePermissionCommand(...))`. Same for device-code OAuth.
This is the structural fix that decouples surface from harness.

Subagents emit `SubagentEventForwardedEvent` carrying the inner event. The
surface decides whether to render inline (CLI) or as a separate pane (web).

The full event vocabulary is defined in
`cli/lib/src/_proposed_core/session_event.dart` (this PR).

### Sealed command hierarchy (surface → harness)

```dart
sealed class SessionCommand {}

class SendMessageCommand extends SessionCommand { ... }
class InterruptCommand extends SessionCommand {}
class CancelCommand extends SessionCommand {}
class ResolvePermissionCommand extends SessionCommand { ... }
class ResolveDeviceCodeCommand extends SessionCommand { ... }
class SwitchModelCommand extends SessionCommand { ... }
class RegenerateCommand extends SessionCommand { ... }
```

The entire surface↔harness contract is two stream types: `Stream<SessionEvent>`
out, `Stream<SessionCommand>` in. ACP can implement it as one JSON-RPC method.
Tests can replay command logs.

## The harness API (target)

```dart
class Glue {
  static Future<Glue> open({GlueConfig? config, GlueOverrides? overrides});

  ProjectRegistry get projects;
  SessionStore get sessions;
  ToolRegistry get tools;
  SkillRegistry get skills;
  CatalogService get catalog;
  ObservabilityHub get observability;
  SettingsResolver get settings;

  Future<AgentRunResult> run(AgentRunRequest req);   // for `glue -p`
  Future<void> close();
}

abstract interface class Session {
  SessionId get id;
  ProjectId get projectId;
  SessionMeta get meta;

  Stream<SessionEvent> history();   // cold, from store
  Stream<SessionEvent> events();    // hot, broadcast, from now
  Stream<SessionEvent> replay();    // history concat events

  Future<void> dispatch(SessionCommand cmd);

  // Convenience wrappers — sugar over dispatch.
  Future<void> send(String text);
  Future<void> interrupt();
  Future<void> cancel();
  Future<void> resolvePermission(PermissionRequestId id, {required bool granted, PermissionScope? scope});

  Future<void> close();
}
```

Three properties to flag:
- `dispatch` is the canonical method. Convenience wrappers are sugar.
- `history()` and `events()` are independent streams. Surfaces that connect
  mid-session call `replay()`. Tests call `history()` after completion.
- Closing a session is detach, not destroy. Multiple surfaces can attach.

## The agent loop (target)

```dart
class AgentLoop {
  AgentLoop({
    required Provider provider,
    required ToolRegistry tools,
    required ToolContext baseContext,
    required PermissionGate permissions,
    required ObservabilityHub obs,
    required EventSink<SessionEvent> emit,
    required CommandSource<SessionCommand> commands,
  });

  Future<void> run({required List<Message> initialMessages});
}
```

It does not import from any surface package. It does not read from terminal.
It emits events to a sink and reads commands from a source. `PermissionGate`
is a small class (~50 lines) that encapsulates request/response matching by
ID — the only place that needs to know permission semantics.

## Persistence layout (target)

```
~/.glue/
├── config.yaml
├── credentials.json
├── projects.json
└── projects/
    └── <project-id>/
        ├── project.json
        └── sessions/
            └── <session-id>/
                ├── meta.json              # SessionMeta — fast scan
                ├── conversation.jsonl     # SessionEvents, append-only
                └── checkpoints/           # optional snapshots for fork
                    └── seq-<n>.json
```

Three changes from today:
- Sessions live under their project directory, not flat.
- `meta.json` is just metadata. No conversation log entries.
- Optional checkpoints for fast fork-at-N.

## Surface responsibilities (exhaustive)

**CLI owns:** argv parsing, key bindings, terminal raw mode, screen buffer,
ANSI rendering, block layout, modal dialogs, autocomplete, line/text editors,
status bar, theme, slash command UI, session picker UI, doctor output
formatting, completions install logic.

**ACP server owns:** JSON-RPC framing, transport selection (stdio/WebSocket),
connection lifecycle, ACP capability negotiation, mapping `SessionEvent` →
ACP notifications, mapping ACP requests → `SessionCommand`, multi-client
coordination.

**Web (later) owns:** HTML/CSS/JS, websocket connection, render loops,
browser-side state, route handling.

**Harness owns everything else.** Including: model resolution, prompt
assembly, tool execution, permission state machine, OAuth flows (the state
machine, not the UI), credential storage, observability sinks, skill
activation logic, git worktree management, session persistence, metrics
calculation, title generation, gist publishing.

The test that distinguishes: *would identical logic be needed for any other
surface?* If yes, harness. If no, surface.

## Migration sequencing

**Foundational (do these first):**

1. ✅ **Linter PR** (this PR). Layer-import enforcement script in CI as
   warn-only. Produces the worklist.
2. **Type wrappers PR.** Add `extension type` wrappers for IDs.
3. ✅ **Sealed event types PR** (this PR). Define `SessionEvent` as a sealed
   type covering today's agent emissions. No consumer migration yet.

**Decoupling (largest set, do gradually):**

4. **Move data types to `glue_core`.** Identity types, domain types, event
   types, command types.
5. **Permission gate PR.** Convert callback to events + dispatch.
6. **OAuth device flow PR.** Same transformation.
7. **Settings cascade PR.** `SettingsResolver` with source tracking.
8. **Per-subsystem decoupling PRs.** One per subsystem with violations.
9. **Flip linter to error.**

**Strategy extraction:**

10. **Move strategies to `glue_strategies`.**
11. **Move transport layer to `glue_transport`.**

**Harness consolidation:**

12. **Extract harness package.**
13. **Trim the CLI.**

**Surface expansion:**

14. **Add `glue serve --stdio`.**
15. **CLI as ACP client (optional).**
16. **WebSocket transport.**
17. **Multi-client session attach.**

## What this PR delivers

Two pieces of foundation, both no-runtime-impact:

- **`cli/tool/check_layers.dart`** — layer-import linter, warn-only, runs in
  CI. Outputs the violation worklist.
- **`cli/lib/src/_proposed_core/`** — sealed `SessionEvent` and
  `SessionCommand` types covering the full vocabulary. Not yet wired to
  consumers; established as the contract everyone will reference.

Both are independently valuable, low risk, and do not change runtime behavior.
