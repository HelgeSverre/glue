# Context Inspector and Telemetry — Research + Implementation Plan

> Status: research / design. No code changes yet.

## Goal

Give Glue users a truthful way to inspect how the active context window is being consumed, while also instrumenting the runtime so we can understand context growth, oversized payload failures, and future context-management regressions.

Concretely, this plan delivers:

1. A real `/context` slash command for the interactive TUI.
2. Structured context telemetry that can back both chat output (MVP) and a future docked right-side panel.
3. Error classification and tracking for provider calls that fail because request or response context is too large.
4. A clear model of how Glue currently manages context growth, where it already caps inputs, and where it currently has no first-class compaction story.

This is **not** just a slash command. `/context` is the UX surface for a broader context-observability subsystem.

---

## Scope Statement

Add context telemetry to Glue's runtime so developers can inspect current context usage, identify the largest contributors, and debug context-related failures without guessing.

---

## Current State Audit

### What Glue already tracks

#### 1. Aggregate per-turn token usage exists

`cli/lib/src/agent/agent_core.dart`

- `UsageInfo` captures `inputTokens` + `outputTokens`.
- `AgentCore.tokenCount` accumulates `totalTokens` over the session.
- This is fed by provider-specific parsers in:
  - `cli/lib/src/llm/openai_client.dart`
  - `cli/lib/src/llm/anthropic_client.dart`
  - `cli/lib/src/llm/ollama_client.dart`

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

Glue already has an observability layer:

- `cli/lib/src/observability/observability.dart`
- `cli/lib/src/observability/logging_http_client.dart`
- `cli/lib/src/observability/file_sink.dart`
- `cli/lib/src/observability/http_trace_sink.dart`

Capabilities already present:
- spans for tool execution (`tool.<name>`)
- spans for outbound HTTP requests (`http.<kind>`)
- redacted body/header logging
- max-body truncation in logs
- sink abstraction suitable for file/HTTP export

**Gap:** this is generic request/tool tracing, not context telemetry.

#### 3. Session storage already supports append-only event logging

`docs/reference/session-storage.md`

Sessions store:
- `meta.json`
- `conversation.jsonl`
- `state.json`

Current conversation events include:
- `user_message`
- `assistant_message`
- `tool_call`
- `tool_result`

**Opportunity:** context snapshots and overflow/truncation events can be logged into the same append-only stream without inventing a second persistence model.

---

### How Glue currently mitigates context growth

Glue already has several **localized caps** and truncation safeguards.

#### 1. Project instruction files are capped at 50 KB

`cli/lib/src/agent/prompts.dart`

- `AGENTS.md` and `CLAUDE.md` are read into the system prompt.
- Each file is truncated if it exceeds `_maxGuidanceBytes = 50 * 1024`.
- Truncation is explicit: `"(truncated — file exceeded 50KB)"`.

**Good:** prevents runaway rules files from silently bloating the prompt.

**Bad:** no telemetry records how often this happens or how much was dropped.

#### 2. `@file` expansion rejects oversized files

Covered by tests in `cli/test/input/file_expander_test.dart`.

- Files over 100 KB are not fully expanded into prompt context.
- They render as `[too large: ...]` markers instead.

**Good:** direct user expansion has a hard guardrail.

**Bad:** the event is not surfaced as structured telemetry or context diagnostics.

#### 3. Web/browser/fetch tool content is token-truncated

Key files:
- `cli/lib/src/web/fetch/truncation.dart`
- `cli/lib/src/web/fetch/web_fetch_client.dart`
- `cli/lib/src/tools/web_browser_tool.dart`

Patterns in use:
- content is approximated to token counts via `TokenTruncation`
- outputs are clipped to a configured/derived token budget
- truncation markers are appended to results

**Good:** large remote content does not blindly enter context.

**Bad:** this uses estimated token math and the truncation decision is not exposed in a central event stream.

#### 4. Some oversized web responses are rejected outright

`cli/test/web/fetch/web_fetch_client_test.dart`

Tests assert explicit failure when response size exceeds the byte limit:
- `"Response too large: ... bytes (max ...)"`

**Good:** Glue already has the right instinct for very large payloads — fail fast.

**Bad:** no normalized failure type; this is just an error string.

#### 5. Ollama `num_ctx` is bounded

`cli/lib/src/llm/ollama_client.dart`

- `ollamaNumCtxCeiling = 131072`
- catalog context windows are capped before being sent as `options.num_ctx`

**Good:** avoids absurd context claims causing local OOM issues.

**Bad:** this is model/request shaping, not session introspection.

#### 6. Session fork replays truncated history slices

`cli/lib/src/session/session_manager.dart`

- `forkSession()` truncates the replayed event history to a selected branch point.

**Good:** state branching is not blindly replaying everything.

**Bad:** this is not compaction or long-session context management.

---

### What Glue does **not** appear to have yet

This is the critical gap analysis.

#### 1. No first-class conversation compaction runtime

I searched for:
- `compact`
- `autocompact`
- compaction thresholds
- context checkpointing
- summarization of old turns before provider calls

What exists:
- tests/autocomplete references to `/compact`
- design docs and plans discussing compaction or thinking tokens

What I did **not** find in live runtime code:
- a compactor service
- a slash command implementation for `/compact`
- automatic turn compaction at token thresholds
- summarizer-driven checkpointing
- replacement of older conversation turns with compact summaries

**Working conclusion:** Glue currently uses edge truncation and payload caps, but does not yet have a first-class session compaction story comparable to Claude Code, OpenCode, Cline, or Kiro.

#### 2. No normalized classification of context-overflow failures

I did not find a dedicated error normalization layer for:
- prompt/context window exceeded
- request payload too large
- provider refused overlong input
- tool output too large for safe inclusion

Current behavior appears to be:
- provider HTTP error bubbles up as generic exception text
- logs contain truncated request/response bodies
- user gets a low-level failure rather than a context-specific explanation

#### 3. No current context snapshot model

There is no existing runtime object like:
- `ContextSnapshot`
- `ContextBreakdown`
- `TopContributor`
- `ContextFailureEvent`

So `/context` cannot be implemented truthfully yet without first adding these primitives.

---

## Why this work matters

### User-facing reasons

1. **Debugging degraded sessions**
   - When the agent starts getting vague or forgetful, users need to know whether the issue is context growth, not model quality.

2. **Debugging payload failures**
   - When a provider request errors because the prompt got too large, the user should see what filled it.

3. **Reducing superstition**
   - Without visibility, users cargo-cult around `/clear`, model switches, and narrower prompts without understanding the real bottleneck.

### Product/engineering reasons

1. **Telemetry before optimization**
   - We should not build compaction, caching, or retrieval improvements blind.

2. **Future right-panel UI needs structured data anyway**
   - If we only build a string-producing slash command now, we will rewrite it later.

3. **Trust**
   - A `/context` command that invents precise-looking numbers from vibes is worse than nothing. Structured telemetry prevents that.

---

## External Research Summary

### Relevant precedents

#### Claude Code
Strongest precedent.

- Built-in `/context` command reportedly shows category-level usage:
  - system prompt
  - system tools
  - MCP tools
  - memory files
  - skills
  - messages
  - free space
  - auto-compact buffer
- Also has `/compact` and auto-compaction as first-class concepts.

#### Aider
Related, but not equivalent.

- `/tokens` exposes token usage for current context.
- `/context` means "context mode" rather than global occupancy breakdown.
- Shows that exposing raw counts is useful, but it is not enough for Glue's goal.

#### GitHub Copilot / Kiro / Cline / Roo / OpenCode
Useful product patterns mentioned in research corpus:
- context usage gauges in UI
- auto-summarization / compaction thresholds
- explicit context management guidance
- context-aware failure recovery
- session-level context pressure indicators

### Product lesson from external tools

The tools that handle context well do **at least one** of these:
- expose visible usage meters
- compact/summarize when near limit
- maintain persistent structured memory/checkpoints
- use retrieval/scoping to avoid bloating the main window
- track token/cost/usage as first-class telemetry

Glue currently does some localized truncation, but not enough of the above.

---

## Product Shape

### MVP (v1): `/context` prints a report in chat output

This is the right first surface.

When the user types `/context`, Glue prints a textual report like:

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

- no right-side panel yet
- no live auto-updating dashboard
- no drill-down interactivity
- no compaction implementation in the same PR

### V2: docked right-side context panel

Use the same telemetry model to render a docked panel with sections/tabs:

1. **Overview**
   - current used / max / free
   - percentage
   - risk level

2. **Breakdown**
   - category table
   - exact vs estimated markers

3. **Contributors**
   - top files, tool results, prompt sections, message groups

4. **Timeline**
   - turn-by-turn growth
   - spikes after tool calls or file reads

5. **Failures**
   - context overflow
   - request too large
   - truncated payload events
   - retry outcomes

Because Glue already has `DockManager`, `DockedPanel`, and right-side docking support, this is realistic — but only if telemetry is structured from day one.

---

## Recommended Data Model

### Context snapshot

```dart
class ContextSnapshot {
  final DateTime timestamp;
  final String modelRef;
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

### Per-turn telemetry

```dart
class ContextTurnTelemetry {
  final String turnId;
  final DateTime timestamp;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  final int? requestBytes;
  final int? responseBytes;
  final ContextSnapshot? snapshotBefore;
  final ContextSnapshot? snapshotAfter;
  final List<ContextEvent> events;
}
```

### Context events

```dart
sealed class ContextEvent {
  const ContextEvent();
}

class ToolResultTruncated extends ContextEvent {
  final String toolName;
  final int originalBytes;
  final int keptBytes;
}

class WebResponseRejected extends ContextEvent {
  final int sizeBytes;
  final int limitBytes;
}

class ProviderContextOverflow extends ContextEvent {
  final String provider;
  final String model;
  final String rawMessage;
}

class RetryAfterContextTrim extends ContextEvent {
  final String strategy;
}

class ProjectInstructionTruncated extends ContextEvent {
  final String path;
  final int originalBytes;
  final int keptBytes;
}

class FileExpansionRejected extends ContextEvent {
  final String path;
  final int sizeBytes;
  final int limitBytes;
}
```

### Critical design rule

Every reported count must carry a confidence level:
- **exact** — from provider/runtime/accounted bytes/tokens
- **estimated** — token estimation logic (char-count heuristics, etc.)
- **derived** — inferred from higher-level totals

No unlabeled fake precision.

---

## Where the numbers can come from

### Exact today

We can already get exact or near-exact values for:
- provider-reported `prompt_tokens` / `input_tokens`
- provider-reported `completion_tokens` / `output_tokens`
- byte sizes of logged request/response bodies
- size of instruction files before/after truncation
- size of tool results before/after truncation/rejection

### Estimated in v1

We will likely need estimation for:
- tokens attributable to instruction file sections
- tokens attributable to message history slices
- tokens attributable to loaded tool schemas
- tokens attributable to file reads and tool results currently present in effective prompt context

If exact tokenizer infrastructure exists per model later, we can upgrade these from estimated to exact. For v1, estimates are acceptable only if marked.

---

## Failure Handling Plan

Glue needs a normalized ladder for oversized prompt/response failures.

### New normalized failure classes

At minimum:
- `contextWindowExceeded`
- `requestPayloadTooLarge`
- `responsePayloadTooLarge`
- `toolOutputTooLarge`

### Recovery behavior

For provider request overflow:
1. classify the error
2. emit a `ProviderContextOverflow` event
3. capture a `ContextSnapshot`
4. surface a useful user-facing message
5. optionally retry once after deterministic trimming if safe

### User-facing message shape

Instead of a raw provider error, the user should see something like:

> Request exceeded the model context budget. The largest contributors were conversation history and a recent tool result. Run `/context` to inspect details, or retry after narrowing scope.

### Retry rules

- at most one automatic retry
- only after a deterministic trim strategy
- never infinite loop

---

## Proposed Implementation Phases

### Phase 1 — Telemetry primitives

Build the data model and event capture before rendering anything.

Deliverables:
- `ContextSnapshot`
- `ContextBreakdownItem`
- `ContextContributor`
- `ContextTurnTelemetry`
- `ContextEvent` types
- a context snapshot builder invoked before each provider request
- event emission for current truncation/rejection paths

Likely files:
- `cli/lib/src/agent/agent_core.dart`
- `cli/lib/src/agent/prompts.dart`
- `cli/lib/src/llm/*.dart`
- `cli/lib/src/observability/*.dart`
- session logging/storage files

### Phase 2 — `/context` MVP

Deliverables:
- `/context` slash command
- textual report renderer for current snapshot
- optional `--verbose`
- optional `--json` if cheap

Likely files:
- `cli/lib/src/commands/builtin_commands.dart`
- `cli/lib/src/commands/slash_commands.dart`
- app/controller wiring
- report formatter file (new)

### Phase 3 — overflow/failure classification and recovery

Deliverables:
- normalized context-related provider errors
- telemetry events for overflow/rejection
- user-facing recovery messages
- one-shot retry path after deterministic trim (if safe)

### Phase 4 — docked panel v2

Deliverables:
- `ContextDockedPanel`
- overview, breakdown, contributors, failures, timeline sections
- navigation/drill-down UX

Leverages existing docked panel architecture.

---

## File-Level Impact Estimate

### Core runtime / telemetry
- `cli/lib/src/agent/agent_core.dart`
- `cli/lib/src/agent/prompts.dart`
- `cli/lib/src/llm/openai_client.dart`
- `cli/lib/src/llm/anthropic_client.dart`
- `cli/lib/src/llm/ollama_client.dart`
- `cli/lib/src/observability/observability.dart`
- `cli/lib/src/observability/logging_http_client.dart`
- session logging/storage files

### Command surface
- `cli/lib/src/commands/builtin_commands.dart`
- possibly command formatter/helper files

### TUI v2
- `cli/lib/src/ui/docked_panel.dart`
- `cli/lib/src/ui/dock_manager.dart`
- new context panel file(s)
- app render/event plumbing as needed

### Tests
- llm provider tests for overflow classification
- command tests for `/context`
- observability/session tests for event emission
- panel tests for v2

---

## Open Questions

1. **Can we compute a trustworthy current context-window max per model at runtime?**
   - Catalog metadata likely has context window info, but provider-side effective limits may differ.

2. **Do we want `/context --json` in MVP, or is that premature?**
   - It is useful for debugging and future automation, but not required for first user value.

3. **Should context snapshots be persisted every turn, or only on demand + on failure?**
   - Every turn gives better timeline data but raises log volume.

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

If the whole implementation lives in slash-command string formatting logic, the future panel will require a rewrite.

**Mitigation:** telemetry model first, report renderer second.

#### 3. Over-scoped MVP

A docked interactive panel, timeline engine, and recovery system in one shot is too much.

**Mitigation:** chat output MVP first.

#### 4. Telemetry overload

If every turn records huge snapshots in full fidelity, logs become noisy and expensive.

**Mitigation:** keep snapshots compact; store structured contributor summaries, not raw duplicated payload text.

#### 5. Broken trust on provider failures

If Glue auto-retries with aggressive trimming and silently changes what the model sees, debugging becomes harder.

**Mitigation:** one retry max; explicit user-facing message; event logged.

---

## Acceptance Criteria

### Phase 1

- Glue emits structured context-related telemetry events for:
  - truncated project instructions
  - rejected oversized file expansions
  - truncated tool/web payloads
  - provider context overflow failures
- A `ContextSnapshot` can be constructed at request time.
- Session/event logging can persist context-related events without schema ambiguity.

### Phase 2

- `/context` exists as a visible slash command.
- `/context` prints:
  - current usage vs max
  - breakdown by category
  - top contributors
  - warnings/suggestions
- Every line item is labeled exact / estimated / derived.
- Command output is useful even in sessions with no failures.

### Phase 3

- Provider overflow errors are normalized and surfaced clearly.
- At least one context-overflow path emits a structured failure event.
- Optional retry (if implemented) happens at most once and is observable.

### Phase 4

- Right-side docked panel can render the same telemetry model used by `/context`.
- Panel supports overview + at least one drill-down dimension.

---

## Recommended Execution Order

1. Instrument current truncation/rejection paths.
2. Add `ContextSnapshot` builder.
3. Add `/context` chat renderer.
4. Normalize provider overflow failures.
5. Only then start the docked panel.

Anything else is backwards.

---

## Notes

This plan is based on direct inspection of the live Glue runtime, not just external tool research.

The most important non-obvious conclusion is this:

> Glue already has several smart local guardrails against oversized inputs, but it does not yet appear to have a first-class session compaction system or a truthful context-inspection surface.

That means the right move is not to fake a `/context` command from `tokenCount` and vibes. The right move is to build context telemetry as a runtime primitive and let `/context` be the first user-facing consumer of that data.
