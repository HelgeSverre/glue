# Bundled Assets + Skill Runtime Refactor Plan

> Status: design / planning only. No code changes in this plan.
> Re-spec'd 2026-04-30 against the harness/strategies/core split.

## Goal

Replace Glue's current repo/install-layout-dependent bundled skill discovery with a small, explicit bundled-asset system that:

1. Treats built-in skills as packaged application assets.
2. Embeds those assets into the build artifact via codegen.
3. Syncs them into a Glue-managed runtime directory under `GLUE_HOME` on startup.
4. Simplifies skill discovery so it no longer depends on `Platform.script`, repo-relative path guesses, or `GLUE_BUNDLED_SKILLS_DIR`.

This plan also establishes a minimal general-purpose `AssetBundle` concept that can later support other simple bundled text assets, such as markdown-backed slash commands, without overengineering a plugin/package system.

## How this plan relates to the harness layers

Skills are a **harness-level** subsystem (see `2026-04-29-harness-layers.md`):
they sit at the same level as session storage and observability and run inside
`Glue.open()` long before any surface attaches.

Important consequence for asset bundling: bundled skill assets must be authored
and embedded in a place that all surfaces share. The CLI is no longer the only
distributable artifact — `glue serve` (ACP server in `packages/glue_server/`)
also needs the same skills, and a future `glue_web` surface will too. So the
asset source must live inside the harness package, not the CLI surface
package.

That changes one major decision from the original plan: bundled assets live
under `packages/glue_harness/assets/`, generated into
`packages/glue_harness/lib/src/skills/assets_generated.dart`, and consumed by
the harness's `SkillRegistry`. Surfaces never see asset bytes — they see
discovered skills via the existing harness API.

## Problem Statement

### Current behavior is install-fragile

Bundled skills currently live in `cli/skills/` and are discovered via
`packages/glue_harness/lib/src/skills/skill_paths.dart`, which:

1. optionally reads `GLUE_BUNDLED_SKILLS_DIR`
2. otherwise derives paths from `Platform.script`
3. tries guessed locations like:
   - `<packageRoot>/skills`
   - `<packageRoot>/cli/skills`

That makes built-in skill availability depend on the runtime filesystem layout
of the executable or source checkout — and worse, it embeds knowledge of the
CLI surface's directory layout into the harness package. A separately
distributed `glue serve` binary or an ACP-only client cannot rely on those
paths existing.

This is the wrong abstraction for a distributable harness. Installed Glue
should assume:

- the source repo is not present
- `cli/skills/` is not visible on disk
- only the installed executable and `~/.glue/` (= `GLUE_HOME`) are guaranteed

### Current behavior complicates the mental model

Today, the term "bundled skill" really means "a skill found by looking near
the executable or repo checkout." That is surprising and hard to reason
about, and it bleeds surface assumptions into the harness.

It also creates implementation noise:

- `GLUE_BUNDLED_SKILLS_DIR` exists mainly as an escape hatch
- `skill_paths.dart` performs self-location heuristics
- tests validate path guessing behavior rather than the desired install/runtime contract

### Desired behavior

Built-in skills should behave like other packaged harness resources:

- authored in the repo under the harness package
- embedded in the distributed artifact via `dart run tool/gen_assets.dart`
- materialized into a stable runtime location owned by Glue
- discovered from explicit, deterministic paths only
- visible identically to all surfaces (CLI, ACP server, future web)

## Goals

1. **Self-contained install behavior**
   - A user on a separate machine with only an installed Glue binary should always get built-in skills.

2. **Surface independence**
   - Built-in skill assets must not live in any surface package. Both `glue` (CLI) and `glue serve` binaries must produce the same built-in skills.

3. **Explicit runtime ownership**
   - Built-in assets should live in a Glue-managed subtree under `GLUE_HOME`, separate from user-authored global skills.

4. **Minimal reusable asset system**
   - Introduce a small `AssetBundle` abstraction that supports current skill bundling and can be reused later for simple bundled markdown/text assets.

5. **Simpler skill discovery**
   - Remove executable-relative path guessing and discover skills from explicit directories only.

6. **Preserve user override precedence**
   - Project and user skills must still override built-in skills by name.

## Non-Goals

1. A plugin/package manager for third-party assets.
2. General binary asset packaging in this first iteration.
3. Implementing markdown-backed slash commands in this change.
4. Cross-platform executable permission metadata handling for bundled binaries.
5. Any runtime network fetch for built-in assets.

## Proposed Design

### 1. Move built-in repo assets under `packages/glue_harness/assets/`

Create a new repo asset root under the harness package:

- `packages/glue_harness/assets/skills/<skill-name>/SKILL.md`

This replaces `cli/skills/` as the source of truth for built-in skills.

Rationale:

- clarifies that these are packaged harness resources, not surface files
- both `cli` and `glue_server` consume them transitively via the harness
- creates a natural namespace for future bundled harness resources
- avoids conflating any one surface's repo layout with runtime skill discovery

Future-compatible asset families may include:

- `packages/glue_harness/assets/skills/...`
- `packages/glue_harness/assets/slash-commands/...` (harness-defined slash commands; surface-only commands stay in surface packages)
- `packages/glue_harness/assets/templates/...`

But this plan only implements `assets/skills`.

### 2. Add build-time asset codegen

Add a generator inside the harness package:

- `packages/glue_harness/tool/gen_assets.dart`

Responsibilities:

- scan `packages/glue_harness/assets/skills/**`
- read UTF-8 text files
- generate `packages/glue_harness/lib/src/skills/assets_generated.dart`
- support both normal mode and `--check`
- follow existing generator conventions used by `cli/tool/gen_models.dart` and `cli/tool/gen_version.dart`

The generated file embeds bundled assets directly into Dart source. Wire it
into the monorepo `just gen` and `just gen-check` recipes alongside the
existing model catalog and version generators.

#### Generated representation

Keep the representation small and text-focused.

Suggested types in `packages/glue_harness/lib/src/skills/asset_bundle.dart`:

```dart
class BundledAssetFile {
  final String relativePath;
  final String content;
  final String sha256;
  const BundledAssetFile({
    required this.relativePath,
    required this.content,
    required this.sha256,
  });
}

class BundledAssetBundle {
  final String id;
  final List<BundledAssetFile> files;
  const BundledAssetBundle({required this.id, required this.files});
}
```

Generated constant example:

```dart
const BundledAssetBundle bundledSkillsBundle = BundledAssetBundle(
  id: 'skills',
  files: [...],
);
```

Intentionally limited to text assets in v1.

### 3. Introduce a tiny runtime asset install/sync layer

Add a small runtime asset module **inside the harness**:

- `packages/glue_harness/lib/src/skills/asset_bundle.dart` (data types)
- `packages/glue_harness/lib/src/skills/asset_installer.dart` (sync logic)

Public surface in the harness barrel (`packages/glue_harness/lib/glue_harness.dart`):

- `AssetInstaller`
- `BundledAssetBundle`

Surfaces never call these directly — `Glue.open()` invokes them during
startup. They remain public only for testing.

#### `AssetInstaller` responsibilities

- ensure target directory exists
- write missing files
- overwrite changed files
- prune stale files previously managed by the same bundle
- never touch user-owned directories outside the managed target subtree

Suggested API:

```dart
class AssetInstaller {
  static void installAll(Environment environment);
  static void syncBundleToDirectory(
    BundledAssetBundle bundle,
    String targetDir,
  );
}
```

`installAll()` is small and explicit. v1 installs only the bundled skills bundle.

### 4. Materialize built-in skills under `GLUE_HOME`

Built-in skills are installed into a Glue-managed subtree under
`Environment.skillsDir` (`packages/glue_harness/lib/src/core/environment.dart`).

Recommended target:

- `<GLUE_HOME>/skills/_builtin/<skill-name>/SKILL.md`

Not directly into `<GLUE_HOME>/skills/<skill-name>/`.

#### Why use `_builtin`

This keeps Glue-owned files separate from user-owned global skills.

Benefits:

- avoids accidental overwrite of user files
- makes ownership clear during upgrades
- allows Glue to re-sync built-ins freely
- preserves a clean override model: users override by placing a same-named skill in project/global locations

### 5. Simplify skill discovery to explicit paths only

Refactor `packages/glue_harness/lib/src/skills/skill_runtime.dart` and
`skill_registry.dart` so bundled built-ins come from the managed runtime dir,
not from executable-relative lookup.

After the refactor, skill discovery sources should be:

1. project-local: `<workspaceRoot>/.glue/skills`
2. configured extra paths: `skill_paths`
3. global user: `<GLUE_HOME>/skills`
4. built-in managed: `<GLUE_HOME>/skills/_builtin`

#### Remove current bundled path heuristics

Delete or obsolete:

- `packages/glue_harness/lib/src/skills/skill_paths.dart`
- `GLUE_BUNDLED_SKILLS_DIR`
- `Platform.script`-derived bundle lookup
- repo-relative `skills/` or `cli/skills/` probing

The harness should no longer try to locate its own source tree.

### 6. Add an explicit builtin skill source label

Today built-in skills discovered via `bundledPaths` are effectively labeled as
`SkillSource.custom`.

Add a dedicated source variant in `packages/glue_harness/lib/src/skills/skill_parser.dart`:

```dart
enum SkillSource { project, global, custom, builtin }
```

This improves:

- `/skills` UI labeling (CLI surface)
- ACP responses (`glue_server` mapping uses the same enum)
- tests
- internal clarity
- future observability/debugging

### 7. Install bundled assets before skill runtime initialization

In `packages/glue_harness/lib/src/core/service_locator.dart` `ServiceLocator.create()`:

1. resolve environment
2. ensure Glue directories exist
3. install bundled assets into managed runtime dirs
4. initialize `SkillRuntime`
5. build prompt from discovered skills

Both `cli/` and `glue_server/` already construct their dependencies via
`ServiceLocator`, so this single change lights up both surfaces.

### 8. Slightly expand `Environment.ensureDirectories()`

`Environment.ensureDirectories()` currently creates:

- `sessionsDir`
- `logsDir`
- `cacheDir`

Because built-in skills will now be materialized under `skillsDir`, also ensure:

- `skillsDir`

The `_builtin` subdirectory itself can still be created by the installer.

## Sync Strategy

### Recommended v1 sync behavior

Use per-file content hashes plus a small manifest written into the managed target directory.

Example:

- `<GLUE_HOME>/skills/_builtin/.bundle-manifest.json`

Manifest contents:

- bundle id
- file list
- content hashes
- harness version that wrote it (use `glue_core/version_generated.dart`)

### Installer behavior

For each bundle sync:

1. read manifest if present
2. compare expected files/hashes to current bundle
3. write changed or missing files
4. prune files previously managed by the bundle that no longer exist in the generated bundle
5. rewrite manifest

This gives deterministic upgrades while containing all mutation within the Glue-owned managed subtree.

### Why not skip the manifest entirely?

Comparing file contents directly would work for v1, but a manifest makes safe pruning easier when built-in skills are renamed or removed. Worth the small complexity cost.

## API Simplicity Constraints

### Allowed complexity

- one generated assets file per harness build
- one installer module
- one managed runtime target for skills
- one manifest per installed bundle

### Disallowed complexity for this iteration

- asset registries with dynamic plugin hooks
- bundle dependency graphs
- platform-target selection logic
- compression, archive extraction, or remote downloads
- generic executable-permission management

Should feel like "embedded files synced to a target directory," not a framework.


## Future Reuse

This plan intentionally leaves room for future bundled text assets without implementing them now.

Potential future uses:

1. **Markdown-backed slash commands**
   - e.g. `packages/glue_harness/assets/slash-commands/<name>.md`
   - materialized into a Glue-managed command asset dir

2. **Prompt templates or docs snippets**
   - stored in `packages/glue_harness/assets/templates/...`

3. **Small helper config files**
   - bundled defaults or examples

If future binary bundling is ever needed, the naming can remain compatible, but binary support itself stays out of scope for this iteration.

## Detailed Refactor Plan

### Phase 1 — Asset source + generator

1. Create `packages/glue_harness/assets/skills/`
2. Move existing built-in skills from `cli/skills/` to `packages/glue_harness/assets/skills/`
3. Add `packages/glue_harness/tool/gen_assets.dart`
4. Add generated file output: `packages/glue_harness/lib/src/skills/assets_generated.dart`
5. Update root `justfile` and per-package recipes:
   - include `gen_assets.dart` in monorepo `just gen`
   - include `gen_assets.dart --check` in monorepo `just gen-check`

#### Acceptance criteria

- `just gen` regenerates assets successfully
- `just gen-check` fails when generated assets are stale
- generated asset file contains all built-in skills from `packages/glue_harness/assets/skills`

### Phase 2 — Runtime asset install support

1. Add runtime asset types and installer in `packages/glue_harness/lib/src/skills/`
2. Add managed install target for built-in skills
3. Update `Environment.ensureDirectories()` to create `skillsDir`
4. Hook asset installation into `ServiceLocator.create()` before `SkillRuntime` init

#### Acceptance criteria

- a fresh `GLUE_HOME` gets a populated built-in skills subtree on startup, in both CLI and ACP-server invocations
- repeated startup is idempotent
- removed/renamed built-in skills are pruned from the managed subtree

### Phase 3 — Skill runtime/discovery simplification

1. Remove bundled path discovery heuristics from `SkillRuntime`
2. Remove `packages/glue_harness/lib/src/skills/skill_paths.dart`
3. Remove `GLUE_BUNDLED_SKILLS_DIR`
4. Point bundled skill discovery at `<GLUE_HOME>/skills/_builtin`
5. Add `SkillSource.builtin` and propagate through ACP mappings in `glue_server`
6. Update skill discovery help text in CLI commands and ACP responses

#### Acceptance criteria

- no harness code depends on `Platform.script` to find built-in skills
- no code references `GLUE_BUNDLED_SKILLS_DIR`
- built-in skills are discovered from the managed Glue runtime dir only
- project/global/custom precedence still works
- ACP `session/list_skills` (or equivalent) reports the new source label

### Phase 4 — Tests and docs

1. Replace path-guessing tests with install/sync tests in `packages/glue_harness/test/skills/`
2. Rewrite bundled skill tests to validate generated/install behavior rather than repo-relative lookup
3. Update docs/comments that refer to `cli/skills/`
4. Update plan and architecture docs where skill bundling/runtime locations are described

#### Acceptance criteria

- tests cover generator output freshness
- tests cover startup install into managed builtin dir
- tests cover skill precedence with builtin/global/project collisions
- no docs mention `GLUE_BUNDLED_SKILLS_DIR`
- no docs describe repo-relative bundled skill discovery as the runtime model

## Files Likely Affected

### New files

- `packages/glue_harness/tool/gen_assets.dart`
- `packages/glue_harness/lib/src/skills/asset_bundle.dart`
- `packages/glue_harness/lib/src/skills/asset_installer.dart`
- `packages/glue_harness/lib/src/skills/assets_generated.dart`
- new tests under `packages/glue_harness/test/skills/`

### Moved / reorganized files

- `cli/skills/**` → `packages/glue_harness/assets/skills/**`

### Modified files

- root `justfile`, `cli/justfile`, and `packages/glue_harness/` justfile/recipes
- `packages/glue_harness/lib/src/core/service_locator.dart`
- `packages/glue_harness/lib/src/core/environment.dart`
- `packages/glue_harness/lib/src/skills/skill_runtime.dart`
- `packages/glue_harness/lib/src/skills/skill_registry.dart`
- `packages/glue_harness/lib/src/skills/skill_parser.dart` (for `SkillSource.builtin`)
- `packages/glue_harness/lib/glue_harness.dart` (barrel)
- ACP mappers in `packages/glue_server/lib/src/acp/` (if they expose source labels)
- docs/tests referencing current layout

### Removed files

- `packages/glue_harness/lib/src/skills/skill_paths.dart`
- `packages/glue_harness/test/skills/skill_paths_test.dart` (if present; otherwise the `cli` test analogue)

## Test Strategy

### Unit tests (in `packages/glue_harness/test/skills/`)

1. **Generator tests**
   - generated file is fresh
   - embedded relative paths are correct
   - embedded contents round-trip correctly

2. **Installer tests**
   - installs files into empty target dir
   - updates changed files
   - preserves identical files without churn
   - prunes stale managed files
   - does not touch unrelated user files outside bundle manifest scope

3. **Skill discovery tests**
   - built-in managed dir is discovered as `SkillSource.builtin`
   - project/global/custom override builtin by name
   - body loading works from installed builtin files

### Cross-surface regression tests

1. CLI startup with empty `GLUE_HOME` still exposes built-in skills in prompt/tool list (`cli/test/`)
2. `glue serve --stdio` startup with empty `GLUE_HOME` exposes the same skills via ACP (`packages/glue_server/test/`)
3. `/skills` UI still sees bundled built-ins (CLI surface)
4. `skill` tool still loads built-in skill bodies correctly
5. `just gen-check` fails if bundled assets generator output is stale

## Migration Notes

### Directory migration

The repo source directory for built-ins changes from:

- `cli/skills/`

to:

- `packages/glue_harness/assets/skills/`

### Runtime migration

Users do not need to copy any files manually. Built-ins are reinstalled by Glue into:

- `<GLUE_HOME>/skills/_builtin`

…regardless of which surface they launched (CLI or `glue serve`).

### Precedence remains stable

Users can still override built-ins by placing same-named skills in:

- project `.glue/skills/<name>/SKILL.md`
- global `<GLUE_HOME>/skills/<name>/SKILL.md`
- configured custom paths

## Open Questions

1. **Should the manifest live inside the bundle target dir or under cache?**
   - Recommendation: keep it inside the managed target dir for locality and easier debugging.

2. **Should bundled skill files be rewritten on every startup or only when changed?**
   - Recommendation: only when changed, using manifest/hash comparison.

3. **Should built-in asset installation failures be fatal?**
   - Recommendation: treat as non-fatal but visible. Glue should continue running, but diagnostics/logging via `ObservabilityHub` should make the failure obvious.

4. **Should `global` discovery include `_builtin` implicitly or should builtin always be passed explicitly?**
   - Recommendation: keep builtin explicit. Do not make `SkillRegistry` infer managed builtin subdirectories automatically.

5. **Does `glue_server` need a way to opt out of bundled-skill install?**
   - Recommendation: no. ACP clients expect parity with CLI; an opt-out would create a divergence with no clear use case. Reconsider only when a specific deploy needs read-only `GLUE_HOME`.

## Acceptance Criteria Summary

This plan is complete when:

1. built-in skills no longer depend on repo/executable-relative lookup
2. `GLUE_BUNDLED_SKILLS_DIR` is removed entirely
3. `packages/glue_harness/lib/src/skills/skill_paths.dart` is removed
4. built-in skills are authored under `packages/glue_harness/assets/skills`
5. generated embedded assets are produced by codegen and checked by `just gen-check`
6. startup materializes bundled built-ins into `<GLUE_HOME>/skills/_builtin` for both CLI and ACP-server entry points
7. skill discovery reads built-ins from the managed runtime dir only
8. user/project/custom precedence still overrides built-ins
9. the asset-bundling abstraction remains small and text-focused

## Recommended Implementation Notes

- Author bundled assets in the harness package, never the surface package, so all surfaces share one source of truth.
- Prefer `assets_generated.dart` over package-manager asset bundling assumptions, since Glue must work as a standalone compiled binary on multiple surfaces.
- Prefer explicit managed subtrees under `GLUE_HOME` over mixing Glue-owned and user-owned files in the same directory level.
- Keep the API intentionally small so future asset families can reuse it without forcing a framework onto the codebase.
- Do not add binary support until a concrete use case exists.
