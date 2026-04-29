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
are allowed within reason. Cross-layer-up imports are bugs. The linter at
`cli/tool/check_layers.dart` enforces this rule in CI (`--strict`).

## Subsystem → layer mapping

After the package extractions:

| Package / Subsystem    | Layer      | Notes                                |
|------------------------|------------|--------------------------------------|
| `packages/glue_core/`  | core       | Pure data types                      |
| `packages/glue_strategies/` | strategies | LLM clients, providers, exec, web |
| `packages/glue_harness/`    | harness    | Agent loop, sessions, catalog, tools |
| `cli/lib/src/app/`     | surface    | App controller, event-merge loop     |
| `cli/lib/src/commands/`| surface    | CLI subcommands (config, doctor)     |
| `cli/lib/src/doctor/`  | surface    | Doctor checks + output formatting    |
| `cli/lib/src/input/`   | surface    | LineEditor, TextAreaEditor           |
| `cli/lib/src/rendering/`| surface   | ANSI + markdown rendering            |
| `cli/lib/src/terminal/`| surface    | Raw terminal I/O                     |
| `cli/lib/src/ui/`      | surface    | Modals, panels, autocomplete         |

The CLI is now a pure surface package. The harness/strategies/core
extractions mean the four-layer architecture is enforced not just by
the linter but by Dart's package boundaries.
| `web/`            | strategies  | Search/Browser/Fetch providers            |

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

**Foundational:**

1. ✅ **Linter PR.** Layer-import enforcement script in CI.
2. ✅ **Type wrappers PR.** `SessionId` and `ToolCallId` adopted across
   session, agent, LLM, and orchestrator code.
3. ✅ **Sealed event types PR.** `SessionEvent` and `SessionCommand`
   defined as the proposed surface↔harness contract.

**Decoupling:**

4. ✅ **Move data types to `_proposed_core/` (the future `glue_core`).**
   `Message`, `ToolCall`, `LlmChunk`, `Tool`, `ToolResult`, `ToolTrust`,
   `ContentPart`, `LlmClient`, `AgentEvent`, `ModelRef`, `ModelCatalog`,
   `AppConstants`. Strategies now import directly from `_proposed_core/`
   for the types they need. `agent/` and `catalog/` re-export shims keep
   their old harness rank for non-strategy consumers.
5. ✅ **Misclassified-subsystem moves.** `title_generator`,
   `llm_factory`, `shell_job_manager` moved to `agent/` (harness) — they
   were data-driven services, not wire-format strategies.
6. ✅ **Permission gate PR.** `PermissionGate.requestEventFor(...)` emits
   typed `PermissionRequestedEvent`s for new surfaces.
7. ✅ **service_locator decoupled** from `terminal/` and `input/`.
8. ✅ **Linter flipped to strict, full four-layer enforcement.**
9. **OAuth device flow PR.** Same callback→events transformation as
   the permission gate.
10. **Settings cascade PR.** `SettingsResolver` with source tracking.

**Strategy extraction:**

11. ✅ **Move strategies to `glue_strategies` package.**
    `credentials/`, `llm/`, `providers/`, `shell/`, `web/` source dirs
    moved out of `cli/lib/src/` into `packages/glue_strategies/`. CLI
    consumes via path dependency and the
    `package:glue_strategies/glue_strategies.dart` public barrel.
12. **Move transport layer to `glue_transport` package.** (HTTP, SSE,
    NDJSON, process spawning — extract from glue_strategies once a
    second consumer needs them.)

**Harness consolidation:**

13. ✅ **Extract `_proposed_core/` as a sibling `glue_core` package.**
    Pure-data types now live under `packages/glue_core/`; CLI consumes
    via path dependency and the `package:glue_core/glue_core.dart`
    public barrel.
14. ✅ **Extract harness package.** Twelve subsystems (`agent/`,
    `catalog/`, `config/`, `core/`, `extensions/`, `observability/`,
    `orchestrator/`, `session/`, `share/`, `skills/`, `storage/`,
    `tools/`) now live under `packages/glue_harness/`. CLI is now a
    pure surface package — only `app/`, `commands/`, `doctor/`,
    `input/`, `rendering/`, `terminal/`, `ui/` remain in
    `cli/lib/src/`.
15. **Trim the CLI.** (Largely done by #14; remaining work is
    barrel cleanup and naming.)

**Surface expansion:**

16. ✅ **Add `glue serve --stdio` (ACP server).** New
    `packages/glue_server/` provides JSON-RPC 2.0 framing,
    line-delimited stdio transport, ACP message types (initialize,
    session/new, session/prompt, session/cancel, session/update,
    session/request_permission), an `AcpServer` dispatcher, and a
    `SessionEvent` / `AgentEvent` → ACP update mapping.
17. ✅ **`session/prompt` round-trip.** `AcpServer` routes
    `session/new` to an `AcpServerDelegate.createSession`; the cli's
    `CliAcpDelegate` builds a per-session `AgentCore` + tool registry
    via `ServiceLocator`. `session/prompt` runs `AgentCore.run()`,
    streams text deltas as `agent_message_chunk` notifications,
    synthesises `tool_call` / `tool_call_update` lifecycle around
    each `AgentToolCall`, and routes the harness's `PermissionGate`
    "ask" decisions through `session/request_permission` with an
    async waiter for the client's reply.
18. **CLI as ACP client (optional).**
19. ✅ **WebSocket transport.** `WebSocketTransport` implements
    `JsonRpcTransport`; `AcpHttpHost` binds an HTTP server, accepts
    WebSocket upgrades on `/acp` (configurable), and runs one
    `AcpServer` per connection with a delegate factory for
    per-connection isolation. CLI grows `glue serve --port N
    [--host H] [--ws-path /p]`.
20. ✅ **Image content blocks.** ACP messages now use a sealed
    `AcpContentBlock` (text, image, audio, resource_link, unknown
    pass-through) and a sealed `AcpToolCallContent` (content / diff /
    terminal). `ToolResult.contentParts` (TextPart / ImagePart) flows
    through to the ACP client unchanged; image-bearing tool results
    (e.g. `web_browser` screenshots) are first-class.
21. **Multi-client session attach.**
22. **MCP client.** See `docs/plans/2026-04-29-mcp-client.md`.

## What this PR delivers

Two pieces of foundation, both no-runtime-impact:

- **`cli/tool/check_layers.dart`** — layer-import linter, warn-only, runs in
  CI. Outputs the violation worklist.
- **`cli/lib/src/_proposed_core/`** — sealed `SessionEvent` and
  `SessionCommand` types covering the full vocabulary. Not yet wired to
  consumers; established as the contract everyone will reference.

Both are independently valuable, low risk, and do not change runtime behavior.
