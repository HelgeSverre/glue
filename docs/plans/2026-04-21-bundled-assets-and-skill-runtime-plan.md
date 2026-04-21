# Bundled Assets + Skill Runtime Refactor Plan

> Status: design / planning only. No code changes in this plan.

## Goal

Replace Glue's current repo/install-layout-dependent bundled skill discovery with a small, explicit bundled-asset system that:

1. Treats built-in skills as packaged application assets.
2. Embeds those assets into the build artifact via codegen.
3. Syncs them into a Glue-managed runtime directory under `GLUE_HOME` on startup.
4. Simplifies skill discovery so it no longer depends on `Platform.script`, repo-relative path guesses, or `GLUE_BUNDLED_SKILLS_DIR`.

This plan also establishes a minimal general-purpose `AssetBundle` concept that can later support other simple bundled text assets, such as markdown-backed slash commands, without overengineering a plugin/package system.

## Problem Statement

### Current behavior is install-fragile

Bundled skills currently live in `cli/skills/` and are discovered via `cli/lib/src/skills/skill_paths.dart`, which:

1. optionally reads `GLUE_BUNDLED_SKILLS_DIR`
2. otherwise derives paths from `Platform.script`
3. tries guessed locations like:
   - `<packageRoot>/skills`
   - `<packageRoot>/cli/skills`

That makes built-in skill availability depend on the runtime filesystem layout of the executable or source checkout.

This is the wrong abstraction for a distributable CLI. Installed Glue should assume:

- the source repo is not present
- `cli/skills/` is not visible on disk
- only the installed executable and user data directories are guaranteed

### Current behavior complicates the mental model

Today, the term “bundled skill” really means “a skill found by looking near the executable or repo checkout.” That is surprising and hard to reason about.

It also creates implementation noise:

- `GLUE_BUNDLED_SKILLS_DIR` exists mainly as an escape hatch
- `skill_paths.dart` performs self-location heuristics
- tests validate path guessing behavior rather than the desired install/runtime contract

### Desired behavior

Built-in skills should behave like other packaged application resources:

- authored in the repo
- embedded in the distributed artifact
- materialized into a stable runtime location owned by Glue
- discovered from explicit, deterministic paths only

## Goals

1. **Self-contained install behavior**
   - A user on a separate machine with only the installed Glue artifact should always get built-in skills.

2. **Explicit runtime ownership**
   - Built-in assets should live in a Glue-managed subtree under `GLUE_HOME`, separate from user-authored global skills.

3. **Minimal reusable asset system**
   - Introduce a small `AssetBundle` abstraction that supports current skill bundling and can be reused later for simple bundled markdown/text assets.

4. **Simpler skill discovery**
   - Remove executable-relative path guessing and discover skills from explicit directories only.

5. **Preserve user override precedence**
   - Project and user skills must still override built-in skills by name.

## Non-Goals

1. A plugin/package manager for third-party assets.
2. General binary asset packaging in this first iteration.
3. Implementing markdown-backed slash commands in this change.
4. Cross-platform executable permission metadata handling for bundled binaries.
5. Any runtime network fetch for built-in assets.

## Proposed Design

## 1. Move built-in repo assets under `cli/assets/`

Create a new repo asset root:

- `cli/assets/skills/<skill-name>/SKILL.md`

This replaces `cli/skills/` as the source of truth for built-in skills.

Rationale:

- clarifies that these are packaged assets, not runtime-discovered source files
- creates a natural namespace for future bundled resources
- avoids conflating repo layout with runtime skill discovery

Future-compatible asset families may include:

- `cli/assets/skills/...`
- `cli/assets/slash-commands/...`
- `cli/assets/bin/...`

But this plan only implements `assets/skills`.

## 2. Add build-time asset codegen

Add a generator:

- `cli/tool/gen_assets.dart`

Responsibilities:

- scan `cli/assets/skills/**`
- read UTF-8 text files
- generate `cli/lib/src/assets/assets_generated.dart`
- support both normal mode and `--check`
- follow existing generator conventions used by `gen_models.dart` and `gen_version.dart`

The generated file should embed bundled assets directly into Dart source.

### Generated representation

Keep the representation small and text-focused.

Suggested types:

```dart
class BundledAssetFile {
  final String relativePath;
  final String content;
  final String sha256;
}

class BundledAssetBundle {
  final String id;
  final List<BundledAssetFile> files;
}
```

Generated constant example:

```dart
const BundledAssetBundle bundledSkillsBundle = BundledAssetBundle(
  id: 'skills',
  files: [...],
);
```

This is intentionally limited to text assets in v1.

## 3. Introduce a tiny runtime asset install/sync layer

Add a small runtime asset module:

- `cli/lib/src/assets/asset_bundle.dart`
- `cli/lib/src/assets/asset_installer.dart`

### `AssetInstaller` responsibilities

- ensure target directory exists
- write missing files
- overwrite changed files
- optionally prune stale files previously managed by the same bundle
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

`installAll()` should be small and explicit. For this iteration it installs only the bundled skills bundle.

## 4. Materialize built-in skills under `GLUE_HOME`

Built-in skills should be installed into a Glue-managed subtree under `Environment.skillsDir`.

Recommended target:

- `<GLUE_HOME>/skills/_builtin/<skill-name>/SKILL.md`

Not directly into:

- `<GLUE_HOME>/skills/<skill-name>/...`

### Why use `_builtin`

This keeps Glue-owned files separate from user-owned global skills.

Benefits:

- avoids accidental overwrite of user files
- makes ownership clear during upgrades
- allows Glue to re-sync built-ins freely
- preserves a clean override model: users override by placing a same-named skill in project/global locations

## 5. Simplify skill discovery to explicit paths only

Refactor skill runtime/discovery so bundled built-ins come from the managed runtime dir, not from executable-relative lookup.

After the refactor, skill discovery sources should be:

1. project-local: `<cwd>/.glue/skills`
2. configured extra paths: `skill_paths`
3. global user: `<GLUE_HOME>/skills`
4. built-in managed: `<GLUE_HOME>/skills/_builtin`

### Remove current bundled path heuristics

Delete or obsolete:

- `cli/lib/src/skills/skill_paths.dart`
- `GLUE_BUNDLED_SKILLS_DIR`
- `Platform.script`-derived bundle lookup
- repo-relative `skills/` or `cli/skills/` probing

The runtime should no longer try to locate its own source tree.

## 6. Add an explicit builtin skill source label

Today built-in skills discovered via `bundledPaths` are effectively labeled as `SkillSource.custom`.

Add a dedicated source variant:

```dart
enum SkillSource { project, global, custom, builtin }
```

This improves:

- `/skills` UI labeling
- tests
- internal clarity
- future observability/debugging

## 7. Install bundled assets before skill runtime initialization

In `ServiceLocator.create()`:

1. resolve environment
2. ensure Glue directories exist
3. install bundled assets into managed runtime dirs
4. initialize `SkillRuntime`
5. build prompt from discovered skills

This ensures built-in skills are present before discovery occurs.

## 8. Slightly expand `Environment.ensureDirectories()`

`Environment.ensureDirectories()` currently creates:

- `sessionsDir`
- `logsDir`
- `cacheDir`

Because built-in skills will now be materialized under `skillsDir`, this plan recommends also ensuring:

- `skillsDir`

The `_builtin` subdirectory itself can still be created by the installer.

## Sync Strategy

## Recommended v1 sync behavior

Use per-file content hashes plus a small manifest written into the managed target directory.

Example:

- `<GLUE_HOME>/skills/_builtin/.bundle-manifest.json`

Manifest contents:

- bundle id
- file list
- content hashes

### Installer behavior

For each bundle sync:

1. read manifest if present
2. compare expected files/hashes to current bundle
3. write changed or missing files
4. prune files previously managed by the bundle that no longer exist in the generated bundle
5. rewrite manifest

This gives deterministic upgrades while containing all mutation within the Glue-owned managed subtree.

### Why not skip the manifest entirely?

Comparing file contents directly would work for v1, but a manifest makes safe pruning easier when built-in skills are renamed or removed. That is worth the small complexity cost.

## API Simplicity Constraints

This plan intentionally keeps the asset API small.

### Allowed complexity

- one generated assets file
- one installer module
- one managed runtime target for skills
- one manifest per installed bundle

### Disallowed complexity for this iteration

- asset registries with dynamic plugin hooks
- bundle dependency graphs
- platform-target selection logic
- compression, archive extraction, or remote downloads
- generic executable-permission management

The design should feel like “embedded files synced to a target directory,” not a framework.

## Future Reuse

This plan intentionally leaves room for future bundled text assets without implementing them now.

Potential future uses:

1. **Markdown-backed slash commands**
   - e.g. `cli/assets/slash-commands/<name>.md`
   - materialized into a Glue-managed command asset dir

2. **Prompt templates or docs snippets**
   - stored in `cli/assets/templates/...`

3. **Small helper config files**
   - bundled defaults or examples

If future binary bundling is ever needed, the naming can remain compatible, but binary support itself stays out of scope for this iteration.

## Detailed Refactor Plan

## Phase 1 — Asset source + generator

1. Create `cli/assets/skills/`
2. Move existing built-in skills from `cli/skills/` to `cli/assets/skills/`
3. Add `cli/tool/gen_assets.dart`
4. Add generated file output: `cli/lib/src/assets/assets_generated.dart`
5. Update `cli/justfile`
   - include `gen_assets.dart` in `gen`
   - include `gen_assets.dart --check` in `gen-check`

### Acceptance criteria

- `just gen` regenerates assets successfully
- `just gen-check` fails when generated assets are stale
- generated asset file contains all built-in skills from `assets/skills`

## Phase 2 — Runtime asset install support

1. Add runtime asset types and installer
2. Add managed install target for built-in skills
3. Update `Environment.ensureDirectories()` to create `skillsDir`
4. Hook asset installation into `ServiceLocator.create()` before `SkillRuntime` init

### Acceptance criteria

- a fresh `GLUE_HOME` gets a populated built-in skills subtree on startup
- repeated startup is idempotent
- removed/renamed built-in skills are pruned from the managed subtree

## Phase 3 — Skill runtime/discovery simplification

1. Remove bundled path discovery heuristics from `SkillRuntime`
2. Remove `skill_paths.dart`
3. Remove `GLUE_BUNDLED_SKILLS_DIR`
4. Point bundled skill discovery at `<GLUE_HOME>/skills/_builtin`
5. Add `SkillSource.builtin`
6. Update skill discovery help text to reflect the new model

### Acceptance criteria

- no runtime code depends on `Platform.script` to find built-in skills
- no runtime code references `GLUE_BUNDLED_SKILLS_DIR`
- built-in skills are discovered from the managed Glue runtime dir only
- project/global/custom precedence still works

## Phase 4 — Tests and docs

1. Replace path-guessing tests with install/sync tests
2. Rewrite bundled skill tests to validate generated/install behavior rather than repo-relative lookup
3. Update docs/comments that refer to `cli/skills/`
4. Add/update plan and architecture docs where skill bundling/runtime locations are described

### Acceptance criteria

- tests cover generator output freshness
- tests cover startup install into managed builtin dir
- tests cover skill precedence with builtin/global/project collisions
- no docs mention `GLUE_BUNDLED_SKILLS_DIR`
- no docs describe repo-relative bundled skill discovery as the runtime model

## Files Likely Affected

### New files

- `cli/tool/gen_assets.dart`
- `cli/lib/src/assets/asset_bundle.dart`
- `cli/lib/src/assets/asset_installer.dart`
- `cli/lib/src/assets/assets_generated.dart`
- new tests under `cli/test/assets/`

### Moved / reorganized files

- `cli/skills/**` → `cli/assets/skills/**`

### Modified files

- `cli/justfile`
- `cli/lib/src/core/service_locator.dart`
- `cli/lib/src/core/environment.dart`
- `cli/lib/src/skills/skill_runtime.dart`
- `cli/lib/src/skills/skill_registry.dart`
- `cli/lib/src/skills/skill_parser.dart` (for `SkillSource.builtin`)
- docs/tests referencing current layout

### Removed files

- `cli/lib/src/skills/skill_paths.dart`
- `cli/test/skills/skill_paths_test.dart`

## Test Strategy

## Unit tests

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

## Regression tests

1. startup with empty `GLUE_HOME` still exposes built-in skills in prompt/tool list
2. `/skills` UI still sees bundled built-ins
3. `skill` tool still loads built-in skill bodies correctly
4. `just gen-check` fails if bundled assets generator output is stale

## Migration Notes

### Directory migration

The repo source directory for built-ins changes from:

- `cli/skills/`

to:

- `cli/assets/skills/`

### Runtime migration

Users do not need to copy any files manually. Built-ins are reinstalled by Glue into:

- `<GLUE_HOME>/skills/_builtin`

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
   - Recommendation: treat as non-fatal but visible. Glue should continue running, but diagnostics/logging should make the failure obvious.

4. **Should `global` discovery include `_builtin` implicitly or should builtin always be passed explicitly?**
   - Recommendation: keep builtin explicit. Do not make `SkillRegistry` infer managed builtin subdirectories automatically.

## Acceptance Criteria Summary

This plan is complete when:

1. built-in skills no longer depend on repo/executable-relative lookup
2. `GLUE_BUNDLED_SKILLS_DIR` is removed entirely
3. `cli/lib/src/skills/skill_paths.dart` is removed
4. built-in skills are authored under `cli/assets/skills`
5. generated embedded assets are produced by codegen and checked by `just gen-check`
6. startup materializes bundled built-ins into `<GLUE_HOME>/skills/_builtin`
7. skill discovery reads built-ins from the managed runtime dir only
8. user/project/custom precedence still overrides built-ins
9. the asset-bundling abstraction remains small and text-focused

## Recommended Implementation Notes

- Prefer `assets_generated.dart` over package-manager asset bundling assumptions, since Glue must work as a standalone compiled binary.
- Prefer explicit managed subtrees under `GLUE_HOME` over mixing Glue-owned and user-owned files in the same directory level.
- Keep the API intentionally small so future asset families can reuse it without forcing a framework onto the codebase.
- Do not add binary support until a concrete use case exists.
