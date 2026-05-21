# Context Window Management: Visual Explainer

## Context

The `copilot/add-context-window-management-system` branch adds a sophisticated three-tier system that automatically manages token budgets when conversations grow large. The current main branch passes the full conversation history unfiltered to LLM providers — the new system adds an intelligent pre-processing step before each LLM call.

The goal is to create a self-contained visual HTML explainer + companion markdown doc that lets anyone quickly grasp how the system works through interactive scenario walkthroughs.

---

## What the Branch Adds (explored via git diff)

**New files:** `cli/lib/src/context/` module:
- `context_manager.dart` — Master orchestrator (prepareForLlm, emergencyTrim, forceCompact)
- `context_budget.dart` — Computes token budget from model definition
- `context_estimator.dart` — Self-calibrating token estimation (EMA, 4 chars/token baseline)
- `context_config.dart` — Config: compactThreshold (0.80), criticalThreshold (0.95), keepRecentTurns (4), toolResultTrimAfter (3)
- `overflow_handler.dart` — Detects provider-specific overflow errors
- `tool_result_trimmer.dart` — Tier 1: truncates old tool results > 200 tokens
- `conversation_compactor.dart` — Tier 2: summarizes old turns with small model
- `sliding_window_trimmer.dart` — Tier 3: drops oldest complete turns

**Modified:** `agent_core.dart` (prepareForLlm before each llm.stream call), `app.dart` (/compact slash command), `glue_config.dart` (context: config section), `service_locator.dart` (wires ContextManager)

---

## Three-Tier Architecture

```
Conversation history (original, never mutated)
    ↓
ContextManager.prepareForLlm()
    ├─ Tier 1: ToolResultTrimmer  → Always applied
    │   Replace old (>3 turns) large (>200 tok) tool results with placeholders
    ├─ Tier 2: ConversationCompactor  → When > 80% full
    │   Summarize all-but-last-N turns using a small model
    └─ Tier 3: SlidingWindowTrimmer  → When > 95% full after Tier 2
        Drop oldest complete turns until fit, prepend trim marker
    ↓
LLM receives trimmed/compacted view
```

**Emergency path:** On provider overflow error → emergency trim to 60%, retry once.
**Manual path:** `/compact` slash command triggers Tier 2 on demand.

---

## Implementation Plan

### Step 1: Fetch branch and read source files

```bash
git fetch origin copilot/add-context-window-management-system
```

Read these files from the branch to use accurate code details:
- `origin/copilot/add-context-window-management-system:cli/lib/src/context/context_manager.dart`
- `origin/copilot/add-context-window-management-system:cli/lib/src/context/context_budget.dart`
- `origin/copilot/add-context-window-management-system:cli/lib/src/context/context_config.dart`
- `origin/copilot/add-context-window-management-system:cli/lib/src/context/context_estimator.dart`
- `origin/copilot/add-context-window-management-system:cli/lib/src/agent/agent_core.dart`

### Step 2: Create `docs/reference/context-window.html`

A **single self-contained HTML file** (no external deps, inline CSS + JS) with:

**Design:** Terminal/monospace aesthetic (dark bg, green/amber accents) matching Glue's identity.

**Structure:**
1. **Header** — Title, one-line description, links to config reference
2. **Architecture overview** — Static diagram showing the 3-tier waterfall with threshold markers
3. **Token bar widget** — Reusable animated bar showing usage vs compactAt/criticalAt/limit
4. **6 interactive scenario tabs:**

| # | Scenario | Budget used | What happens |
|---|----------|-------------|--------------|
| 1 | Normal conversation | < 80% | Pass-through, no management |
| 2 | Old tool results pile up | < 80% (Tier 1 only) | Tier 1 trims old large results |
| 3 | Long session → 80% | 80–95% | Tier 1 + Tier 2 compaction |
| 4 | Very long session → 95%+ | > 95% | All three tiers |
| 5 | Provider overflow mid-stream | overflow | Emergency trim 60%, retry |
| 6 | Manual `/compact` | any | User-triggered Tier 2 |

**Per scenario layout:**
- Token budget bar (animated fill to the scenario's usage level)
- "Before" message list (original conversation with realistic placeholder content)
- Action panel (which tier fires, why, what it does)
- "After" message list (what gets sent to the LLM, with visual diff highlights)
- Small code callout box with the relevant source file + method

**Visual language:**
- Message bubbles: user (right-aligned, blue), assistant (left, gray), tool_result (monospace, amber)
- Trimmed content: red strikethrough or faded + placeholder label
- Summary message: purple/indigo with "✦ Summary" badge
- Dropped turns: shown briefly then fade out (CSS animation)
- Threshold lines on token bar: labeled "compact" (80%) and "critical" (95%)

**Config reference section:**
- YAML snippet showing all context: settings with their defaults and effect

### Step 3: Create `docs/reference/context-window.md`

Concise markdown companion covering:
- What context window management is and why it's needed
- The three tiers explained in prose
- Threshold diagram (ASCII)
- Config options table
- How to use `/compact` manually
- Link to the HTML visual

---

## Files to Create

| File | What |
|------|------|
| `docs/reference/context-window.html` | Self-contained visual explainer (new) |
| `docs/reference/context-window.md` | Markdown reference doc (new) |

No existing files are modified.

---

## Verification

1. Open `docs/reference/context-window.html` in a browser — all 6 scenario tabs should render and be clickable
2. Token bars should animate on tab switch
3. Before/after message lists should match the real implementation (verify against branch source)
4. Markdown file should render cleanly in GitHub/VitePress
5. HTML should be fully self-contained (`file://` open works, no network requests)
