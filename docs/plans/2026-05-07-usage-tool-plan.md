# Usage Tool Plan

> Status: design / planning only. No code changes in this plan.

## Goal

Expose session token-usage data to the LLM as a first-class `Tool`, so the
model can answer questions like "how much have we spent this session?" or
"are we close to the context window limit?" without the user having to
paste `/usage` output into the chat.

The diagnostic data already exists — `cli/lib/src/commands/usage_report.dart`
builds and formats a per-role token report. Today it is reachable only via
the `/usage` slash command, whose output is rendered to the transcript but
**not** added to the agent's conversation history.

## Why a tool, not a context-injection seam

There are two plausible patterns for surfacing diagnostic data to the
model:

1. **Tool** — register a `get_usage` tool on `AgentCore`. The model invokes
   it when relevant, the result flows through the normal
   `tool_call`/`tool_result` machinery.
2. **Context contributor** — extend `SlashCommand` so `/usage` can inject
   its output into the agent's next turn as a synthetic message.

This plan picks (1):

- the `Tool` contract (`packages/glue_core/lib/src/tool.dart`) is exactly
  the right shape: name, description, schema, `execute(args) → ToolResult`
- usage data is a **read** operation the model should be able to pull on
  demand, not a fact every prompt should carry
- option (2) would require a new return channel from `SlashCommand`,
  invite scope creep ("should `/clear` contribute too?"), and burn tokens
  on every `/usage` invocation regardless of whether the model needs them
- the tool route is strictly additive — `/usage` keeps its current
  display-only behavior, and the new tool happens to share its formatter

If a recurring need for "slash command output must reach the model"
emerges across multiple commands, a `ContextContributor` abstraction can
be designed then. Until then, one tool is enough.

## How this fits the existing architecture

### Tool contract

`packages/glue_core/lib/src/tool.dart:135` defines the `Tool` base class:

```dart
abstract class Tool {
  String get name;
  String get description;
  List<ToolParameter> get parameters;
  Future<ToolResult> execute(Map<String, dynamic> args);
  ToolTrust get trust => ToolTrust.safe;
}
```

`get_usage` is a pure read with no parameters and no mutation. It stays
on `ToolTrust.safe`, so `PermissionGate` will not prompt the user.

### Tool registration

Tools are registered as a `Map<String, Tool>` passed to `AgentCore(tools: ...)`.
The two existing registration sites are:

- `cli/lib/src/acp/cli_acp_delegate.dart:35-42` (per-ACP-session map)
- the main App startup path (wherever `AgentCore` is constructed for the
  interactive surface — call site in services/lifecycle)

Both sites need the new entry.

### Formatter reuse

`cli/lib/src/commands/usage_report.dart` already exposes:

- `buildUsageReport({usageEvents, modelLabel, sessionId})`
- `formatUsageReport(report)`

The slash command in `cli/lib/src/commands/slash/usage.dart` is currently
the only consumer. Both `/usage` and the new tool will call the same
`buildUsageReport` + `formatUsageReport` pair — the formatter stays the
single source of truth for how usage is presented.

## Proposed tool contract

### Schema

```json
{
  "name": "get_usage",
  "description": "Return token usage for the current session, broken down by role (main, subagent, title). Call when the user asks about cost, token consumption, or session size.",
  "input_schema": {
    "type": "object",
    "properties": {},
    "required": []
  }
}
```

### Result

`ToolResult.content` is the same string `/usage` shows the user today.
`ToolResult.summary` carries a short human-readable label
(`"Usage report for <session-id>"`). `ToolResult.metadata` carries the
session id for downstream observability.

### No-active-session path

If `SessionManager.currentStore` is `null`, return a successful
`ToolResult` with content `"No active session yet."` rather than failing.
The model can then answer the user directly without retry.

## Proposed implementation shape

### 1. New tool file

**File:** `cli/lib/src/tools/usage_tool.dart` (new)

```dart
import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';

import 'package:glue/src/commands/usage_report.dart';

class UsageTool extends Tool {
  UsageTool(this._sessionGetter);

  final SessionManager Function() _sessionGetter;

  @override
  String get name => 'get_usage';

  @override
  String get description =>
      'Return token usage for the current session, broken down by role '
      '(main, subagent, title). Call when the user asks about cost, token '
      'consumption, or session size.';

  @override
  List<ToolParameter> get parameters => const [];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final store = _sessionGetter().currentStore;
    if (store == null) {
      return ToolResult(content: 'No active session yet.');
    }
    final report = buildUsageReport(
      usageEvents: SessionStore.loadConversation(store.sessionDir),
      modelLabel: store.meta.modelRef,
      sessionId: store.meta.id.value,
    );
    return ToolResult(
      content: formatUsageReport(report),
      summary: 'Usage report for ${store.meta.id.value}',
      metadata: {'session_id': store.meta.id.value},
    );
  }
}
```

The constructor takes a getter (`SessionManager Function()`) rather than
a direct reference because the live `SessionManager` is constructed during
app startup — the getter pattern matches how `SlashCommandContext`
already handles late-bound dependencies.

### 2. Register the tool

**File:** `cli/lib/src/acp/cli_acp_delegate.dart`

Add to the per-session tool map:

```dart
final tools = <String, Tool>{
  ...,
  'get_usage': UsageTool(() => services.session),
};
```

**File:** the interactive App's `AgentCore` construction site

Same one-line addition. Both registration paths must include the tool, or
the surfaces will diverge in capability.

### 3. Why no harness changes

`UsageTool` lives in `cli/` because:

- `usage_report.dart` is a CLI-layer module (it depends on
  `SessionStore.loadConversation` which is a harness-side primitive used
  via the CLI's session services)
- the harness has no opinion on usage reporting — it's a CLI surface
  feature
- registering tools per surface is already the established pattern (see
  the ACP delegate)

If the report ever needs to be shared with a non-CLI surface, the tool
and its formatter can move down to `glue_harness` as a single unit.

## Suggested file-by-file changes

### CLI (`cli/`)

#### New
- `cli/lib/src/tools/usage_tool.dart`

#### Modified
- `cli/lib/src/acp/cli_acp_delegate.dart` — register `get_usage` in the
  per-session tool map (`createSession`)
- the interactive App's tool registration site — register `get_usage`
- `cli/lib/glue.dart` — barrel export for `UsageTool` if external
  consumers need it (otherwise leave private to `cli/`)

### No core / harness / ACP changes

- `glue_core` — unchanged. `Tool`, `ToolResult`, `ToolParameter` already
  cover everything needed.
- `glue_harness` — unchanged. `AgentCore` already accepts arbitrary
  `Tool` registrations.
- `glue_server` (ACP) — unchanged. The tool flows through normal
  tool-call plumbing; ACP clients see it as just another tool.

## Tests

### Unit

- `cli/test/tools/usage_tool_test.dart` (new)
  - returns `"No active session yet."` when `SessionManager.currentStore`
    is `null`
  - returns formatted report when a session exists, with correct
    `summary` and `metadata['session_id']`
  - schema (`toSchema()`) advertises an empty parameter object

### Integration

- `cli/test/integration/usage_tool_integration_test.dart` (new)
  - drive a fake LLM that emits a `get_usage` tool call
  - assert the agent transcript contains a matching `tool_result` with
    the expected formatted body
  - assert no permission prompt was raised (trust = safe)

### Existing tests

- no changes expected to `/usage` slash-command tests — that behavior is
  unchanged. If anything, factor a shared fixture so both the slash
  command test and the tool test exercise the same `buildUsageReport`
  output.

## Prompting / usage guidance for models

Update `packages/glue_harness/lib/src/agent/prompts.dart` only if needed.
Likely not needed for v1 — the tool description is enough. If model
behavior shows the tool being called too eagerly (e.g. unprompted
chatter about token counts), tighten the description with a "only when
the user asks" clause.

## Risks and edge cases

### 1. Token cost of the tool result

`formatUsageReport` is a small block (~10–20 lines). Inserting it as a
tool result is cheap. No truncation needed for v1.

### 2. Session not yet created

Handled by the `currentStore == null` branch above. The model receives a
plain successful result and can answer the user directly.

### 3. Tool advertised but not implemented downstream

Both `cli_acp_delegate.dart` and the main App must register the tool. A
missing registration means the model sees `get_usage` in one surface and
not the other. Add an integration smoke test that asserts the canonical
tool set on each surface.

### 4. Formatter changes

If `formatUsageReport`'s output format changes, both `/usage` and the
tool inherit the change automatically. No special coordination required.

### 5. Permissioning

`get_usage` is read-only over local session state. `ToolTrust.safe` is
correct — no `PermissionGate` prompt. Reconfirm if a future change makes
the underlying call mutate state (unlikely).

## Suggested phased implementation

### Phase 1 — Tool exists and is callable

1. Add `cli/lib/src/tools/usage_tool.dart`.
2. Register in both tool-registration sites.
3. Add unit + integration tests.

#### Acceptance criteria

- model can call `get_usage`
- result content matches `/usage` output for the same session
- no permission prompt
- empty-session path returns a clean message instead of an error

### Phase 2 — Optional refinements (only if observed)

1. Tighten the description if the model over-uses the tool.
2. Add a `roles` parameter (`["main", "subagent", "title"]`) to filter
   the report — only if a real prompt benefits from it.
3. Move tool + formatter to `glue_harness` if a second surface needs it.

## Open questions

1. **Where exactly is the interactive App's `AgentCore` constructed?**
   The plan assumes one canonical site; verify before implementing so
   both registration sites stay in sync.
2. **Should the tool return JSON or formatted text?** Recommendation:
   formatted text (same as `/usage`) for v1. The model handles formatted
   tables fine, and structured-result variants can be added later as
   metadata.
3. **Should `/usage` and `get_usage` ever diverge?** Recommendation: no.
   Treat `formatUsageReport` as the single source of truth.

## Acceptance criteria summary

This plan is complete when:

1. `UsageTool` exists in `cli/lib/src/tools/usage_tool.dart` and extends
   `Tool` from `glue_core`.
2. The tool is registered as `get_usage` in every `AgentCore`
   construction site in `cli/`.
3. The model can invoke `get_usage` and receive a `ToolResult` whose
   `content` matches what `/usage` would print.
4. The empty-session path returns a successful, descriptive result.
5. The tool is `ToolTrust.safe` and bypasses permission prompts.
6. Unit and integration tests cover both populated and empty sessions.
7. `/usage` continues to work unchanged and shares
   `buildUsageReport`/`formatUsageReport` with the tool.
