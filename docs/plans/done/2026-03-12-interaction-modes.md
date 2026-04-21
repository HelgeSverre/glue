# Interaction Modes

Date: 2026-03-12

## What This Is

Replace the current `PermissionMode` enum (confirm/acceptEdits/YOLO/readOnly) with
an interaction mode system copied from Roo Code / Kilo Code. Modes control which
tools the LLM can use, not just how tool calls are approved.

## Why

Every major AI coding tool has converged on this pattern. The current permission
cycling conflates two independent axes: tool access (what the LLM can do) and
approval flow (whether the user confirms). Splitting these gives us plan/architect
mode for free.

## Competitive Basis

| Tool        | Modes                                             | Mechanism                                      |
| ----------- | ------------------------------------------------- | ---------------------------------------------- |
| Roo Code    | Code, Architect, Ask, Debug, Orchestrator         | Tool-group permissions per mode                |
| Kilo Code   | Code, Ask, Architect, Debug, Orchestrator, Review | Same, adds browser group                       |
| Aider       | code, ask, architect, help                        | Coder subclass per mode, hard tool restriction |
| Claude Code | default, auto-accept, plan                        | Prompt-level restriction (weak)                |
| Cline       | Plan/Act toggle                                   | Binary, hard restriction                       |
| Copilot     | Agent, Plan, Ask                                  | Per-agent tool lists                           |

Glue should copy the Roo/Kilo tool-group model with hard filtering via the
existing `toolFilter` on `AgentCore`.

## Design

### Modes

| Mode        | Tools Available                     | Purpose                         |
| ----------- | ----------------------------------- | ------------------------------- |
| `code`      | All tools                           | Default. Full access.           |
| `architect` | Read tools + write `.md` files only | Plan, research, draft documents |
| `ask`       | Read tools only                     | Q&A, no changes at all          |

That's it. Three modes. No orchestrator yet (defer until subtask system exists).

### Tool Groups

Map every tool to a group:

| Group     | Tools                                                           | Description           |
| --------- | --------------------------------------------------------------- | --------------------- |
| `read`    | read_file, glob, grep, list_files, web_search, web_fetch, skill | Safe, read-only       |
| `edit`    | write_file, edit_file, notebook_edit                            | File mutations        |
| `command` | bash                                                            | Shell execution       |
| `mcp`     | Any MCP tool                                                    | External integrations |

Mode → group mapping:

| Mode        | read | edit       | command | mcp |
| ----------- | ---- | ---------- | ------- | --- |
| `code`      | yes  | yes        | yes     | yes |
| `architect` | yes  | `.md` only | no      | yes |
| `ask`       | yes  | no         | no      | yes |

### Approval (Orthogonal)

Keep the existing approval behavior but decouple it from modes:

| Approval  | Behavior                   |
| --------- | -------------------------- |
| `confirm` | Ask before untrusted tools |
| `auto`    | Auto-approve everything    |

This replaces the 4-value `PermissionMode` with a 2-value `ApprovalMode` that is
independent of the interaction mode. The `readOnly` and `acceptEdits` permission
modes become unnecessary — `ask` mode replaces `readOnly`, and `auto` approval
replaces `acceptEdits`/`YOLO`.

### Mode Switching

**Shift+Tab** cycles: `code` → `architect` → `ask` → `code`

**Slash commands:**

- `/code` — switch to code mode
- `/architect` — switch to architect mode
- `/ask` — switch to ask mode
- `/approve` — toggle approval mode (confirm ↔ auto)

**Agent-initiated:** Add a `switch_mode` tool (always available) so the LLM can
suggest mode transitions. Requires user confirmation.

### Status Bar

Show mode in the status bar where permission mode currently displays:

- Code mode: `[code]`
- Architect mode: `[architect]`
- Ask mode: `[ask]`

Approval indicator appended when auto: `[code·auto]`

### Prompt Changes

Each mode gets a short system prompt suffix:

**architect:**

> You are in architect mode. You can read the entire codebase and write markdown
> files (.md) only. You cannot edit code files or run commands. Focus on research,
> analysis, and drafting plans as markdown documents.

**ask:**

> You are in ask mode. You can read the codebase but cannot make any changes.
> Answer questions, explain code, and provide guidance.

### File Restriction in Architect Mode

The `.md`-only write restriction in architect mode is the key insight from
Roo/Kilo. It means the architect can:

- Save plans to `docs/plans/` or `~/.glue/plans/`
- Write design docs, specs, notes
- Update existing markdown documentation

But cannot:

- Edit source code
- Run shell commands
- Create non-markdown files

This makes plans a natural byproduct of architect mode, not a special subsystem.
The existing `PlanStore` already indexes markdown files from these locations.

## What This Replaces

The entire previous plan mode design is replaced:

- No `PlanDraftSession` — architect mode just writes `.md` files normally
- No `PlannerFlow` — the LLM uses its normal tools, just restricted
- No `ClarificationPanel` — free-text conversation like Aider's ask/code bounce
- No `request_clarification` tool — not needed, conversation is the interface
- No `update_plan_draft` tool — the LLM uses `write_file` restricted to `.md`
- No special plan save flow — it's just writing a file
- No `/run` command — user switches to code mode and references the plan
- No `EnterPlanMode`/`ExitPlanMode` tools — `switch_mode` is generic

## Integration with Superpowers Skills

The superpowers skill chain (brainstorming → writing-plans → executing-plans)
works naturally with modes:

1. User enters architect mode (Shift+Tab or `/architect`)
2. Activates `brainstorming` skill — explores, asks questions, proposes design
3. Skill writes spec to `docs/superpowers/specs/` (allowed in architect mode)
4. Activates `writing-plans` skill — writes plan to `docs/superpowers/plans/`
5. User switches to code mode (Shift+Tab or `/code`)
6. Activates `executing-plans` skill — implements the plan with full tool access

No special plumbing needed. Modes just gate tools; skills provide the workflow.

## Implementation

### Phase 1: InteractionMode enum + tool group filtering

Files to modify:

- `cli/lib/src/config/permission_mode.dart` — replace `PermissionMode` with `InteractionMode` + `ApprovalMode`
- `cli/lib/src/app/agent_orchestration.dart` — replace `_syncToolFilterImpl` with group-based filtering
- `cli/lib/src/agent/tools.dart` — add `ToolGroup` enum, tag each tool with its group

New:

- `cli/lib/src/config/interaction_mode.dart` — `InteractionMode` enum with tool group access matrix

Changes:

1. Define `InteractionMode { code, architect, ask }` with group access matrix
2. Define `ApprovalMode { confirm, auto }`
3. Tag each tool with a `ToolGroup` (read/edit/command/mcp)
4. Replace `_syncToolFilterImpl` to filter by mode's allowed groups
5. For architect mode edit group: add file extension check (`.md` only)

Acceptance: Tools are hard-filtered. In architect mode, only read tools + `.md`
write tools appear in the LLM's tool list. In ask mode, only read tools appear.

### Phase 2: Mode switching UX

Files to modify:

- `cli/lib/src/app/terminal_event_router.dart` — Shift+Tab cycles interaction modes
- `cli/lib/src/commands/builtin_commands.dart` — add `/code`, `/architect`, `/ask`, `/approve`
- `cli/lib/src/app/render_pipeline.dart` — show mode in status bar
- `cli/lib/src/app.dart` — replace `_permissionMode` with `_interactionMode` + `_approvalMode`

Changes:

1. Shift+Tab cycles `InteractionMode` instead of `PermissionMode`
2. Add slash commands for explicit mode switching
3. Status bar shows `[architect]` etc. instead of `[confirm]`
4. Prompt prefix changes per mode (optional: `architect>`, `ask>`)

Acceptance: User can cycle modes with Shift+Tab. Status bar reflects current mode.
Slash commands work.

### Phase 3: System prompt per mode

Files to modify:

- `cli/lib/src/agent/prompts.dart` — add mode-specific prompt suffix
- `cli/lib/src/app/agent_orchestration.dart` — inject mode context on submit

Changes:

1. Add short mode description to system prompt when mode != code
2. Architect prompt emphasizes markdown output for plans/specs

Acceptance: LLM behavior adapts to mode. In architect mode it naturally produces
markdown plans without being told to use special tools.

### Phase 4: switch_mode tool (optional)

New:

- `cli/lib/src/agent/builtin_tools/switch_mode_tool.dart`

Changes:

1. Tool with `name` parameter (code/architect/ask)
2. Always available in all modes
3. Requires user confirmation before switching
4. Returns confirmation message

Acceptance: LLM can suggest mode transitions. User approves.

## What NOT to Build

- Plan status fields, plan databases, plan DAGs
- Orchestrator mode (defer until subtask system exists)
- Custom user-defined modes (defer, copy Roo's YAML config later if needed)
- Debug mode (just use code mode)
- Review mode (just use ask mode)
- Per-mode model selection (defer)
- Auto-approve per tool category (defer)

## Risks

**Shift+Tab behavior change:** Users currently use Shift+Tab for permission
cycling. The new cycling replaces it entirely — `readOnly` becomes `ask` mode,
`YOLO` becomes `auto` approval (toggled separately via `/approve`).

**Architect `.md` restriction:** The file extension check must be enforced in the
tool filter, not the prompt. The `write_file` and `edit_file` tools need a
wrapper or the filter needs to inspect the file path argument.

## Success Criteria

1. `dart analyze` and `dart test` pass
2. Shift+Tab cycles code → architect → ask → code
3. In architect mode, LLM cannot see edit/command tools except `.md` writes
4. In ask mode, LLM cannot see any mutating tools
5. `/architect`, `/code`, `/ask` commands work
6. Status bar shows current mode
7. Plans written in architect mode appear in `/plans`
