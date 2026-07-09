# Shell PWD Tracking Implementation Spec

Status: proposed
Owner: implementation agent
Date: 2026-04-21
Last revised: 2026-04-30 (re-spec'd against the harness/strategies/core split)

## Goal

Implement **tracked shell pwd** in Glue without changing the session's
project identity.

Glue should distinguish between:

- a stable **workspace root** for the session
- a mutable **shell pwd** for bash-mode execution state

This spec intentionally does **not** add:

- `/cwd`
- workspace switching
- promoting shell pwd into workspace root
- multi-workspace session support

Those are deferred until an actual product need appears.

## How this plan relates to the harness layers

`workspaceRoot` and `shellPwd` are not just CLI app fields — they are session
state that every surface needs (CLI today, ACP server tomorrow). The cleanest
home for them is on the harness's `SessionMeta`/`SessionState`, not on
`App`.

Concretely:

- **Definition** (data): adds two fields to `SessionMeta` in
  `packages/glue_harness/lib/src/storage/session_meta.dart` (or
  `glue_core/session.dart` if a core-level type already exists).
- **Mutation**: only the harness's `ShellRuntime`-equivalent path may write
  `shellPwd`. The CLI never directly sets it; it dispatches a
  `SessionCommand` (e.g. `RunShellCommand`) and observes a
  `ShellPwdChangedEvent` in return. This matches the `SessionEvent` /
  `SessionCommand` contract from `2026-04-29-harness-layers.md`.
- **Read**: surfaces read `session.meta.shellPwd` via the existing
  `Glue.sessions` API.

The shell wrapper itself (sentinel emission + parsing) lives in the
**strategies** layer (`packages/glue_strategies/lib/src/shell/`), since it
is a transport-level concern that varies per executor (host vs Docker vs
future cloud runtime). The harness only sees a `RunningCommandHandle` or a
`CaptureResult` plus an "after-pwd" callback.

## Why This Change Is Needed

Today Glue overloads one `cwd` concept with too many meanings:

- project/workspace root
- prompt root (`CLAUDE.md`, `AGENTS.md`)
- skill-discovery root
- permission boundary root
- shell execution directory
- session metadata directory label

That is wrong because those things should not all move together.

The concrete user problem is narrower:

- in bash mode, the user may run `cd ...`
- subsequent shell commands should run from the new directory
- Glue should remember and display that shell location

That does **not** require changing the workspace root.

## Product Decision

### In scope

- stable workspace root
- mutable shell pwd
- shell commands start from shell pwd
- shell pwd is updated after each bash command
- session metadata stores both workspace root and shell pwd
- UI (CLI today, ACP later) can show shell pwd when relevant

### Out of scope

- `/cwd`
- `/workspace switch`
- prompt/skills/permissions following shell pwd
- non-shell tools following shell pwd
- attached-path browsing UI
- automatic workspace promotion/switching

## Architecture Decision

### Stable session/project identity

Introduce a stable concept called:

- `workspaceRoot`

This drives:

- prompt construction (`packages/glue_harness/lib/src/agent/prompts.dart`)
- project instruction loading
- project-local skill discovery (`SkillRegistry`)
- permission boundaries (`PermissionGate`)
- session grouping / resume UI (CLI surface)
- session metadata identity
- file references and autocomplete (CLI surface)

This must **not** change when shell pwd changes.

### Mutable shell execution state

Introduce a mutable concept called:

- `shellPwd`

This drives only shell-related behavior:

- starting directory for bash commands
- bash mode status display
- shell-related transcript/session metadata

This may change after shell commands that modify working directory.

### Naming

Use these names in new code and schema:

- `workspaceRoot`
- `shellPwd`
- persisted JSON keys:
  - `workspace_root`
  - `shell_pwd`

Legacy `cwd` remains read-compatible but should be phased out from the hot
paths touched by this implementation.

## Behavior Specification

### Startup

At startup:

- `workspaceRoot = Environment.cwd`
- `shellPwd = Environment.cwd`

So both begin equal, then diverge only if bash mode changes directory.

### Bash command execution

When the user runs a bash command:

1. command starts in `shellPwd`
2. command is executed via the strategies-layer executor
3. executor parses the wrapper sentinel and reports `(exitCode, finalPwd)`
4. harness emits a `ShellPwdChangedEvent` if `finalPwd != currentShellPwd`
5. `SessionMeta.shellPwd` is updated to that final value
6. `workspaceRoot` is unchanged

### Non-shell behavior

The following continue to use `workspaceRoot` only:

- prompts
- skill discovery
- permission gating
- `@file` expansion (CLI)
- at-file autocomplete (CLI)
- session identity and grouping
- ACP `session/list_files` and equivalents

### Cross-project shell movement

For phase 1, shell pwd is allowed to leave `workspaceRoot`, but the effect is
local to shell state only.

This split-brain state is allowed:

- `workspaceRoot = ~/code/crescat`
- `shellPwd = ~/code/glue`

Acceptable because:

- the shell is the only subsystem following `shellPwd`
- the session still truthfully belongs to `crescat`
- we are **not** pretending the whole workspace changed

## Implementation Plan

### Phase 1 — explicit state split

#### 1. Promote workspace/shell state into the harness session

**Files (harness):**

- `packages/glue_harness/lib/src/storage/session_meta.dart` — add `workspaceRoot` + `shellPwd` fields, persisted as `workspace_root` / `shell_pwd`.
- `packages/glue_harness/lib/src/session/session_manager.dart` — initialize both from `Environment.cwd` on session create.
- `packages/glue_core/lib/src/session_event.dart` — add `ShellPwdChangedEvent`.

**Files (CLI surface):**

- `cli/lib/src/app.dart`
- `cli/lib/src/app/session_runtime.dart`
- `cli/lib/src/app/command_helpers.dart`

CLI no longer holds its own `_cwd`. It reads `session.meta.workspaceRoot` and
`session.meta.shellPwd`, and observes `ShellPwdChangedEvent` to refresh its
status bar. No CLI code mutates pwd directly.

#### 2. Prompt and skill wiring stay on workspace root

**Files (harness):**

- `packages/glue_harness/lib/src/agent/prompts.dart`
- `packages/glue_harness/lib/src/skills/skill_runtime.dart`
- `packages/glue_harness/lib/src/skills/skill_registry.dart`
- `packages/glue_harness/lib/src/core/service_locator.dart`

Change:

- keep prompt construction rooted at `workspaceRoot`
- keep project-local skill discovery rooted at `workspaceRoot`

Do not make these follow shell pwd.

#### 3. File references and autocomplete stay on workspace root

**Files (CLI surface):**

- `cli/lib/src/ui/at_file_hint.dart`
- `cli/lib/src/input/file_expander.dart`
- app wiring sites that instantiate them

Change:

- keep `@file` expansion and at-file suggestions rooted at `workspaceRoot`
- do not let shell movement retarget these
- pass `session.meta.workspaceRoot` explicitly; do not fall back to `Directory.current`

#### 4. Permission gate stays on workspace root

**Files (harness):**

- `packages/glue_harness/lib/src/orchestrator/permission_gate.dart`

Change:

- pass `workspaceRoot` where permission logic currently expects `cwd`
- typed `PermissionRequestedEvent`s already carry the gate-relevant context; keep `workspaceRoot` as the gate's authoritative root regardless of shell movement

#### 5. Shell runtime follows shell pwd

**Files (strategies):**

- `packages/glue_strategies/lib/src/shell/command_executor.dart`
- `packages/glue_strategies/lib/src/shell/host_executor.dart`
- `packages/glue_strategies/lib/src/shell/executor_factory.dart`
- `packages/glue_strategies/lib/src/shell/docker_executor.dart`

**Files (harness):**

- `packages/glue_harness/lib/src/agent/shell_job_manager.dart`

**Files (CLI surface):**

- `cli/lib/src/app/shell_runtime.dart` — orchestrates the user-visible bash mode UX, but delegates execution to the harness/strategies stack.

This is the primary implementation area. The wrapper contract below is owned
by the strategies layer; the harness owns "after-pwd reported by executor →
update SessionMeta + emit `ShellPwdChangedEvent`."

## Shell wrapper contract

This section is normative.

### Chosen approach

Use a **command wrapper approach**, not a full persistent shell process rewrite.

### Required properties

The wrapper must guarantee all of the following:

1. user command starts from current `shellPwd`
2. final pwd is captured after command execution
3. original command exit code is preserved exactly
4. final pwd capture works for success and failure cases
5. sentinel text is stripped from user-visible output
6. shell pwd updates only when capture is trustworthy
7. workspace root is never mutated by this mechanism

### Required execution semantics

Conceptually, execution must behave as if Glue runs:

1. `cd` into current `shellPwd`
2. run the user command in that shell context
3. remember the user command's exit code
4. print a unique sentinel containing:
   - sentinel token
   - captured pwd
   - exit code
5. parse and strip sentinel from final output
6. return the original exit code, cleaned output, and the captured pwd to the harness

The strategies-layer executor is the only code that touches sentinel bytes.
The harness consumes a structured `CaptureResult` extended with an optional
`finalPwd: String?`.

### Wrapper payload requirements

Sentinel must include at minimum:

- a unique marker unlikely to appear naturally in command output
- the final pwd
- the user command exit code

Recommended shape:

```text
__GLUE_SENTINEL_<nonce>__:<exitCode>:<pwd>
```

- `<nonce>` is generated per command invocation
- `<exitCode>` is the wrapped command's actual exit code
- `<pwd>` is the shell's final working directory after the command finishes

Do not use a fixed sentinel string globally.

### Preferred parsing channel

Prefer emitting the sentinel on **stdout** at the end of the command, then
parsing from combined output.

If stdout-only proves too brittle, stderr is acceptable **only if** output
handling remains deterministic and the sentinel is still removable without
corrupting user-visible stderr.

### Output-cleaning contract

The user must never see:

- the sentinel line
- wrapper bookkeeping
- synthetic `cd` boilerplate
- explicit exit-code plumbing text

### Exit-code preservation contract

If the user command exits with code `N`, Glue must behave exactly as if the
raw command exited with code `N`. Glue must not return success merely
because sentinel emission succeeded; must not lose original exit code on
failure; must still capture pwd on failure where possible.

### Minimal shell-shape example

```bash
cd "$SHELL_PWD"
{
  <user command>
}
status=$?
printf '\n__GLUE_SENTINEL_<nonce>__:%s:%s\n' "$status" "$PWD"
exit "$status"
```

Behavioral contract is what matters; an implementing agent may use a more
robust form.

## Shell wrapper edge cases

### 1. Command fails before changing directory

Example: `cd does-not-exist`

Expected:

- exit code reflects failure
- final pwd remains the previous `shellPwd` if capture succeeds
- `shellPwd` must not become null/empty

### 2. Command changes directory then fails

Example: `cd ../glue && false`

Expected:

- exit code reflects `false`
- `shellPwd` updates to `../glue` if final pwd capture succeeds

### 3. Command prints text similar to sentinel

Expected:

- parser only recognizes the exact nonce-bearing sentinel for this invocation
- user output remains intact even if it contains other similar strings

### 4. Command has no stdout/stderr

Expected:

- still captures sentinel and updates shell pwd
- rendered output may be empty; exit code preserved

### 5. Trailing newlines / no trailing newline

Expected:

- sentinel parsing does not depend on pretty formatting quirks
- cleaned output preserves user-visible output semantics

### 6. Long-running but completes normally

Expected: sentinel capture works; no spinner/render regressions.

### 7. Command is cancelled

Expected:

- if cancellation occurs before sentinel emission, `shellPwd` must remain the previous value
- do not infer shell pwd from partial output

### 8. Command times out or process crashes

Expected:

- preserve current Glue cancellation/error behavior
- do not update `shellPwd` unless a valid sentinel was parsed

### 9. Shell pwd contains spaces or special characters

Expected: quoting and parsing support paths with spaces; sentinel parsing does not split incorrectly on spaces.

### 10. Shell pwd is deleted or becomes inaccessible between commands

Expected:

- next command fails clearly or falls back to a defined behavior
- do not silently reset workspace root
- phase 1 recommendation: if `shellPwd` no longer exists, fall back to `workspaceRoot` for shell execution and emit a `ShellPwdResetEvent` (`SessionEvent` variant) so all surfaces can show a system message

## Docker/sandbox behavior contract

Current Docker execution mounts only the startup cwd as `/workspace`.

If shell pwd moves outside workspace root, Docker cannot automatically follow
that path unless additional host paths are mounted.

### Phase-1 required behavior

Implementation must choose and document one of these explicitly in
`packages/glue_strategies/lib/src/shell/docker_executor.dart`:

#### Option A — constrain shell pwd in Docker mode

- allow shell pwd updates only within workspace root
- if command attempts to end outside workspace root, either:
  - keep `shellPwd` unchanged, or
  - reset it to `workspaceRoot`
- emit a `ShellPwdRejectedEvent` (typed `SessionEvent`) if reset/restricted

#### Option B — deny shell execution once shell pwd leaves mounted workspace

- shell pwd may still be tracked from prior host-mode or logical state
- but Docker shell execution outside mounted workspace is rejected clearly

### Recommendation

Use **Option A** for phase 1.

Simpler and avoids pretending Docker supports something it does not.

### Required Docker tests

Whichever option is chosen, tests in
`packages/glue_strategies/test/shell/` must assert the exact behavior. No
silent fallbacks.

### 6. Shell pwd persistence in session metadata

**Files:**

- `packages/glue_harness/lib/src/storage/session_store.dart`
- `packages/glue_harness/lib/src/session/session_manager.dart`
- `packages/glue_harness/lib/src/doctor/` (or wherever doctor lives — currently `cli/lib/src/doctor/doctor.dart`)

Schema evolution:

Add fields to `SessionMeta`:

- `workspace_root`
- `shell_pwd`

Backward compatibility:

- when reading legacy sessions, treat `cwd` as `workspace_root`
- if `shell_pwd` is absent, default it to `workspace_root`

For session creation:

- set `workspace_root = Environment.cwd`
- set `shell_pwd = Environment.cwd`

For shell-pwd changes:

- update current session metadata when shell pwd changes
- persist without rotating the session identity

### 7. UI updates

**Files (CLI surface):**

- `cli/lib/src/app/command_helpers.dart`
- `cli/lib/src/app/render_pipeline.dart`
- `cli/lib/src/ui/panel_controller.dart`
- any status/header rendering paths

Behavior:

- normal session/project info continues showing workspace root as the session directory/project identity
- bash mode/status can additionally show current shell pwd when it differs from workspace root
- resume/session list continues grouping and searching primarily by workspace root, not shell pwd

Phase 1 UI should remain conservative. No large UX redesign is needed.

For ACP server, `glue_server` already maps `SessionEvent`s to ACP
notifications; `ShellPwdChangedEvent` simply needs an entry in the mapper
so headless ACP clients can update their displays.

## Codebase Refactor Map

### A. App/runtime state

#### `cli/lib/src/app.dart`

Current: `_cwd` is overloaded (and locally owned).

Required:

- remove the locally-owned `_cwd` entirely
- read `session.meta.workspaceRoot` / `session.meta.shellPwd`

#### `cli/lib/src/app/session_runtime.dart`

Required: handles attach + observes `ShellPwdChangedEvent` to refresh status bar.

#### `cli/lib/src/app/command_helpers.dart`

Required:

- continue using workspace root for project identity in UI
- optionally expose shell pwd in session info when useful

### B. Prompt / project instructions

#### `packages/glue_harness/lib/src/agent/prompts.dart`

Required:

- ensure this path uses workspace root from `SessionMeta`
- renaming parameter is optional in phase 1

### C. Skills

#### `packages/glue_harness/lib/src/skills/skill_runtime.dart`
#### `packages/glue_harness/lib/src/skills/skill_registry.dart`

Required: keep rooted to workspace root.

### D. File references / autocomplete

#### `cli/lib/src/ui/at_file_hint.dart`
#### `cli/lib/src/input/file_expander.dart`

Required: keep rooted to workspace root; pass it explicitly rather than relying on `Directory.current`.

### E. Permissions

#### `packages/glue_harness/lib/src/orchestrator/permission_gate.dart`

Required: use workspace root semantics; rename internally where touched if it clarifies the model.

### F. Shell execution

#### `cli/lib/src/app/shell_runtime.dart` (surface UX)
#### `packages/glue_harness/lib/src/agent/shell_job_manager.dart` (harness lifecycle)
#### `packages/glue_strategies/lib/src/shell/command_executor.dart`
#### `packages/glue_strategies/lib/src/shell/host_executor.dart`
#### `packages/glue_strategies/lib/src/shell/docker_executor.dart`
#### `packages/glue_strategies/lib/src/shell/executor_factory.dart`

Required:

- wrap commands to run from `shellPwd` in the strategies layer
- parse final pwd and exit code at the executor boundary
- bubble `(exitCode, cleanedOutput, finalPwd)` up through `CaptureResult`
- harness emits `ShellPwdChangedEvent` and persists metadata
- strip wrapper artifacts from rendered output before reaching surfaces

Docker path handling needs extra care because current executor assumes a fixed mounted cwd at `/workspace`.

### G. Session metadata / doctor / UI

#### `packages/glue_harness/lib/src/storage/session_store.dart`
#### `packages/glue_harness/lib/src/session/session_manager.dart`
#### `cli/lib/src/ui/panel_controller.dart`
#### `cli/lib/src/doctor/doctor.dart`

Required:

- schema update on `SessionMeta`
- read compatibility for legacy `cwd`
- doctor validation update
- resume/list views continue using workspace root

## Risks And Gotchas

### 1. Docker executor mismatch

If shell pwd moves outside workspace root, Docker execution may not be able to follow that path without additional mounts or explicit rejection. Phase 1 must define behavior clearly (Option A above).

### 2. Sentinel parsing

Final-pwd capture must be robust. Failure modes: sentinel appears in normal output; stdout/stderr ordering breaks parsing; command failure masks pwd capture. Use a highly unique sentinel and strip it before rendering.

### 3. `Directory.current` fallback

Some helpers fall back to `Directory.current.path`. Where touched, prefer explicit `workspaceRoot` / `shellPwd` injection from `SessionMeta`.

### 4. Session metadata churn

If shell pwd is persisted after every shell command, metadata writes become more frequent. Acceptable, but keep writes targeted and atomic. Consider debouncing within `SessionStore`.

## Test Coverage Specification

### A. App state separation (CLI + harness)

1. startup initializes `workspaceRoot == shellPwd == Environment.cwd` on `SessionMeta`
2. shell pwd changes do not change workspace root
3. session identity remains tied to workspace root after shell movement

### B. Shell runtime behavior — core contract (`packages/glue_strategies/test/shell/`)

1. simple command runs from initial shell pwd
2. `cd subdir && pwd` updates `shellPwd` to that subdir
3. `cd .. && pwd` updates `shellPwd` correctly
4. repeated commands start from last tracked shell pwd
5. shell pwd updates on success
6. shell pwd updates on "change dir then fail" cases
7. shell pwd does not update when no valid sentinel is parsed
8. wrapper sentinel is not in rendered bash output
9. wrapper plumbing is not in rendered bash output
10. original command exit code is preserved exactly

### C. Shell runtime behavior — edge cases

1. command with no stdout and exit 0
2. command with no stdout and non-zero exit
3. command with large stdout still yields correct sentinel parsing
4. command output containing sentinel-like text does not confuse parser
5. command output ending without newline parses correctly
6. command output with many trailing newlines parses correctly
7. shell pwd containing spaces is handled correctly
8. shell pwd containing shell-sensitive characters is quoted correctly
9. cancelled command leaves `shellPwd` unchanged
10. timed-out/aborted command leaves `shellPwd` unchanged unless a valid sentinel was captured before termination
11. deleted/inaccessible `shellPwd` on next run falls back per spec

### D. Cross-project shell movement (`packages/glue_harness/test/`)

1. shell pwd can move outside workspace root in host mode
2. workspace root does not change when that happens
3. non-shell systems remain on workspace root after shell movement

After shell moves elsewhere:

- prompt build still uses workspace root
- skill runtime still uses workspace root
- file expansion still uses workspace root
- permission gate still uses workspace root

### E. Session metadata (`packages/glue_harness/test/storage/` + `session/`)

1. new sessions write `workspace_root` and `shell_pwd`
2. legacy sessions with only `cwd` still load correctly
3. legacy `cwd` maps to `workspace_root`
4. missing `shell_pwd` defaults to `workspace_root`
5. updating shell pwd persists correctly without changing workspace root
6. resume preserves workspace root and shell pwd
7. malformed `shell_pwd` values are handled safely
8. metadata updates do not accidentally rotate or fork the session

### F. Surface behavior

CLI (`cli/test/app/`):

1. session info shows workspace/project directory as the primary directory
2. bash-specific/status output shows shell pwd when it differs
3. session list/search uses workspace root, not shell pwd, for primary grouping
4. legacy sessions still render correctly in resume/session list UI

ACP server (`packages/glue_server/test/acp/`):

1. `ShellPwdChangedEvent` is mapped to a documented ACP notification
2. ACP `session/info` exposes workspace root and shell pwd separately

### G. Docker-mode behavior

1. shell pwd updates within workspace root work under Docker mode
2. shell pwd attempts outside workspace root are rejected/reset per spec
3. user-visible messaging for this restriction is clear and deterministic
4. no silent execution in the wrong directory occurs

### H. Doctor / schema validation

1. doctor accepts new metadata schema
2. doctor still tolerates legacy sessions with `cwd`
3. doctor reports malformed new metadata fields cleanly
4. doctor does not require `shell_pwd` for legacy sessions

## Suggested Test File Targets

- `packages/glue_harness/test/storage/session_store_test.dart`
- `packages/glue_harness/test/session/session_manager_test.dart`
- `packages/glue_harness/test/orchestrator/permission_gate_test.dart`
- `packages/glue_harness/test/agent/prompts_test.dart`
- `packages/glue_harness/test/skills/`
- `packages/glue_strategies/test/shell/` (core wrapper + Docker)
- `packages/glue_strategies/test/shell/host_executor_pwd_tracking_test.dart` (new)
- `packages/glue_strategies/test/shell/wrapper_parsing_test.dart` (new)
- `cli/test/input/file_expander_test.dart`
- `cli/test/ui/at_file_hint_test.dart`
- `cli/test/app/`
- `cli/test/doctor/doctor_test.dart`
- `packages/glue_server/test/acp/` for ACP mapping if needed

## Acceptance Criteria

This work is complete when:

1. Glue has distinct runtime concepts for workspace root and shell pwd, owned by `SessionMeta` in the harness
2. shell commands follow shell pwd across invocations
3. shell pwd updates after `cd`-style commands
4. original shell command exit codes are preserved exactly
5. sentinel/wrapper artifacts are never user-visible
6. session metadata stores both workspace root and shell pwd
7. prompts/skills/permissions/file refs remain rooted to workspace root
8. Docker-mode behavior is explicit and tested
9. no `/cwd` command is introduced
10. tests cover host-mode shell-pwd updates, metadata compatibility, workspace-root isolation, and ACP event mapping
11. CLI does not own pwd state directly; surface reads from `SessionMeta`

## Non-Goals Reminder

Do not sneak these into the same PR:

- workspace switching
- shell-pwd promotion
- multi-root editing semantics
- file tools following shell pwd
- big UI redesign

That is scope creep, and it will make the implementation sloppier.

## Hand-off Guidance

If another agent implements this later, approach in this order:

1. add `workspaceRoot`/`shellPwd` to `SessionMeta` + read compatibility
2. add `ShellPwdChangedEvent` to `glue_core`
3. plumb workspace root through the harness consumers (prompts, skills, permissions)
4. implement shell wrapper + final pwd capture + exit-code preservation in `glue_strategies`
5. wire harness-side metadata persistence + event emission
6. update CLI surface to read from `SessionMeta` and render the new event
7. add ACP mapping in `glue_server`
8. add/adjust tests
9. only then do optional renaming in touched paths for clarity

Do not start with global renames. Start with semantic separation.
