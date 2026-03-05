# Glue Market Positioning (March 5, 2026)

## Snapshot

Live OSS traction (GitHub stars, March 5, 2026):

- Gemini CLI: 96,557
- Codex CLI: 63,237
- Cline: 58,652
- Aider: 41,507
- Roo Code: 22,516
- Kilo Code: 16,252

This market is crowded, with multiple strong tools already covering "general AI coding assistant" positioning.

Additional major competitors in this space (including non-OSS or closed surfaces):

- GitHub Copilot (IDE + coding agent + CLI)
- Amp Code
- Augment Code

## What Competitors Signal

### 1) Focused-native stacks win on quality

- Codex is positioned as a coding agent from OpenAI and centered on OpenAI auth flow.
- Gemini CLI is explicitly positioned around Gemini models (Google account, Gemini API key, Vertex AI).

Implication: deep integration with a narrower model surface can outperform broad but shallow support.

### 2) Broad provider support exists, but is noisy

- Aider and Cline emphasize wide provider/model compatibility.
- Kilo Code pushes broad model access (500+ models) and MCP ecosystem through its own platform.

Implication: "supports everything" is table stakes for some users, but it is hard to make consistently excellent.

### 3) Enterprise path matters

- Claude Code docs include managed deployment pathways via Bedrock and Vertex, showing enterprise appetite for policy/compliance-friendly routing.
- Copilot and Augment emphasize team/enterprise workflows and integrated platform surfaces.

Implication: operational trust and governance can be a stronger moat than raw model count.

### 4) Platform bundling pressure is real

- Amp and Augment appear to optimize around tightly integrated platform experiences.
- Copilot is deeply integrated with GitHub workflows and multi-model selection.

Implication: competing as another generic paid platform is a weak position for Glue.

## Recommended Positioning for Glue

**"Operator-grade multi-agent terminal."**

Primary promise:

1. Best runtime UX for parallel agent work (streaming, overlays, focus model, searchable state).
2. Deterministic, auditable execution model (clear permission gates, reproducible runs, session lineage).
3. Curated model support with capability guarantees (not maximal provider sprawl).

## Product Constraints (Intentional)

Given strategic constraints:

- No paid Glue backend
- No attempt to outspend major platforms

Glue should be:

1. Local-first and BYO-key first
2. Minimal, explicit, and auditable ("no magic")
3. Best-in-class TUI ergonomics + rendering performance
4. Extensible through user-owned commands/flows/agents

## Model Strategy Recommendation

Use a tiered support model:

1. **Tier 1 (official):** 2-3 model families tested deeply, with explicit capability contracts.
2. **Tier 2 (compatible):** OpenAI-compatible endpoint mode, documented as best effort.
3. **Tier 3 (experimental):** community adapters behind feature flags.

This keeps quality high while preserving extension paths.

## Specialization Wedges to Test

Pick one primary wedge first, then expand:

1. **Best TUI runtime UX** (fastest, clearest multi-agent terminal)
2. **Best for Dart/CLI-heavy repos** (deep workflows for Dart + terminal apps)
3. **Best for Laravel/Filament** (prebuilt flows, domain-aware checks/agents)
4. **Best "minimal coding agent"** (predictable behavior, strict approvals, zero platform lock-in)

Recommendation: start with **(1) + (2)** because they align with current momentum and your strengths.

## 30-Day Execution Bets

1. Build a `ModelCapabilityRegistry` and enforce capability gating in the runtime.
2. Promote the "realistic scenario" TUI fixture into regression snapshots for UX stability.
3. Ship operator workflows as first-class: searchable agent/session table, failed-tool triage, rerun/fork actions.
4. Publish concise website positioning around the above, replacing generic "AI coding CLI" language.
5. Ship one vertical pack (Dart-first) to prove specialization thesis.

## Sources

- Codex repository: https://github.com/openai/codex
- Gemini CLI repository: https://github.com/google-gemini/gemini-cli
- Aider repository: https://github.com/Aider-AI/aider
- Cline repository: https://github.com/cline/cline
- Roo Code repository: https://github.com/RooCodeInc/Roo-Code
- Kilo Code repository: https://github.com/Kilo-Org/kilocode
- Codex repo API (stars): https://api.github.com/repos/openai/codex
- Gemini CLI repo API (stars): https://api.github.com/repos/google-gemini/gemini-cli
- Aider repo API (stars): https://api.github.com/repos/Aider-AI/aider
- Cline repo API (stars): https://api.github.com/repos/cline/cline
- Roo Code repo API (stars): https://api.github.com/repos/RooCodeInc/Roo-Code
- Kilo Code repo API (stars): https://api.github.com/repos/Kilo-Org/kilocode
- Codex docs/auth: https://developers.openai.com/codex/auth
- Claude Code (Bedrock/Vertex): https://docs.claude.com/en/docs/claude-code/bedrock-vertex-proxies
- Copilot model support: https://docs.github.com/en/copilot/concepts/ai-models/model-comparison
- Copilot coding agent: https://docs.github.com/en/copilot/concepts/about-copilot-coding-agent
- Amp Code homepage: https://ampcode.com
- Amp Manual: https://ampcode.com/manual
- Augment Code homepage: https://www.augmentcode.com
- Augment docs: https://docs.augmentcode.com
