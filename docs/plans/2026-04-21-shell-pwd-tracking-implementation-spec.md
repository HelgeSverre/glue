# Shell PWD Tracking Implementation Spec

Status: proposed
Owner: implementation agent
Date: 2026-04-21

## Goal

Implement **tracked shell pwd** in Glue without changing the session's project
identity.

Glue should distinguish between:

- a stable **workspace root** for the session
- a mutable **shell pwd** for bash-mode execution state

This spec intentionally does **not** add:

- `/cwd`
- workspace switching
- promoting shell pwd into workspace root
- multi-workspace session support

Those are deferred until an actual product need appears.

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
- UI can show shell pwd when relevant

### Out of scope

- `/cwd`
- `/workspace switch`
- prompt/skills/permissions following shell pwd
- non-shell tools following shell pwd
- attached-path browsing UI
- automatic workspace promotion/switching

## Architecture Decision

## Stable session/project identity

Introduce a stable concept called:

- `workspaceRoot`

This is the root of the coding session and must drive:

- prompt construction
- project instruction loading
- project-local skill discovery
- permission boundaries
- session grouping / resume UI
- session metadata identity
- file references and autocomplete

This must **not** change when shell pwd changes.

## Mutable shell execution state

Introduce a mutable concept called:

- `shellPwd`

This drives only shell-related behavior:

- starting directory for bash commands
- bash mode status display
- shell-related transcript/session metadata

This may change after shell commands that modify working directory.

## Naming

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
2. command is executed
3. Glue captures the final shell pwd after command completion
4. `shellPwd` is updated to that final value
5. `workspaceRoot` is unchanged

### Non-shell behavior

The following continue to use `workspaceRoot` only:

- prompts
- skill discovery
- permission gating
- `@file` expansion
- at-file autocomplete
- session identity and grouping

This is intentional. Non-shell tools must not silently retarget to another
project just because the shell moved.

### Cross-project shell movement

For phase 1, shell pwd is allowed to leave `workspaceRoot`, but the effect is
local to shell state only.

That means this split-brain state is allowed:

- `workspaceRoot = ~/code/crescat`
- `shellPwd = ~/code/glue`

This is acceptable because:

- the shell is the only subsystem following `shellPwd`
- the session still truthfully belongs to `crescat`
- we are **not** pretending the whole workspace changed

## Implementation Plan

## Phase 1 — explicit state split

### 1. App state split

Files:

- `cli/lib/src/app.dart`
- `cli/lib/src/app/session_runtime.dart`
- `cli/lib/src/app/command_helpers.dart`

Change:

Replace the overloaded `_cwd` with:

- `_workspaceRoot`
- `_shellPwd`

Initialization:

- both start from `Environment.cwd`

Usage rules:

- anything project/session/prompt/permission-related should use
  `_workspaceRoot`
- anything shell-execution-related should use `_shellPwd`

### 2. Prompt and skill wiring stay on workspace root

Files:

- `cli/lib/src/agent/prompts.dart`
- `cli/lib/src/skills/skill_runtime.dart`
- `cli/lib/src/skills/skill_registry.dart`
- `cli/lib/src/core/service_locator.dart`

Change:

- keep prompt construction rooted at `workspaceRoot`
- keep project-local skill discovery rooted at `workspaceRoot`

Do not make these follow shell pwd.

### 3. File references and autocomplete stay on workspace root

Files:

- `cli/lib/src/ui/at_file_hint.dart`
- `cli/lib/src/input/file_expander.dart`
- app wiring sites that instantiate them

Change:

- keep `@file` expansion and at-file suggestions rooted at `workspaceRoot`
- do not let shell movement retarget these

This avoids making prior conversation references ambiguous.

### 4. Permission gate stays on workspace root

Files:

- `cli/lib/src/orchestrator/permission_gate.dart`
- `cli/lib/src/app.dart`

Change:

- pass `workspaceRoot` where permission logic currently expects `cwd`
- rename internally where useful, but behavior should remain workspace-rooted

### 5. Shell runtime follows shell pwd

Files:

- `cli/lib/src/app/shell_runtime.dart`
- `cli/lib/src/shell/command_executor.dart`
- `cli/lib/src/shell/host_executor.dart`
- possibly `cli/lib/src/shell/executor_factory.dart`
- possibly `cli/lib/src/shell/docker_executor.dart`

This is the primary implementation area.

## Shell wrapper contract

This section is normative. The implementing agent should follow this contract,
not invent a looser interpretation.

### Chosen approach

Use a **command wrapper approach**, not a full persistent shell process rewrite.

That is the smallest viable change given current Glue architecture.

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
6. return the original exit code and cleaned output

The important thing is the semantics, not the literal shell syntax.

### Wrapper payload requirements

The sentinel must include at minimum:

- a unique marker unlikely to appear naturally in command output
- the final pwd
- the user command exit code

Recommended shape:

```text
__GLUE_SENTINEL_<nonce>__:<exitCode>:<pwd>
```

Where:

- `<nonce>` is generated per command invocation
- `<exitCode>` is the wrapped command's actual exit code
- `<pwd>` is the shell's final working directory after the command finishes

Do not use a fixed sentinel string globally. That is too collision-prone.

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

After parsing, Glue should render only the original command's stdout/stderr,
minus the sentinel line.

### Exit-code preservation contract

This is critical.

If the user command exits with code `N`, Glue must behave exactly as if the raw
command exited with code `N`.

That means:

- Glue must not return success merely because sentinel emission succeeded
- Glue must not lose the original exit code when command fails
- Glue must still capture pwd even when the command fails, where possible

### Minimal shell-shape example

This is conceptual guidance, not exact required syntax:

```bash
cd "$SHELL_PWD"
{
  <user command>
}
status=$?
printf '\n__GLUE_SENTINEL_<nonce>__:%s:%s\n' "$status" "$PWD"
exit "$status"
```

An implementing agent may use a more robust form, but the behavioral contract
must remain the same.

## Shell wrapper edge cases

These edge cases are part of the implementation spec and must be considered.

### 1. Command fails before changing directory

Example:

```bash
cd does-not-exist
```

Expected:

- exit code reflects failure
- final pwd should remain the previous `shellPwd` if capture succeeds
- `shellPwd` must not become null/empty

### 2. Command changes directory then fails

Example:

```bash
cd ../glue && false
```

Expected:

- exit code reflects `false`
- `shellPwd` updates to `../glue` if final pwd capture succeeds

### 3. Command prints text similar to sentinel

Expected:

- parser should only recognize the exact nonce-bearing sentinel for this
  invocation
- user output should remain intact even if it contains other similar strings

### 4. Command has no stdout/stderr

Expected:

- Glue still captures sentinel and updates shell pwd
- rendered output may be empty
- exit code still preserved

### 5. Command produces trailing newlines / no trailing newline

Expected:

- sentinel parsing should not depend on pretty formatting quirks
- cleaned output should preserve user-visible output semantics as much as
  possible

### 6. Command is long-running but completes normally

Expected:

- sentinel capture still works
- no spinner/render regressions

### 7. Command is cancelled

Expected:

- if cancellation occurs before sentinel emission, `shellPwd` must remain the
  previous value
- do not infer shell pwd from partial output

### 8. Command times out or process crashes

Expected:

- preserve current Glue cancellation/error behavior
- do not update `shellPwd` unless a valid sentinel was parsed

### 9. Shell pwd contains spaces or special characters

Expected:

- quoting and parsing must support paths with spaces
- sentinel parsing must not split incorrectly on spaces

### 10. Shell pwd is deleted or becomes inaccessible between commands

Expected:

- next command should fail clearly or fall back to a defined behavior
- do not silently reset workspace root
- phase 1 recommendation: if `shellPwd` no longer exists, fall back to
  `workspaceRoot` for shell execution and emit a system message

## Docker/sandbox behavior contract

This is a special case and must not be hand-waved.

Current Docker execution mounts only the startup cwd as `/workspace`.

If shell pwd moves outside workspace root, Docker cannot automatically follow
that path unless additional host paths are mounted.

### Phase-1 required behavior

Implementation must choose and document one of these behaviors explicitly:

#### Option A — constrain shell pwd in Docker mode

- allow shell pwd updates only within workspace root
- if command attempts to end outside workspace root, either:
  - keep `shellPwd` unchanged, or
  - reset it to `workspaceRoot`
- emit a clear system message if reset/restricted

#### Option B — deny shell execution once shell pwd leaves mounted workspace

- shell pwd may still be tracked from prior host-mode or logical state
- but Docker shell execution outside mounted workspace is rejected clearly

### Recommendation

Use **Option A** for phase 1.

It is simpler and avoids pretending Docker supports something it does not.

### Required Docker tests

Whichever option is chosen, tests must assert the exact behavior. No silent
fallbacks.

### 6. Shell pwd persistence in session metadata

Files:

- `cli/lib/src/storage/session_store.dart`
- `cli/lib/src/session/session_manager.dart`
- `cli/lib/src/app/session_runtime.dart`
- `cli/lib/src/doctor/doctor.dart`

Schema evolution:

Add fields:

- `workspace_root`
- `shell_pwd`

Backward compatibility:

- when reading legacy sessions, treat `cwd` as `workspace_root`
- if `shell_pwd` is absent, default it to `workspace_root`

For session creation:

- set `workspace_root = _workspaceRoot`
- set `shell_pwd = _shellPwd`

For shell-pwd changes:

- update current session metadata when shell pwd changes
- persist without rotating the session identity

### 7. UI updates

Files:

- `cli/lib/src/app/command_helpers.dart`
- `cli/lib/src/app/render_pipeline.dart`
- `cli/lib/src/ui/panel_controller.dart`
- any status/header rendering paths

Behavior:

- normal session/project info should continue showing workspace root as the
  session directory/project identity
- bash mode/status can additionally show current shell pwd when it differs from
  workspace root
- resume/session list should continue grouping and searching primarily by
  workspace root, not shell pwd

Phase 1 UI should remain conservative. No large UX redesign is needed.

## Codebase Refactor Map

These are the concrete hotspots that need attention for this feature.

## A. App/runtime state

### `cli/lib/src/app.dart`

Current problem:

- `_cwd` is overloaded

Required change:

- split into `_workspaceRoot` and `_shellPwd`
- audit each use site

### `cli/lib/src/app/session_runtime.dart`

Current problem:

- session creation currently writes one cwd field

Required change:

- session creation writes both workspace root and shell pwd
- session resume defaults shell pwd correctly for older sessions

### `cli/lib/src/app/command_helpers.dart`

Current problem:

- session info and filters use `cwd`

Required change:

- continue using workspace root for project identity
- optionally expose shell pwd in session info when useful

## B. Prompt / project instructions

### `cli/lib/src/agent/prompts.dart`

Current problem:

- parameter name `cwd` hides true semantics

Required change:

- no functional change beyond ensuring this path uses workspace root
- renaming parameter is optional in phase 1, but recommended if it improves
  clarity in touched code

## C. Skills

### `cli/lib/src/skills/skill_runtime.dart`
### `cli/lib/src/skills/skill_registry.dart`

Required change:

- keep rooted to workspace root
- do not follow shell pwd

## D. File references / autocomplete

### `cli/lib/src/ui/at_file_hint.dart`
### `cli/lib/src/input/file_expander.dart`

Required change:

- keep rooted to workspace root
- app wiring should pass explicit workspace root rather than relying on
  `Directory.current`

That last part matters; fallback-to-process-cwd is sloppy and should be reduced
where touched.

## E. Permissions

### `cli/lib/src/orchestrator/permission_gate.dart`

Required change:

- use workspace root semantics
- rename internally where touched if it clarifies the model

## F. Shell execution

### `cli/lib/src/app/shell_runtime.dart`

Required change:

- wrap commands to run from `shellPwd`
- parse final pwd and exit code
- update app state
- persist metadata update
- strip wrapper artifacts from rendered output

### `cli/lib/src/shell/command_executor.dart`
### `cli/lib/src/shell/host_executor.dart`
### `cli/lib/src/shell/docker_executor.dart`
### `cli/lib/src/shell/executor_factory.dart`

Required change:

- possibly no broad redesign, but enough adaptation to support shell-pwd-aware
  execution cleanly
- Docker path handling needs extra care because current executor assumes a fixed
  mounted cwd at `/workspace`

This is one of the main risk areas.

## G. Session metadata / doctor / UI

### `cli/lib/src/storage/session_store.dart`
### `cli/lib/src/session/session_manager.dart`
### `cli/lib/src/ui/panel_controller.dart`
### `cli/lib/src/doctor/doctor.dart`

Required change:

- schema update
- read compatibility
- doctor validation update
- resume/list views continue using workspace root as the main directory field

## Risks And Gotchas

## 1. Docker executor mismatch

Current Docker execution mounts startup cwd as `/workspace`.

If shell pwd moves outside workspace root, Docker execution may not be able to
follow that path without additional mounts or explicit rejection.

For phase 1, implementation must define behavior clearly.

## 2. Sentinel parsing

Final-pwd capture must be robust.

Failure modes:

- sentinel appears in normal command output
- stderr/stdout ordering breaks parsing
- command failure masks pwd capture or vice versa

Use a highly unique sentinel and strip it before rendering.

## 3. Process `Directory.current`

Some helpers currently fall back to `Directory.current.path`.

That is dangerous if app state is supposed to be authoritative.
Where touched, prefer explicit workspace-root injection.

## 4. Session metadata churn

If shell pwd is persisted after every shell command, metadata writes will become
more frequent.

That is acceptable, but keep writes targeted and atomic.

## Test Coverage Specification

This implementation needs real coverage. Do not hand-wave it.

## A. App state separation

Add tests that verify:

1. startup initializes:
   - `workspaceRoot == shellPwd == Environment.cwd`

2. shell pwd changes do not change workspace root

3. session identity remains tied to workspace root after shell movement

## B. Shell runtime behavior — core contract

Add tests for bash runtime that verify:

1. a simple command runs from the initial shell pwd
2. `cd subdir && pwd` updates `shellPwd` to that subdir
3. `cd .. && pwd` updates `shellPwd` correctly
4. repeated commands start from the last tracked shell pwd
5. shell pwd updates on success
6. shell pwd updates on "change dir then fail" cases
7. shell pwd does not update when no valid sentinel is parsed
8. wrapper sentinel is not shown in rendered bash output
9. wrapper plumbing is not shown in rendered bash output
10. original command exit code is preserved exactly

## C. Shell runtime behavior — edge cases

Add explicit tests for:

1. command with no stdout and exit 0
2. command with no stdout and non-zero exit
3. command with large stdout still yields correct sentinel parsing
4. command output containing sentinel-like text does not confuse parser
5. command output ending without newline still parses correctly
6. command output with many trailing newlines still parses correctly
7. shell pwd containing spaces is handled correctly
8. shell pwd containing shell-sensitive characters is quoted correctly
9. cancelled command leaves `shellPwd` unchanged
10. timed-out/aborted command leaves `shellPwd` unchanged unless a valid
    sentinel was captured before termination
11. deleted/inaccessible `shellPwd` on next run falls back or errors according
    to chosen behavior

## D. Cross-project shell movement

Add tests that verify:

1. shell pwd can move outside workspace root in host mode
2. workspace root does not change when that happens
3. non-shell systems remain on workspace root after shell movement

Specifically test that after shell moves elsewhere:

- prompt build still uses workspace root
- skill runtime still uses workspace root
- file expansion still uses workspace root
- permission gate still uses workspace root

## E. Session metadata

Add tests for `SessionMeta` / `SessionStore` / `SessionManager` that verify:

1. new sessions write `workspace_root` and `shell_pwd`
2. legacy sessions with only `cwd` still load correctly
3. legacy `cwd` maps to `workspace_root`
4. missing `shell_pwd` defaults to `workspace_root`
5. updating shell pwd persists correctly without changing workspace root
6. resume preserves workspace root and shell pwd
7. malformed `shell_pwd` values are handled safely
8. metadata updates do not accidentally rotate or fork the session

## F. UI/session info behavior

Add tests that verify:

1. session info shows workspace/project directory as the primary directory
2. bash-specific/status output can show shell pwd when it differs
3. session list/search uses workspace root, not shell pwd, for primary grouping
4. legacy sessions still render correctly in resume/session list UI

## G. Docker-mode behavior

If Docker mode remains supported in this pass, add tests that verify the chosen
behavior explicitly.

### Required tests if phase-1 recommendation is followed

1. shell pwd updates within workspace root work under Docker mode
2. shell pwd attempts outside workspace root are rejected/reset per spec
3. user-visible messaging for this restriction is clear and deterministic
4. no silent execution in the wrong directory occurs

## H. Doctor / schema validation

Add tests that verify:

1. doctor accepts new metadata schema
2. doctor still tolerates legacy sessions with `cwd`
3. doctor reports malformed new metadata fields cleanly
4. doctor does not require `shell_pwd` for legacy sessions

## Suggested Test File Targets

Likely test files to modify/add:

- `cli/test/storage/session_store_test.dart`
- `cli/test/session/session_manager_test.dart`
- `cli/test/orchestrator/permission_gate_test.dart`
- `cli/test/input/file_expander_test.dart`
- `cli/test/ui/at_file_hint_test.dart`
- `cli/test/agent/prompts_test.dart`
- `cli/test/shell/*`
- `cli/test/app/*` or add a new focused shell-pwd app test file
- `cli/test/doctor/doctor_test.dart`

If shell runtime behavior is non-trivial, add dedicated test files such as:

- `cli/test/app/shell_pwd_tracking_test.dart`
- `cli/test/app/shell_wrapper_parsing_test.dart`

## Acceptance Criteria

This work is complete when:

1. Glue has distinct runtime concepts for workspace root and shell pwd
2. shell commands follow shell pwd across invocations
3. shell pwd updates after `cd`-style commands
4. original shell command exit codes are preserved exactly
5. sentinel/wrapper artifacts are never user-visible
6. session metadata stores both workspace root and shell pwd
7. prompts/skills/permissions/file refs remain rooted to workspace root
8. Docker-mode behavior is explicit and tested
9. no `/cwd` command is introduced
10. tests cover host-mode shell-pwd updates, metadata compatibility, and
    workspace-root isolation

## Non-Goals Reminder

Do not sneak these into the same PR:

- workspace switching
- shell-pwd promotion
- multi-root editing semantics
- file tools following shell pwd
- big UI redesign

That is scope creep, and it will make the implementation sloppier.

## Hand-off Guidance

If another agent implements this later, they should approach it in this order:

1. split app state
2. update session schema/read compatibility
3. implement shell wrapper + final pwd capture + exit-code preservation
4. wire metadata persistence
5. update targeted UI/status rendering
6. add/adjust tests
7. only then do optional renaming in touched paths for clarity

Do not start with global renames. Start with semantic separation.
