# Context Inspector and Telemetry — Research + Implementation Plan

> Status: research / design. No code changes yet.
> Re-spec'd 2026-04-30 against the harness/strategies/core split.

## Goal

Give Glue users a truthful way to inspect how the active context window is being consumed, while also instrumenting the runtime so we can understand context growth, oversized payload failures, and future context-management regressions.

Concretely, this plan delivers:

1. A real `/context` slash command for the interactive TUI.
2. Structured context telemetry that can back both chat output (MVP) and a future docked right-side panel — and crucially, a future ACP-server endpoint, since ACP clients need the same data.
3. Error classification and tracking for provider calls that fail because request or response context is too large.
4. A clear model of how Glue currently manages context growth, where it already caps inputs, and where it currently has no first-class compaction story.

This is **not** just a slash command. `/context` is the UX surface for a broader context-observability subsystem.

---

## How this plan relates to the harness layers

Context telemetry must live in the harness so every surface (CLI today, ACP
server tomorrow, web later) sees the same numbers.

Layer placement (from `2026-04-29-harness-layers.md`):

- **Data types** (`glue_core`): `ContextSnapshot`, `ContextBreakdownItem`,
  `ContextContributor`, `ContextEvent`, new `ContextOverflowEvent` /
  `ContextSnapshotEvent` variants in `session_event.dart`.
- **Harness** (`glue_harness`):
  - the snapshot **builder** — invoked before each provider request from
    `AgentCore`, since only the harness has the full context (system
    prompt, instruction files, message history, tool schemas).
  - emission of context `SessionEvent`s into the existing event stream.
  - extension of `ObservabilityHub` (already in
    `packages/glue_harness/lib/src/observability/`) to attach context
    attributes to the per-turn span.
- **Strategies** (`glue_strategies`): provider clients raise typed
  `ContextOverflowException` from
  `packages/glue_strategies/lib/src/llm/*.dart`; the harness classifies
  them.
- **Surfaces**: the CLI's `/context` slash command formats the latest
  snapshot. The ACP server adds a `session/context_snapshot` request that
  returns the same structured data.

Important: the formatter/renderer is a **surface** concern. Different
surfaces will format the same telemetry differently. Don't bake string
formatting into the harness.

---

## Scope Statement

Add context telemetry to Glue's runtime so developers can inspect current context usage, identify the largest contributors, and debug context-related failures without guessing.

---

## Current State Audit

### What Glue already tracks

#### 1. Aggregate per-turn token usage exists

- `UsageInfo` in `packages/glue_core/lib/src/message.dart` captures `inputTokens` + `outputTokens`.
- `AgentCore.tokenCount` in `packages/glue_harness/lib/src/agent/agent_core.dart` accumulates `totalTokens` over the session.
- Fed by provider-specific parsers in:
  - `packages/glue_strategies/lib/src/llm/openai_client.dart`
  - `packages/glue_strategies/lib/src/llm/anthropic_client.dart`
  - `packages/glue_strategies/lib/src/llm/ollama_client.dart`

**What this gives us today:**
- total provider-reported token usage per session
- prompt/completion split per request

**What it does not give us:**
- current context occupancy
- composition breakdown (messages vs tools vs files vs instructions)
- top contributors
- turn-by-turn context growth
- overflow diagnosis

#### 2. Generic observability exists

Glue already has an observability layer in
`packages/glue_harness/lib/src/observability/`:

- `observability.dart`
- `logging_http_client.dart`
- `file_sink.dart`
- `http_trace_sink.dart`

Capabilities present:
- spans for tool execution (`tool.<name>`)
- spans for outbound HTTP requests (`http.<kind>`)
- redacted body/header logging
- max-body truncation in logs
- sink abstraction suitable for file/HTTP export

**Gap:** generic request/tool tracing, not context telemetry.

#### 3. Session storage already supports append-only event logging

`docs/reference/session-storage.md` describes the format. Sessions store:
- `meta.json`
- `conversation.jsonl`
- `state.json`

Current persisted `SessionEvent` variants include user/assistant messages, tool calls, tool results, permission events.

**Opportunity:** context snapshots and overflow/truncation can be added as new typed `SessionEvent` variants in `glue_core/session_event.dart` rather than inventing a parallel persistence model.

---

### How Glue currently mitigates context growth

Glue already has several **localized caps** and truncation safeguards.

#### 1. Project instruction files are capped at 50 KB

`packages/glue_harness/lib/src/agent/prompts.dart`

- `AGENTS.md` and `CLAUDE.md` are read into the system prompt.
- Each file is truncated if it exceeds `_maxGuidanceBytes = 50 * 1024`.
- Truncation is explicit: `"(truncated — file exceeded 50KB)"`.

**Good:** prevents runaway rules files from silently bloating the prompt.
**Bad:** no telemetry records how often this happens or how much was dropped.

#### 2. `@file` expansion rejects oversized files

Covered by `cli/test/input/file_expander_test.dart` — `@file` expansion lives in the CLI surface (`cli/lib/src/input/file_expander.dart`).

- Files over 100 KB render as `[too large: ...]` markers.

**Good:** direct user expansion has a hard guardrail.
**Bad:** the event is not surfaced as structured telemetry.

#### 3. Web/browser/fetch tool content is token-truncated

Key files (now in `glue_strategies`):
- `packages/glue_strategies/lib/src/web/fetch/truncation.dart`
- `packages/glue_strategies/lib/src/web/fetch/web_fetch_client.dart`
- `packages/glue_harness/lib/src/tools/web_browser_tool.dart`

Patterns:
- content is approximated to token counts via `TokenTruncation`
- outputs clipped to a configured/derived token budget
- truncation markers appended

**Bad:** truncation decisions not exposed in a central event stream.

#### 4. Some oversized web responses are rejected outright

`packages/glue_strategies/test/web/fetch/web_fetch_client_test.dart` tests assert explicit failure when response size exceeds the byte limit:
- `"Response too large: ... bytes (max ...)"`

**Bad:** no normalized failure type — just an error string.

#### 5. Ollama `num_ctx` is bounded

`packages/glue_strategies/lib/src/llm/ollama_client.dart`

- `ollamaNumCtxCeiling = 131072`
- catalog context windows are capped before being sent as `options.num_ctx`

**Bad:** request shaping, not session introspection.

#### 6. Session fork replays truncated history slices

`packages/glue_harness/lib/src/session/session_manager.dart`

- `forkSession()` truncates the replayed event history to a selected branch point.

**Bad:** not compaction or long-session context management.

---

### What Glue does **not** appear to have yet

Critical gap analysis.

#### 1. No first-class conversation compaction runtime

I searched for `compact`, `autocompact`, compaction thresholds, context
checkpointing, summarization of old turns before provider calls.

What exists:
- tests/autocomplete references to `/compact`
- design docs and plans discussing compaction or thinking tokens

What I did **not** find in live runtime code:
- a compactor service in `glue_harness`
- a slash command implementation for `/compact` in `cli`
- automatic turn compaction at token thresholds
- summarizer-driven checkpointing
- replacement of older conversation turns with compact summaries

**Conclusion:** Glue currently uses edge truncation and payload caps, but does not yet have a first-class session compaction story.

#### 2. No normalized classification of context-overflow failures

No dedicated error normalization layer for:
- prompt/context window exceeded
- request payload too large
- provider refused overlong input
- tool output too large for safe inclusion

Today: provider HTTP error bubbles up as generic exception text.

#### 3. No current context snapshot model

There is no `ContextSnapshot`, `ContextBreakdown`, `TopContributor`, or `ContextFailureEvent` type. So `/context` cannot be implemented truthfully without adding these primitives.

---

## Why this work matters

### User-facing reasons

1. **Debugging degraded sessions** — when the agent gets vague or forgetful, users need to know whether context growth is the cause.
2. **Debugging payload failures** — when a provider request errors because the prompt got too large, the user should see what filled it.
3. **Reducing superstition** — without visibility, users cargo-cult around `/clear` and model switches.

### Product/engineering reasons

1. **Telemetry before optimization** — don't build compaction blind.
2. **Future ACP/web parity** — ACP clients will demand the same data; structured telemetry from day one prevents a rewrite.
3. **Trust** — A `/context` command that invents precise-looking numbers is worse than nothing. Structured telemetry with confidence labels prevents that.

---

## Product Shape

### MVP (v1): `/context` prints a report in chat output

Surface implementation lives in `cli/lib/src/commands/builtin_commands.dart`. The slash command pulls a `ContextSnapshot` from the session and formats it. Sample output:

```text
Context usage: 142k / 400k tokens (35.5%)

██████████████░░░░░░░░░░░░░░░░░░░░░░░░

Breakdown
- System prompt              9.8k   2.5%
- Project instructions       4.1k   1.0%
- Tool schemas              18.2k   4.6%
- Conversation history      81.4k  20.4%
- Read file content         16.7k   4.2%
- Tool results              12.3k   3.1%
- Reserved headroom         20.0k   5.0%
- Free space               237.5k  59.2%

Top contributors
- AGENTS.md                         6.2k
- Tool schema bundle              18.2k
- Conversation history            81.4k
- Last web_fetch result            7.9k
- README.md                        4.4k

Warnings
- Conversation history is the dominant source of context growth
- Last web/browser payload was large
- No compaction strategy currently active for this session

Suggestions
- Run /clear before switching tasks
- Prefer focused file reads over broad exploration
- Trim large web/browser payloads before retrying
```

### MVP requirements

The report must answer four questions:

1. How full is the current context window?
2. What categories are consuming it?
3. What are the largest contributors?
4. What should the user do next?

### MVP non-goals

- no docked right-side panel yet
- no live auto-updating dashboard
- no drill-down interactivity
- no compaction implementation in the same PR
- no ACP `session/context_snapshot` endpoint yet (but the data model must support it)

### V2: docked right-side context panel

CLI-side panel using existing `DockManager`/`DockedPanel` machinery. Same telemetry source.

Sections: Overview, Breakdown, Contributors, Timeline, Failures.

---

## Recommended Data Model

All types live in `packages/glue_core/lib/src/context_telemetry.dart` (new
file) so they are usable by harness, surfaces, and tests without circular
imports.

### Context snapshot

```dart
class ContextSnapshot {
  final DateTime timestamp;
  final ModelRef modelRef;             // typed extension type from glue_core
  final int? contextWindowTokens;
  final int? usedTokens;
  final int? freeTokens;
  final int? reservedTokens;
  final List<ContextBreakdownItem> items;
  final List<ContextContributor> topContributors;
  final List<String> warnings;
  final List<String> suggestions;
}
```

### Breakdown item

```dart
enum ContextConfidence { exact, estimated, derived }

enum ContextCategory {
  system,
  instructions,
  tools,
  messages,
  files,
  toolResults,
  reserved,
  free,
}

class ContextBreakdownItem {
  final String key;
  final String label;
  final ContextCategory category;
  final int tokens;
  final double percent;
  final ContextConfidence confidence;
}
```

### Top contributor

```dart
enum ContextContributorType {
  systemPrompt,
  projectInstruction,
  toolSchema,
  message,
  file,
  toolResult,
  sessionSummary,
}

class ContextContributor {
  final String id;
  final String label;
  final ContextContributorType type;
  final int tokens;
  final ContextConfidence confidence;
  final Map<String, Object?> metadata;
}
```

### Per-turn telemetry (typed `SessionEvent`)

In `packages/glue_core/lib/src/session_event.dart`:

```dart
class ContextSnapshotEvent extends SessionEvent {
  final TurnId turnId;          // typed wrapper from glue_core/ids.dart
  final ContextSnapshot snapshotBefore;
  final ContextSnapshot? snapshotAfter;
  final int? requestBytes;
  final int? responseBytes;
}

class ContextOverflowEvent extends SessionEvent {
  final String provider;
  final String model;
  final String rawMessage;
}

class ToolResultTruncatedEvent extends SessionEvent { ... }
class WebResponseRejectedEvent extends SessionEvent { ... }
class ProjectInstructionTruncatedEvent extends SessionEvent { ... }
class FileExpansionRejectedEvent extends SessionEvent { ... }
class RetryAfterContextTrimEvent extends SessionEvent { ... }
```

Inheriting `SessionEvent` gets persistence, replay, and ACP forwarding for
free.

### Critical design rule

Every reported count must carry a confidence level:
- **exact** — provider/runtime/accounted bytes/tokens
- **estimated** — token estimation logic (char-count heuristics, etc.)
- **derived** — inferred from higher-level totals

No unlabeled fake precision.

---

## Where the numbers can come from

### Exact today

- provider-reported `prompt_tokens` / `input_tokens`
- provider-reported `completion_tokens` / `output_tokens`
- byte sizes of logged request/response bodies (via `LoggingHttpClient`)
- size of instruction files before/after truncation (visible in `prompts.dart`)
- size of tool results before/after truncation/rejection

### Estimated in v1

- tokens attributable to instruction file sections
- tokens attributable to message history slices
- tokens attributable to loaded tool schemas
- tokens attributable to file reads and tool results currently present in effective prompt context

If exact tokenizer infrastructure exists per model later, upgrade these from estimated to exact. For v1, estimates are acceptable only if marked.

---

## Failure Handling Plan

### New normalized failure classes

In `packages/glue_strategies/lib/src/llm/llm_errors.dart` (new):

- `ContextWindowExceededException`
- `RequestPayloadTooLargeException`
- `ResponsePayloadTooLargeException`
- `ToolOutputTooLargeException`

Provider clients (`anthropic_client.dart`, `openai_client.dart`,
`ollama_client.dart`) classify HTTP error bodies and throw the typed
exceptions. The harness's `AgentCore` catches them and emits typed
`ContextOverflowEvent`s.

### Recovery behavior

For provider request overflow:
1. classify the error in the strategies-layer client
2. emit a `ContextOverflowEvent`
3. capture a `ContextSnapshot` and emit `ContextSnapshotEvent`
4. surface a useful user-facing message (CLI formats; ACP returns structured data)
5. optionally retry once after deterministic trimming if safe

### User-facing message shape (CLI surface)

```
Request exceeded the model context budget. The largest contributors were
conversation history and a recent tool result. Run `/context` to inspect
details, or retry after narrowing scope.
```

### Retry rules

- at most one automatic retry
- only after a deterministic trim strategy
- never infinite loop
- always observable as an `RetryAfterContextTrimEvent`

---

## Proposed Implementation Phases

### Phase 1 — Telemetry primitives

Build the data model and event capture before rendering anything.

Deliverables:
- `ContextSnapshot`, `ContextBreakdownItem`, `ContextContributor` in `glue_core`
- `ContextSnapshotEvent`, `ContextOverflowEvent`, etc. in `glue_core/session_event.dart`
- a context snapshot builder in `glue_harness/lib/src/agent/context_snapshot_builder.dart`, invoked from `AgentCore` before each provider request
- event emission for current truncation/rejection paths

Likely files:
- `packages/glue_core/lib/src/context_telemetry.dart` (new)
- `packages/glue_core/lib/src/session_event.dart`
- `packages/glue_harness/lib/src/agent/agent_core.dart`
- `packages/glue_harness/lib/src/agent/prompts.dart`
- `packages/glue_harness/lib/src/agent/context_snapshot_builder.dart` (new)
- `packages/glue_strategies/lib/src/llm/*.dart`
- `packages/glue_strategies/lib/src/web/fetch/*.dart`
- `packages/glue_harness/lib/src/observability/*.dart` (attach context attributes to per-turn span)

### Phase 2 — `/context` MVP (CLI surface)

Deliverables:
- `/context` slash command in `cli/lib/src/commands/builtin_commands.dart` and registered in `cli/lib/src/commands/slash_commands.dart`
- textual report formatter in `cli/lib/src/commands/context_report_formatter.dart` (new)
- optional `--verbose`
- optional `--json` for debugging/automation

The formatter consumes structured `ContextSnapshot`s pulled from the
harness — no string-formatting in the harness.

### Phase 3 — Overflow/failure classification and recovery

Deliverables:
- typed exceptions in `glue_strategies/llm/llm_errors.dart`
- harness emits `ContextOverflowEvent` and a `ContextSnapshotEvent` on classification
- user-facing recovery messages (CLI formatter)
- optional one-shot retry path after deterministic trim, observable via `RetryAfterContextTrimEvent`

### Phase 4 — Docked panel v2 (CLI surface)

Deliverables:
- `ContextDockedPanel` in `cli/lib/src/ui/`
- overview, breakdown, contributors, failures, timeline sections
- navigation/drill-down UX

Leverages existing docked panel architecture in `cli/lib/src/ui/`.

### Phase 5 — ACP parity (server surface)

Deliverables:
- `session/context_snapshot` ACP request in `packages/glue_server/lib/src/acp/`
- mapping `ContextSnapshotEvent` / `ContextOverflowEvent` → ACP notifications

No new harness work; just surface plumbing.

---

## File-Level Impact Estimate

### Core + Harness runtime / telemetry
- `packages/glue_core/lib/src/context_telemetry.dart` (new)
- `packages/glue_core/lib/src/session_event.dart`
- `packages/glue_harness/lib/src/agent/agent_core.dart`
- `packages/glue_harness/lib/src/agent/prompts.dart`
- `packages/glue_harness/lib/src/agent/context_snapshot_builder.dart` (new)
- `packages/glue_harness/lib/src/observability/observability.dart`
- `packages/glue_harness/lib/src/observability/logging_http_client.dart`

### Strategies (provider error classification)
- `packages/glue_strategies/lib/src/llm/openai_client.dart`
- `packages/glue_strategies/lib/src/llm/anthropic_client.dart`
- `packages/glue_strategies/lib/src/llm/ollama_client.dart`
- `packages/glue_strategies/lib/src/llm/llm_errors.dart` (new)
- `packages/glue_strategies/lib/src/web/fetch/web_fetch_client.dart`

### CLI surface
- `cli/lib/src/commands/builtin_commands.dart`
- `cli/lib/src/commands/slash_commands.dart`
- `cli/lib/src/commands/context_report_formatter.dart` (new)
- `cli/lib/src/ui/` (panel v2)
- `cli/lib/src/app/render_pipeline.dart` (if rendering inline notices)

### ACP surface (phase 5)
- `packages/glue_server/lib/src/acp/`

### Tests
- `packages/glue_strategies/test/llm/` for overflow classification
- `packages/glue_harness/test/agent/context_snapshot_builder_test.dart`
- `packages/glue_harness/test/observability/` for span emission
- `cli/test/commands/` for `/context`
- `cli/test/ui/` for panel v2
- `packages/glue_server/test/acp/` for ACP mapping

---

## Open Questions

1. **Can we compute a trustworthy current context-window max per model at runtime?**
   - `glue_core/model_catalog.dart` has context window info; provider-side effective limits may differ.

2. **Do we want `/context --json` in MVP, or is that premature?**
   - Useful for debugging and ACP testing. Cheap to ship if the data model is already structured. Recommend yes.

3. **Should context snapshots be persisted every turn, or only on demand + on failure?**
   - Every turn gives better timeline data but raises log volume.
   - Recommend: lightweight snapshot per turn (just totals + categories), full breakdown on demand and on failure.

4. **Do we ship failure classification and `/context` in the same PR, or split them?**
   - Same PR is cleaner conceptually; separate PRs reduce risk.

5. **When we eventually add compaction, do we compact messages only, or tool results first?**
   - Telemetry should answer this before we guess.

---

## Adversarial Review

### What could go wrong?

#### 1. Fake precision

If we estimate tokens and present them as exact percentages without labels, `/context` becomes theater.

**Mitigation:** confidence markers on every item.

#### 2. Wrong abstraction layer

If the implementation lives in slash-command string formatting logic (CLI), the future panel and ACP endpoint will require a rewrite.

**Mitigation:** telemetry model in `glue_core`, snapshot builder in `glue_harness`, formatter in `cli`.

#### 3. Over-scoped MVP

A docked interactive panel, timeline engine, and recovery system in one shot is too much.

**Mitigation:** chat output MVP first.

#### 4. Telemetry overload

Full-fidelity snapshots every turn make logs noisy and expensive.

**Mitigation:** keep snapshots compact; store structured contributor summaries, not raw duplicated payload text.

#### 5. Broken trust on provider failures

If Glue auto-retries with aggressive trimming and silently changes what the model sees, debugging becomes harder.

**Mitigation:** one retry max; explicit user-facing message; `RetryAfterContextTrimEvent` always logged.

---

## Acceptance Criteria

### Phase 1

- Glue emits structured context-related typed `SessionEvent`s for:
  - truncated project instructions
  - rejected oversized file expansions
  - truncated tool/web payloads
  - provider context overflow failures
- A `ContextSnapshot` can be constructed at request time inside the harness.
- `SessionStore` persists context-related events without schema ambiguity (they're just `SessionEvent` variants).

### Phase 2

- `/context` exists as a visible slash command in the CLI.
- `/context` prints:
  - current usage vs max
  - breakdown by category
  - top contributors
  - warnings/suggestions
- Every line item is labeled exact / estimated / derived.
- Command output is useful even in sessions with no failures.

### Phase 3

- Provider overflow errors are classified into typed exceptions in `glue_strategies`.
- The harness emits `ContextOverflowEvent` + `ContextSnapshotEvent` when classification fires.
- Optional retry (if implemented) happens at most once and is observable via `RetryAfterContextTrimEvent`.

### Phase 4

- Right-side docked panel can render the same telemetry model used by `/context`.
- Panel supports overview + at least one drill-down dimension.

### Phase 5

- `glue serve` exposes `session/context_snapshot` returning the same snapshot shape.
- ACP clients can subscribe to context-related events.

---

## Recommended Execution Order

1. Add data model in `glue_core`.
2. Instrument current truncation/rejection paths in `glue_harness` + `glue_strategies` to emit typed events.
3. Add `ContextSnapshotBuilder` invoked from `AgentCore`.
4. Add `/context` CLI formatter + slash command.
5. Normalize provider overflow failures into typed exceptions.
6. Only then start the docked panel.
7. ACP parity last.

Anything else is backwards.

---

## Notes

This plan is based on direct inspection of the live Glue runtime, not just external tool research.

The most important non-obvious conclusion:

> Glue already has several smart local guardrails against oversized inputs, but it does not yet have a first-class session compaction system or a truthful context-inspection surface.

The right move is not to fake a `/context` command from `tokenCount` and vibes. The right move is to build context telemetry as a harness primitive, with a `glue_core` data model, and let `/context` be the first user-facing consumer. ACP and the docked panel come for free.
