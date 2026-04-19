# Deeper Skills Integration Plan (agentskills.io)

## Why This Plan

Glue has solid v1 support for agentskills.io-compatible skills (discovery, prompt listing, `skill` tool, and `/skills` browser), but there are activation and lifecycle gaps that limit reliability for long-lived sessions and multi-agent workflows.

This plan is based on:

- Current code in `cli/lib/src/skills/`, `cli/lib/src/app.dart`, `cli/lib/src/agent/`
- Existing skills docs and tests
- agentskills integration guidance: https://agentskills.io/integrate-skills
- agentskills specification: https://agentskills.io/specification

## Review Findings (Current State)

### HIGH: `/skills` "activation" does not reach model context

- File: `cli/lib/src/app.dart:1257`
- The `/skills` panel loads a skill body and prints it to UI blocks only.
- It does not append a message to `AgentCore` conversation.
- Result: users can believe a skill is activated when it is not.

### HIGH: skill registry refresh and skill tool registry diverge

- Files: `cli/lib/src/app.dart:815`, `cli/lib/src/app.dart:1175`, `cli/lib/src/app.dart:393`
- `/skills` re-discovers skills via `_discoverSkills()`, but `SkillTool` was created with the startup registry instance.
- Result: `/skills` can show newly added skills while `skill(name: ...)` cannot load them in the same session.

### HIGH: model switch drops skill path config

- Files: `cli/lib/src/config/glue_config.dart:89`, `cli/lib/src/app.dart:1293`
- `GlueConfig.copyWith()` does not preserve `skillPaths` (also omits `permissionMode` and `titleModel`).
- `/model` uses `copyWith()`, so skills from configured extra paths can disappear after model switch.

### MEDIUM: subagents cannot activate skills

- File: `cli/lib/src/agent/agent_manager.dart:13`
- `safeSubagentTools` excludes `skill`, so subagents cannot load skills even though skills are listed in prompt.
- Result: parent can use skills; subagents cannot, producing inconsistent behavior.

### MEDIUM: no tests for prompt skill block correctness

- Files: `cli/test/agent/prompts_test.dart`, `cli/lib/src/agent/prompts.dart`
- Tests do not validate `<available_skills>` output, escaping, or truncation behavior with many skills.

## Goals

1. Make skill activation reliable and explicit in all entry points.
2. Keep discovery, prompt metadata, and activation source in sync during a session.
3. Enable subagents to use skills safely.
4. Add guardrails and tests so skill behavior is stable across providers.

## Non-Goals (This Iteration)

- Full dependency graph between skills.
- Hot-reload file watchers.
- Rich skill package manager/distribution UX.

## Phase 1: Correctness and Activation Plumbing

### Task 1.1: Introduce a shared skill runtime in `App`

- Replace separate ad-hoc registry usage with one `SkillRuntime` owner in `App`.
- `SkillRuntime` responsibilities:
  - discover/reload
  - expose current `SkillRegistry`
  - expose `List<SkillMeta>` for prompt views
  - expose activation helper (returns canonical activation payload)

Files:

- Add: `cli/lib/src/skills/skill_runtime.dart`
- Modify: `cli/lib/src/app.dart`
- Modify: `cli/lib/src/skills/skill_tool.dart` (inject runtime instead of fixed registry)

Acceptance:

- `/skills` and `skill` tool use the same live registry instance.
- Reloading skills updates both surfaces.

### Task 1.2: Make `/skills` activation actually activate

- On Enter in `/skills`, route activation through the same path as `skill` tool:
  - emit a synthetic tool result block and
  - append matching `Message.toolResult(...)` to `AgentCore` conversation.
- Include `toolName: 'skill'` and stable `callId` prefix (e.g. `manual-skill-<ts>`).

Files:

- Modify: `cli/lib/src/app.dart`
- Add tests: `cli/test/app/skills_activation_test.dart` (or existing app tests location)

Acceptance:

- After activating a skill from `/skills`, the next assistant turn behaves the same as if `skill(name: "...")` had been called.

### Task 1.3: Fix `GlueConfig.copyWith()` field loss

- Preserve all non-overridden fields in `copyWith`, including:
  - `titleModel`
  - `skillPaths`
  - `permissionMode`

Files:

- Modify: `cli/lib/src/config/glue_config.dart`
- Modify: `cli/test/config/glue_config_test.dart`

Acceptance:

- Switching models does not change skill discovery paths.

## Phase 2: Prompt and Trigger Reliability

### Task 2.1: Strengthen skill trigger guidance in system prompt

- Add explicit trigger rules aligned with agentskills guidance:
  - if user names a skill, activate it
  - if task matches a skill description closely, activate before execution
  - when loading a skill, read `SKILL.md` first and only fetch referenced files as needed

Files:

- Modify: `cli/lib/src/agent/prompts.dart`
- Modify: `cli/test/agent/prompts_test.dart`

Acceptance:

- Prompt tests cover `<available_skills>` rendering, XML escaping, and trigger instruction presence.

### Task 2.2: Add optional prompt budget controls for skill listings

- Add `skills.max_prompt_entries` and `skills.max_prompt_bytes` config settings.
- When limits are exceeded, keep deterministic subset (stable sort + truncate) and add a short note.

Files:

- Modify: `cli/lib/src/config/glue_config.dart`
- Modify: `cli/lib/src/agent/prompts.dart`
- Modify tests in `cli/test/config/` and `cli/test/agent/`
- Update docs in `cli/docs/reference/config-yaml.md`, `devdocs/guide/advanced/skills.md`

Acceptance:

- Large skill catalogs do not bloat system prompt unexpectedly.

## Phase 3: Subagent and Policy Integration

### Task 3.1: Allow skill activation in subagents safely

- Add `skill` to `safeSubagentTools`.
- Add test coverage for subagent access to `skill` tool.

Files:

- Modify: `cli/lib/src/agent/agent_manager.dart`
- Add/modify: `cli/test/agent/agent_manager_test.dart` (or nearest coverage file)

Acceptance:

- Subagents can activate skills; behavior matches top-level agent.

### Task 3.2: Implement v1 `allowed-tools` enforcement (opt-in)

- Parse `allowed-tools` into matcher patterns.
- Add config gate: `skills.enforce_allowed_tools` (default `false`).
- When active skill has restrictions and enforcement enabled:
  - intersect with existing permission filter
  - show clear deny message for blocked tools

Files:

- Modify: `cli/lib/src/skills/skill_parser.dart`
- Add: `cli/lib/src/skills/tool_pattern_matcher.dart`
- Modify: `cli/lib/src/app.dart` and/or `cli/lib/src/agent/agent_core.dart`
- Add tests under `cli/test/skills/` and `cli/test/agent/`

Acceptance:

- Restricted skills can constrain tool use without bypassing existing permission modes.

## Phase 4: UX, Observability, and Documentation

### Task 4.1: Add `/skill <name>` fast-path command

- Keep `/skills` browser for discovery.
- Add direct activation command for keyboard-only flow.

Files:

- Modify: `cli/lib/src/app.dart`
- Modify: `cli/lib/src/commands/slash_commands.dart` (if needed)
- Update: `devdocs/guide/using-glue/interactive-mode.md`

Acceptance:

- `/skill code-review` activates same as tool call path and logs clear status.

### Task 4.2: Add skill lifecycle telemetry

- Emit spans/events for:
  - skill discovery count
  - activation success/failure
  - denied tools due to `allowed-tools` constraints

Files:

- Modify: `cli/lib/src/observability/` wrappers + `cli/lib/src/app.dart`
- Add tests for emitted attributes where feasible

Acceptance:

- Debug logs and traces can answer "which skills were active and why a tool was blocked".

### Task 4.3: Docs alignment pass

- Ensure docs match implementation:
  - config keys (`skills.paths`, prompt limits, enforcement flag)
  - activation behavior (`/skills`, `/skill`, `skill` tool)
  - subagent behavior

Files:

- `cli/docs/reference/config-yaml.md`
- `cli/docs/architecture/agent-loop-and-rendering.md`
- `cli/docs/architecture/glossary.md`
- `devdocs/guide/advanced/skills.md`

Acceptance:

- No stale or contradictory skill behavior in first-party docs.

## Suggested Execution Order

1. Phase 1 (correctness blockers)
2. Phase 2.1 (prompt trigger clarity)
3. Phase 3.1 (subagent parity)
4. Phase 2.2 (prompt budget hardening)
5. Phase 3.2 (optional policy enforcement)
6. Phase 4 (UX/telemetry/docs)

## Test Strategy Summary

- Unit tests:
  - parser and matching logic
  - prompt rendering and truncation
  - config parsing for new skill settings
- Integration tests:
  - `/skills` activation feeds agent conversation
  - refreshed discovery is visible to both `/skills` and `skill` tool
  - subagent activation parity
- Regression checks:
  - model switch preserves `skillPaths`
  - permission mode behavior remains unchanged when no skill restrictions are active
