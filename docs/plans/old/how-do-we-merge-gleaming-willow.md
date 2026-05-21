# Consolidate `refactor/c1-turn` into `main` and clean up branches

## Context

The harness-layers PR (#29) squash-merged into `main` as commit `bfefc83`. That PR took a different architectural direction than `refactor/c1-turn` (sibling branches off the same ancestor `9d7c38e`, not parent/child). The harness-layers approach won — `main` now has sibling packages (`glue_harness`, `glue_strategies`, `glue_core`, `glue_server`), an ACP server, prompt caching, and token-usage tracking. `CLAUDE.md` on `main` was rewritten to describe the new layout.

`refactor/c1-turn` is now **93 commits divergent** from `main`. Most of those commits are now-obsolete architecture work (Group A/B/C/D1 restructure, runtime/ui split, services extraction) — duplicating the same problem the harness-layers PR solved differently. A `git merge` would conflict heavily and produce a Frankenstein of two parallel refactors.

**However**, `refactor/c1-turn` also has standalone *feature* commits not on `main` and worth preserving. Strategy: cherry-pick the features, drop the architecture commits, delete the branch. Plus tidy up stale `copilot/*` branches and the already-merged PR branch.

## Audit: feature commits unique to `refactor/c1-turn`

These show up in `git log --oneline origin/main..origin/refactor/c1-turn` filtered to `feat/fix`:

| Commit | Subject | Probably already on main? |
|---|---|---|
| `a367532` | plumb Gemini thoughtSignature through ToolCall round-trip | No |
| `b184f97` | feat(providers): add native Gemini Developer API adapter | **No** — main has Anthropic/OpenAI/Copilot only |
| `0ec4fc9` | feat(context): backport context-window management | Likely overlaps — main has token-usage tracking from PR #29 |
| `318e64d` | fix(app): close session and jobs before observability sinks | Maybe redundant — main has rewritten lifecycle |
| `09c7367` | fix(observability+runtime): tighten span lifecycle | Maybe redundant |
| `b91a6cd` | feat(observability): add OTLP/HTTP protobuf export path | **Possibly unique** — needs check |
| `37810b5` | feat(commands): add `/copy` command | **No** — feature absent on main |
| `132b5b6` | feat(model-picker): retain provider group headers when filtering | **No** |
| `50f4b5b` | feat(model-picker): show api name in MODEL column | **No** |
| `734197c` | feat(commands): merge `/models` into `/model` as alias | **No** |
| `9af58c1` | feat(catalog): refresh models.yaml for 2026-04 + reasoning/Llama 4 | **Yes, partially** — main has its own catalog updates; needs merge of yaml |
| `6c5b1ce` `2eaf9e0` `f4a0642` `a78c7c5` `f68afc1` | observability/share/session/cli polish | Mixed — case-by-case |

Also untracked on disk + in `stash@{0}` (uncommitted feature work):
- SIGINT two-press handling (`app.dart`, `print_mode_sigint_test.dart`, `sigint_helper_main.dart`, `docs/reference/sigint-handling.md`)
- Paste support in `input_router.dart` + test
- Copy action in `ui/actions/chat_actions.dart` + test
- API key prompt panel changes + test

## Plan

### Phase 1: Audit — DONE

| Feature | Status on main | Action |
|---|---|---|
| Gemini provider (`b184f97`) | MISSING | Cherry-pick + adapt to `packages/glue_strategies/lib/src/providers/` |
| Gemini thoughtSignature (`a367532`) | MISSING | Cherry-pick after provider |
| `/copy` slash command (`37810b5`) | MISSING (main has `/session copy` only) | Cherry-pick to `cli/lib/src/commands/builtin_commands.dart` |
| `/models→/model` alias (`734197c`) | PARTIAL — both still exist on main | Cherry-pick |
| Catalog refresh (`9af58c1`) | MISSING — main last bumped 2026-02-01, no `claude-sonnet-4.5` etc. | Diff + merge yaml |
| SIGINT two-press (stash + untracked) | MISSING | Salvage as Phase 2, port to new layout |
| Model picker tweaks (`132b5b6`,`50f4b5b`) | PRESENT in `cli/lib/src/ui/model_panel_formatter.dart` + `cli/lib/src/app/model_display.dart` | Skip |
| Paste handling | PRESENT in `cli/lib/src/input/text_area_editor.dart` | Skip |
| Share/session polish | PRESENT under `packages/glue_harness/lib/src/share/` | Skip |
| API key panel | PRESENT (`cli/lib/src/ui/api_key_prompt_panel.dart`) | Skip basics; verify any tweak still relevant |
| OTLP HTTP (`b91a6cd`) | PARTIAL — main has JSON, refactor adds protobuf path | Defer — investigate if user wants |
| Context-window mgmt (`0ec4fc9`) | LIKELY PARTIAL via main's token-usage tracking | Defer |

New on-main package layout:
- `packages/glue_core/` — catalog, models, types
- `packages/glue_harness/` — harness, observability, share, catalog generation
- `packages/glue_strategies/` — providers, adapters
- `packages/glue_server/` — server mode
- `cli/lib/src/` retains: `acp/`, `app/`, `commands/`, `doctor/`, `input/`, `rendering/`, `terminal/`, `ui/`

### Phase 2: Salvage uncommitted work (single commit on a salvage branch)

Currently on `main` with untracked sigint/paste/copy/api-key files and a `stash@{0}` from `refactor/c1-turn`. Don't apply them onto main yet — they were written against the old layout.

1. `git checkout refactor/c1-turn` (returns to where the stash applies cleanly)
2. `git stash pop stash@{0}` and `git add` the untracked files
3. `git commit -m "feature work: sigint two-press + paste + copy action + api-key prompt"`
4. Push so it's safe (`git push`)

That preserves the work as a real commit on `refactor/c1-turn` — we'll cherry-pick it in Phase 3.

### Phase 3: Cherry-pick onto `main` via small PRs

Create a salvage branch off `main`:

```sh
git checkout main
git pull
git checkout -b salvage/from-c1-turn
```

Cherry-pick **only** the commits the audit flagged as missing. Order: smallest/independent first to surface conflicts early. Expected order:
1. `9af58c1` catalog refresh (yaml-only — check for collision with main's catalog and merge)
2. `b184f97` Gemini provider (paths likely shifted — adapt to new `glue_strategies` or whichever package owns providers now)
3. `a367532` Gemini thoughtSignature (depends on Gemini provider being in)
4. `37810b5` `/copy` command
5. `132b5b6` + `50f4b5b` model-picker tweaks
6. `734197c` `/model` alias
7. The salvage commit from Phase 2 (sigint + paste + copy action + api-key) — likely the most rework since `app.dart` and `runtime/turn.dart` no longer exist in the harness-layers layout
8. (Conditional, per audit) OTLP HTTP exporter, share/session polish

For each: `git cherry-pick <sha>`, fix conflicts to land in the new layout, run `just check`, then continue. If a cherry-pick balloons into a rewrite, stop and either commit the partial work as a new feature or skip it entirely — don't force-fit.

Push and open a PR (or several smaller ones if the changes naturally split). Verify CI green.

### Phase 4: Branch cleanup (after salvage PR(s) merged)

Delete in this order, all via `gh` or `git push origin --delete`:

1. `origin/claude/architect-harness-layers-maSVJ` — already squash-merged into `main`. Safe.
2. `origin/refactor/c1-turn` and local `refactor/c1-turn` — once Phase 3 lands and you've confirmed nothing else worth saving. Safe after audit.
3. The five `origin/copilot/*` branches — confirm none have open PRs, then delete:
   - `copilot/add-context-window-management-system`
   - `copilot/add-mcp-server-support`
   - `copilot/explore-deepwiki-docs-generation`
   - `copilot/investigate-lightweight-web-ui-driver`
   - `copilot/research-acp-server-in-glue`
4. Drop the leftover `stash@{1}` (`HelgeSverre/cli-prompt-arg`) only if confirmed dead.

## Verification

After each cherry-pick:
- `just check` (gen-check + analyze + test) green
- `dart format --set-exit-if-changed .` clean
- For UI/CLI features, smoke-test in a `dart run bin/glue.dart` session: `/copy`, `/model` alias, model picker filtering, Gemini provider auth + a real call, sigint two-press in `--print` mode, `@file` paste

After Phase 4:
- `git branch -a` shows only `main` and any in-flight feature branches
- `gh pr list --state open` shows nothing referencing the deleted branches

## Critical files / references

- `cli/lib/src/providers/gemini_provider.dart` — exists on `refactor/c1-turn`, needs porting to whatever package owns providers in the harness-layers layout
- `cli/lib/src/llm/message_mapper.dart` — `GeminiMessageMapper` lives here
- `cli/lib/src/agent/agent.dart` — `ToolCall.thoughtSignature` field
- `docs/reference/models.yaml` — catalog source
- `docs/reference/sigint-handling.md` (untracked) — design doc for the two-press SIGINT flow; commit it as part of Phase 2
- `cli/test/_helpers/sigint_helper_main.dart` (untracked) — fixture for sigint test

## Risks / unknowns

- **Some "features" on `refactor/c1-turn` may turn out to already be on `main`** under different names from the harness-layers PR. The audit is what surfaces this. Save effort by skipping any whose behavior already exists.
- **Path renames** in the harness-layers refactor mean every cherry-pick will likely have surface-level conflicts (file moved, class renamed). These are mechanical but slow.
- **`refactor/c1-turn`'s sigint work uses `runtime/turn.dart`** which the harness-layers PR may have moved into `glue_harness`. The salvage commit from Phase 2 may need substantial rework — set expectations accordingly.
- **Don't force-merge.** If Phase 3 turns out to require rewriting the features rather than cherry-picking, recognize that early and treat it as a fresh feature implementation referencing the old branch as a spec, not a patch source.
