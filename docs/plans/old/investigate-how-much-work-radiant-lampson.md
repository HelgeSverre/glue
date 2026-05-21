# Investigation: Background Agents + Gemini Deep Research

## Context

Two adjacent questions, scoped together because the second motivates the first:

1. **How much work to add fire-and-forget agent runs?** — User submits a long task, control returns to the prompt immediately, results surface when ready. Today the active `Turn` blocks the prompt; only one turn is alive at a time.
2. **Can we use Gemini Deep Research today?** — Two model variants (`deep-research-preview-04-2026`, `deep-research-max-preview-04-2026`) exist on the Gemini Interactions API. They're already catalogued (`docs/reference/models.yaml:236-253`) but disabled with the note "Requires background-execution runner — not yet wired up in Glue."

User direction: ship Deep Research as a **tool first**, then revisit a model-selectable surface once background-turn infrastructure exists.

The two efforts are independent and can land in either order, but Deep Research's 20–60 min runtime makes the tool largely unusable from an interactive session without background turns — so the natural sequence is: DR tool (small) → background turns (medium-large) → DR-as-model (small follow-up).

---

## Part 1 — Background / fire-and-forget agent turns

### Current shape (what already exists)

- **`AgentRunner.runHeadless`** (`cli/lib/src/agent/agent.dart:483-517`) already drives an agent to completion without a UI turn. It takes an `onEvent` callback. This is the right primitive — background turns don't need new agent infrastructure.
- **`Subagents`** (`cli/lib/src/agent/subagents.dart:43-176`) already broadcasts `SubagentUpdate`s via a `StreamController.broadcast()` and the app already multiplexes them into the transcript without blocking (`app.dart:344-346`). Same shape applies to background turns — we'd add a sibling broadcast stream.
- **`SpawnParallelSubagentsTool`** (`cli/lib/src/tools/subagent_tools.dart:63-122`) runs parallel subagents inside a turn, but the parent `Future.wait`s on them. So intra-turn concurrency exists; **inter-turn concurrency does not**.
- **UI primitives are in place**: `DockManager` + `Panels` (`cli/lib/src/ui/services/`) can render side-by-side panels and overlays; the transcript can already render `SubagentGroup` collapsibles for non-linear progress.

### What needs to change

| Concern | Today | Required change |
|---|---|---|
| Active turn | `App._currentTurn` singleton (`app.dart:76`) | Map of `turnId → Turn`, with one "foreground" turn for input echo and N "background" turns running in parallel |
| Event routing | `AgentEvent`s have no turn ID | Add `turnId` to events (or wrap in a routed envelope at the Turn boundary, mirroring `SubagentUpdate`) |
| Transcript | Append-only single thread | Either (a) inline background results as collapsed entries when they finish, or (b) per-turn transcript threads with a switcher. Start with (a) — much cheaper |
| Permission gate | Per-turn, blocks on user modal | Background turns must use `ToolApprovalPolicy.allowlist` (same as subagents) — read-only by default, no modals. Mutating tools = explicit deny in background mode |
| Session store | One active session (`SessionManager.currentSessionId`) | Background turns belong to the current session; their messages append to the same transcript when they complete |
| Cancellation | `_currentTurn?.cancel()` on Ctrl-C | New `/bg` slash command family: `/bg list`, `/bg cancel <id>`, `/bg show <id>` |
| Status surface | None | Status-zone line or dock: "🔄 2 background tasks running" with collapse-to-detail |

### Scope estimate

**Medium-large, ~1–2 weeks of focused work**, naturally phased:

1. **Phase A — turn registry + ID propagation** (~1–2 days). Replace `_currentTurn` with `TurnRegistry`. Stamp `turnId` on the `AgentEvent` envelope at the Turn boundary. No user-visible changes.
2. **Phase B — headless background turn driver** (~2–3 days). New `BackgroundTurn` that wraps `AgentRunner.runHeadless` with an `allowlist` permission policy. Slash command `/bg <prompt>` (or `&` postfix as a UX experiment). Result lands as a transcript entry when complete.
3. **Phase C — status surface + listing** (~2 days). Status-zone indicator, `/bg list`, `/bg cancel`, `/bg show`. Reuses `Panels` for an optional dock view.
4. **Phase D — persistence/resume** (~2 days, optional first cut). Survive CLI restart by writing background-turn state to session storage; on launch, decide whether to resume polling or mark as orphaned.

### Files most affected

- `cli/lib/src/runtime/turn.dart` — add `turnId`, decouple from `App._currentTurn`
- `cli/lib/src/runtime/app_events.dart` — new `BackgroundTurnSubmit`, `BackgroundTurnCompleted` events
- `cli/lib/src/app.dart` — turn registry (replace `_currentTurn`), event routing
- `cli/lib/src/runtime/transcript.dart` — accept out-of-order entries from completed background turns
- `cli/lib/src/runtime/commands/` — new `bg_command.dart` slash command family
- `cli/lib/src/ui/components/status_zone.dart` (new or extend) — background-task indicator

### Reuse rather than build

- Don't invent new agent infra — `runHeadless` + `Agent` are already correct.
- Don't invent new event broadcast — model after `Subagents._updateController` (`subagents.dart:51`).
- Don't invent new permission machinery — reuse `ToolApprovalPolicy.allowlist` (`subagents.dart:125`).

### Risks / open questions

- **Permission model in background**: must default to read-only. A background turn that wants to write files should fail loudly, not queue a modal.
- **Cost runaway**: a misfired `/bg` could spawn an expensive long run. Need a per-session budget guard or at least confirmation on first use.
- **Token usage attribution**: `obs/` traces are already context-scoped, so concurrent turns won't corrupt each other — but the cost summary in the status line needs to aggregate across turns.

---

## Part 2 — Gemini Deep Research

### Verdict

**Yes — usable today as a tool.** The Interactions API is in public beta, exposed through `google-genai` / `@google/genai` SDKs and via raw HTTP. The two target models (`deep-research-preview-04-2026`, `deep-research-max-preview-04-2026`) are GA-equivalent for preview purposes and already in our catalog.

### Why a tool, not a provider

- The Interactions API is a different wire shape from `streamGenerateContent` (which is what `GeminiProvider` at `cli/lib/src/providers/gemini_provider.dart` uses today). It returns an operation handle and requires polling or SSE-with-resume — incompatible with `LlmClient.stream()`'s "yield chunks until done" contract.
- Deep Research is a **one-shot research task that returns a cited report**, not a conversational model. Treating it as a chat model creates UX friction (you can't really "follow up" naturally).
- A tool fits the existing agent loop without contract changes: the agent calls `deep_research`, blocks on the result inside `Tool.execute()`, and gets back a structured report.
- Trade-off: without background turns, the entire session blocks for 20–60 min during a DR call. Acceptable as v0; a clear motivator for Part 1.

### Tool design sketch

New file `cli/lib/src/tools/deep_research_tool.dart`. Parameters:

| Param | Required | Notes |
|---|---|---|
| `query` | yes | The research question. Tool description guides users to provide context + tell the agent how to handle missing data |
| `mode` | no, default `preview` | `preview` (fast) \| `max` (comprehensive) |
| `collaborative_planning` | no, default `false` | Enables plan-review step before execution — useful for complex queries |
| `mcp_servers` | no | Array of `{name, url, headers, allowed_tools}` for remote MCP grounding |

Wire format (matches the public docs):

```json
POST https://generativelanguage.googleapis.com/v1beta/interactions
{
  "agent": "deep-research-preview-04-2026",
  "input": "<query>",
  "agent_config": {"type": "deep-research", "thinking_summaries": "auto", "collaborative_planning": false},
  "tools": [{"type": "google_search"}, {"type": "url_context"}],
  "background": true,
  "stream": true,
  "store": true
}
```

Then SSE-stream `content.delta` events, reconnecting via `?stream=true&last_event_id=...` if the connection drops at ~600 s. Final report aggregated from text deltas; cited URLs surface as part of the report content.

### Auth

Reuse `GEMINI_API_KEY` from existing `GeminiProvider` config. Same `x-goog-api-key` header.

### Best practices (bake into tool description)

- **Prompt for unknowns**: the tool description should instruct callers to add language like *"If specific figures for 2025 are not available, explicitly state they are projections or unavailable rather than estimating."*
- **Provide context up front**: DR cannot ask follow-up questions mid-run, so the prompt must be self-contained.
- **Collaborative planning** for high-stakes queries (e.g. "how would we implement Glue as a hosted SaaS coding agent?").
- **Cautious multimodal**: supported but expensive; surface as advanced parameter, not default.

### Limitations to surface in tool errors / docs

- Beta API — schemas may break.
- Max 60 min research time (most tasks ≤20 min); enforce a configurable timeout.
- No structured outputs.
- No custom function-calling tools — only Google Search / URL Context / Code Execution / File Search / remote MCP.
- `background=true` requires `store=true`. Free-tier retention is 1 day, paid 55 days. Cleanup the interaction after we've stored results.
- Costs roughly $1–3 (preview) or $3–7 (max) per task. Surface estimated cost up front; consider opt-in via config flag.
- Interactions API itself notes "Gemini 3 does not support remote MCP, this is coming soon" while the Deep Research page lists MCP as supported — verify at integration time.

### Scope estimate

**Small, ~2–3 days** for v0:

1. ~1 day — `gemini_interactions_client.dart` (HTTP + SSE wrapper for `interactions` endpoints; submit, stream, resume, get).
2. ~1 day — `deep_research_tool.dart` implementing `Tool`, calling the client, aggregating output, formatting cited report.
3. ~0.5 day — wiring: register in tool registry behind a config flag (`enable_deep_research_tool` defaults off), set `enabled: true` in `models.yaml` for the two DR variants only after we ship the model-selectable surface.
4. ~0.5 day — tests (unit-level on the response aggregator; live-tagged integration test).

### Files affected

- `cli/lib/src/llm/gemini_interactions_client.dart` (new)
- `cli/lib/src/tools/deep_research_tool.dart` (new)
- `cli/lib/src/boot/wire.dart` — register tool (gated)
- `cli/lib/src/config/glue_config.dart` — `enableDeepResearch` flag
- `docs/reference/models.yaml:227-253` — leave models disabled for now; flip when we add Part 3

---

## Part 3 — Deferred: Deep Research as selectable model

After Part 1 lands, revisit. With background turns in place, a `/model gemini/deep-research-preview-04-2026` selection becomes natural: the user submits a research prompt, the turn detaches into the background, and the cited report lands in the transcript when the SSE stream closes. This is the smaller follow-up (~1–2 days) that piggybacks on both prior phases.

---

## Verification

This is a research/scoping plan; verification means **review and approval of the recommended path**, not code execution. If we proceed to implementation, each phase has its own validation:

- **DR tool**: live-tagged test against `https://generativelanguage.googleapis.com/v1beta/interactions` with a small query (e.g. "Summarize the history of the Dart language in 200 words"); verify the tool returns a cited report under timeout.
- **Background turns**: e2e test that submits `/bg <long prompt>`, immediately submits a foreground prompt, and verifies both complete with correct event routing and transcript ordering.
- **DR-as-model**: model selection followed by long prompt; verify backgrounding and final transcript entry.

## Recommended next step

Spike the **Deep Research tool (Part 2)** first — it's small, ships independently, validates the Interactions API integration, and provides a forcing function for Part 1's UX (anyone who uses it once will feel the need for non-blocking turns).
