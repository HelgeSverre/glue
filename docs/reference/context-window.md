# Context Window Management

Glue automatically fits conversations into the LLM's context budget before each call using a three-tier pipeline. The original `_conversation` list is **never mutated** — only the view sent to the provider is affected.

**Visual explainer:** [context-window.html](./context-window.html)  
**Source:** `cli/lib/src/context/` (branch: `copilot/add-context-window-management-system`)

---

## How it works

Before every LLM call, `AgentCore` passes the conversation through `ContextManager.prepareForLlm()`. Three tiers are applied in order of increasing aggressiveness:

```
_conversation (full, never mutated)
    │
    ▼ prepareForLlm()
┌─────────────────────────────────────────────────┐
│  Tier 1 · Always                                │
│  ToolResultTrimmer                              │
│  Replace old (> toolResultTrimAfter turns)      │
│  large (> 200 tokens) tool results              │
│  with compact placeholders. Zero LLM cost.      │
└──────────────────────┬──────────────────────────┘
                       │
              estimated > 80% of inputBudget?
                       │ YES
                       ▼
┌─────────────────────────────────────────────────┐
│  Tier 2 · When > 80%                            │
│  ConversationCompactor                          │
│  Summarize all but last keepRecentTurns         │
│  user turns using a small model.                │
│  Inserts a synthetic summary message.           │
└──────────────────────┬──────────────────────────┘
                       │
           still > 95% after compaction?
                       │ YES
                       ▼
┌─────────────────────────────────────────────────┐
│  Tier 3 · When > 95%                            │
│  SlidingWindowTrimmer                           │
│  Drop oldest complete turns until              │
│  estimate drops to the 80% target.              │
│  Prepend "[N messages removed]" marker.         │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
           LLM receives trimmed view
```

Two additional paths exist outside the normal tiers:

- **Provider overflow:** If the LLM rejects mid-stream with a context error, `OverflowClassifier` detects the provider-specific message, triggers an emergency trim to 60% of budget, and retries the current turn once. The `overflowRetried` flag prevents infinite loops.
- **Manual `/compact`:** The `/compact` slash command calls `forceCompact()`, which runs Tier 2 unconditionally regardless of current usage level. Useful to clear headroom before starting a new task.

---

## Budget arithmetic

Given a model with a 200K context window (e.g. `claude-sonnet-4-6`):

| Value                 | Formula                                        | Result         |
| --------------------- | ---------------------------------------------- | -------------- |
| `contextWindowTokens` | —                                              | 200,000        |
| `reservedHeadroom`    | `maxOutputTokens` (8192) + tool schemas (1024) | 9,216          |
| `inputBudget`         | `contextWindow − reservedHeadroom`             | 190,784        |
| `compactAt`           | `inputBudget × compactThreshold`               | ~152,627 (80%) |
| `criticalAt`          | `inputBudget × criticalThreshold`              | ~181,245 (95%) |

Source: `cli/lib/src/context/context_budget.dart · ContextBudget.fromModelDef()`

---

## Token estimation

`ContextEstimator` uses a character-based heuristic (~4 chars/token) and self-calibrates via an exponential moving average after each turn:

```
calibrationRatio = 0.7 × old + 0.3 × (actual / raw)
```

Actual token counts come from the provider's `UsageInfo.inputTokens` reported after each successful LLM call. The calibration keeps estimates accurate even as the model's tokenization differs from the simple heuristic.

Source: `cli/lib/src/context/context_estimator.dart`

---

## Configuration

All thresholds are configurable in `~/.glue/config.yaml`:

```yaml
context:
  auto_compact: true # enable Tier 2 (summarization)
  compact_threshold: 0.80 # fire Tier 2 at 80% of inputBudget
  critical_threshold: 0.95 # fire Tier 3 at 95%
  keep_recent_turns: 4 # always keep last 4 user turns verbatim
  tool_result_trim_after: 3 # trim tool results older than 3 turns
```

| Key                      | Default | Effect                                                                                                  |
| ------------------------ | ------- | ------------------------------------------------------------------------------------------------------- |
| `auto_compact`           | `true`  | Enable Tier 2 summarization. Set `false` to use Tier 1+3 only (e.g. when no small model is configured). |
| `compact_threshold`      | `0.80`  | Fraction of `inputBudget` that triggers Tier 2.                                                         |
| `critical_threshold`     | `0.95`  | Fraction that triggers Tier 3 after Tier 2 is insufficient.                                             |
| `keep_recent_turns`      | `4`     | User turns always kept verbatim, never compacted or dropped.                                            |
| `tool_result_trim_after` | `3`     | Tier 1 truncates tool results older than this many turns.                                               |

Source: `cli/lib/src/context/context_config.dart`, `cli/lib/src/config/glue_config.dart`

---

## Manual compaction

Type `/compact` inside a running Glue session to force Tier 2 compaction at any time:

```
/compact    Summarize older conversation to free context space
```

The response shows how many tokens were freed:

```
Compacted: freed ~48,200 tokens (summary ~580 tokens).
```

Source: `cli/lib/src/app.dart · /compact slash command`

---

## Key design decisions

- **Non-destructive:** `_conversation` is never mutated. `prepareForLlm()` returns a new list.
- **Tier 2 is optional:** If no small model is configured, the system falls back to Tier 1 + Tier 3 gracefully.
- **One-shot overflow retry:** `overflowRetried` resets per user turn, so each turn gets at most one emergency retry.
- **Emergency target is 60%:** Aggressive enough that the retry reliably succeeds even if the estimator is off.
- **Observability:** Spans are emitted for `context.compact`, `context.compact_failed`, `context.sliding_window`, and `context.small_model_unavailable`.

---

## Source map

| File                                  | Responsibility                                                        |
| ------------------------------------- | --------------------------------------------------------------------- |
| `context/context_manager.dart`        | Master orchestrator: `prepareForLlm`, `emergencyTrim`, `forceCompact` |
| `context/context_budget.dart`         | Token budget math from model definition                               |
| `context/context_estimator.dart`      | Character-heuristic estimation + EMA calibration                      |
| `context/context_config.dart`         | Configuration value object                                            |
| `context/tool_result_trimmer.dart`    | Tier 1: truncate old large tool results                               |
| `context/conversation_compactor.dart` | Tier 2: summarize with small model                                    |
| `context/sliding_window_trimmer.dart` | Tier 3: drop oldest complete turns                                    |
| `context/overflow_handler.dart`       | Provider-specific overflow error classification                       |
| `agent/agent_core.dart`               | Integration point: calls `prepareForLlm` and handles overflow retry   |
| `app.dart`                            | `/compact` slash command registration                                 |
