# Phase 0 - Baseline And Guardrails

## Objective

Create a stable baseline before architectural changes. This phase should make the current behavior measurable, remove stale test discovery issues, and document constraints that all later phases must preserve.

## Why This Comes First

The current workspace already has rename churn around provider tests and several unrelated modified files. Refactoring without a clean behavioral baseline makes regressions indistinguishable from pre-existing failures.

## Current Problems Addressed

- Full `dart test` currently attempts to load a stale Ollama adapter test path.
- The suite needs to be green or have explicitly documented expected failures before files start moving.
- There is no local refactor target architecture document.
- Existing large files make it easy to mix behavior changes with structural moves.

## Files Expected To Be Touched

Primary:

- `cli/dart_test.yaml`
- `cli/test/providers/ollama_provider_test.dart`
- any stale test import or discovery references related to `ollama_adapter_test.dart`
- `refactor/GOAL.md`
- `refactor/PHASE-*.md`

Possible:

- `cli/README.md`, only if it contains stale architecture notes
- `cli/test/helpers/*`, if a baseline helper is needed

Do not touch runtime implementation files in this phase unless needed to fix an existing broken test reference.

## Desired Output Shape

The end of this phase should look like this:

```text
refactor/
  GOAL.md
  PHASE-0.md
  PHASE-1.md
  PHASE-2.md
  PHASE-3.md
  PHASE-4.md
  PHASE-5.md
  PHASE-6.md
  PHASE-7.md
```

The codebase shape should otherwise remain unchanged.

## Work Items

1. Fix stale provider test discovery.
   - Remove references to `test/providers/ollama_adapter_test.dart`.
   - Confirm the active test file name is `test/providers/ollama_provider_test.dart`.
   - Do not reintroduce old `Adapter` naming just to satisfy stale tests.

2. Run the baseline checks.
   - `dart analyze`
   - `dart test -j 1`
   - targeted tests for runtime input routing if parallel terminal-size failures appear.

3. Record expected failures if any remain.
   - Prefer fixing stale references.
   - If a failure is environmental, document the exact command and failure mode.

4. Add or update refactor documentation only.
   - Keep the architecture goal separate from phase plans.
   - Each phase must list touched files and desired end-state structure.

5. Avoid behavior changes.
   - This phase is allowed to fix broken test discovery.
   - It should not change runtime behavior, config semantics, tool behavior, provider behavior, or UI behavior.

## Acceptance Criteria

- `dart analyze` passes.
- `dart test -j 1` passes, or remaining failures are documented as pre-existing environmental failures with exact commands.
- The stale Ollama adapter test path is gone.
- No runtime architecture changes are mixed into this phase.
- Refactor documents exist and can be reviewed independently.

## Risks

- Test discovery may be failing because of generated metadata or a previous rename, not an explicit import. If so, inspect test package configuration before changing production code.
- Existing dirty worktree changes may already include partial refactors. Do not revert them. Work with the current state.

## Non-Goals

- Do not remove `ServiceLocator`.
- Do not rename `GlueConfig`.
- Do not move files.
- Do not split `App`, `Turn`, `Session`, or tools yet.
