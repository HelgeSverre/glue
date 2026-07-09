# Catalog Refactor — `dart_mappable` for Model Serialization

**Date:** 2026-05-21
**Owner:** Helge
**Status:** ✅ landed 2026-05-25

> Note: the landed implementation follows the repo's current committed
> `.mapper.dart` + `gen-check` conventions. Where this plan says
> `--delete-conflicting-outputs`, the current implementation uses plain
> `dart run build_runner build` because that flag is now removed/ignored.

## Context

`cli/tool/gen_models.dart` (165 LOC) hand-rolls a Dart source emitter for the
model catalog. It reads `docs/reference/models.yaml`, parses it via
`parseCatalogYaml`, then re-walks the result with `_str` / `_renderAuth` /
`_renderStringMap` helpers to emit a `const ModelCatalog(...)` literal at
`packages/glue_harness/lib/src/catalog/models_generated.dart`.

This duplicates field knowledge that already exists on the model classes
themselves. Adding a field to `ModelDef` requires editing both the class and
the emitter; the latter is silent if forgotten. The model types
(`ModelCatalog`, `ProviderDef`, `ModelDef`, `AuthSpec`, `DefaultsConfig`) have
no `toJson` / `fromJson` / `==` / `copyWith` — they bypass any benefit a
serialization library would give us.

A broader survey of the codebase identified two more serialization-heavy
surfaces with similar pain (`packages/glue_server/lib/src/acp/messages.dart`,
`packages/glue_harness/lib/src/storage/session_store.dart`). Those become
viable targets *after* the catalog refactor proves the pattern.

Investigated and rejected alternatives:
- **Dart build hooks / `data_assets`** — flag is `channels: [main, dev]` only,
  never shipped stable; `dart compile exe` errors out when any non-dev dep has
  a build hook ([dart-lang/sdk#62593](https://github.com/dart-lang/sdk/issues/62593));
  assets land *beside* the binary, not in the AOT snapshot. Not viable for
  Glue's self-contained-binary release model.
- **`built_value`** — verbose `Built<X, XBuilder>` ceremony; worse fit than
  `dart_mappable` for plain immutable data.
- **`json_serializable` + `checked_yaml`** — viable but no `copyWith` / `==`
  for free; we'd add codegen ceremony and still hand-write equality.
- **`yaml_writer` / `yaml_edit`** — wrong layer; `yaml_edit` already used
  elsewhere and stays.

## Decisions (locked)

1. Adopt `dart_mappable` on the five catalog types.
2. Relax the "`glue_core` is dependency-free" invariant for this one
   well-justified case — annotation runtime is small (depends only on
   `collection` + `meta`).
3. Drop the `const ModelCatalog` literal. Embed the catalog as a const JSON
   string and parse once at startup (~5ms for ~80KB; no `const` consumers
   downstream — verified by grep).
4. Keep `parseCatalogYaml` as-is. Its source-pathed errors and the
   `auth: {api_key: env:NAME}` polymorphism are runtime concerns codegen can't
   express cleanly; trading them for ~50 LOC saved is a net loss.
5. Leave the three small embedders alone (`gen_share_assets.dart`,
   `gen_modal_sidecar.dart`, `gen_version.dart`). They work, are stable, embed
   non-model files, and don't share `gen_models.dart`'s architectural problem.

## Work

### 1. Annotate catalog types

File: `packages/glue_core/lib/src/model_catalog.dart`

```dart
@MappableLib(caseStyle: CaseStyle.snakeCase)
library;

import 'package:dart_mappable/dart_mappable.dart';

part 'model_catalog.mapper.dart';

@MappableEnum(caseStyle: CaseStyle.snakeCase)
enum AuthKind { apiKey, oauth, none }

@MappableClass()
class ModelCatalog with ModelCatalogMappable { ... }

@MappableClass()
class DefaultsConfig with DefaultsConfigMappable { ... }

@MappableClass()
class AuthSpec with AuthSpecMappable { ... }

@MappableClass()
class ProviderDef with ProviderDefMappable { ... }

@MappableClass()
class ModelDef with ModelDefMappable { ... }
```

Library-level `snakeCase` covers `updated_at`, `small_model`, `local_model`,
`base_url`, `docs_url`, `request_headers`, `api_id`, `context_window`,
`max_output_tokens`. One per-field override needed:

```dart
@MappableField(key: 'default')
final bool isDefault;
```

`Capability` (the string-constant namespace) stays untouched — not a data
class.

`ModelDef.apiId`'s `apiId = apiId ?? id` default-from-id survives decoding
(mapper invokes the constructor verbatim); encoding always emits `api_id`,
which is fine since the bundled JSON is generated, not human-edited.

### 2. Pubspec changes

`packages/glue_core/pubspec.yaml`:
```yaml
dependencies:
  dart_mappable: ^4.5.0  # confirm latest at write time
dev_dependencies:
  dart_mappable_builder: ^4.5.0
  build_runner: ^2.4.13
```

Update the "deliberately dependency-free" comment to note the exception.

No changes needed to `glue_harness/pubspec.yaml` or `cli/pubspec.yaml` —
`dart_mappable` flows through transitively; codegen runs in `glue_core`.

### 3. Rewrite `cli/tool/gen_models.dart`

Shrinks from 165 LOC to ~30. Same `--check` UX, same `dart format`, same
output path. Replace the body of `_render` with:

```dart
String _render(ModelCatalog c) {
  final json = const JsonEncoder.withIndent('  ').convert(c.toMap());
  assert(!json.contains("'''"), 'JSON contains triple-quote sequence');
  return '''
// GENERATED — DO NOT EDIT.
// Source: docs/reference/models.yaml
// Regenerate with: dart run tool/gen_models.dart
// ignore_for_file: lines_longer_than_80_chars

import 'package:glue_core/glue_core.dart';

const String _bundledCatalogJson = r\'\'\'
$json
\'\'\';

final ModelCatalog bundledCatalog =
    ModelCatalogMapper.fromJson(_bundledCatalogJson);
''';
}
```

Delete `_renderAuth`, `_renderStringMap`, `_renderStringSet`, `_str`,
`_strOrNull`. `_dartFormat` stays.

### 4. Wire up build_runner

`packages/glue_core/justfile`: add `gen` / `gen-check` recipes that run
`dart run build_runner build --delete-conflicting-outputs` and a
`git diff --exit-code lib/src/model_catalog.mapper.dart` check respectively.

`cli/justfile`: `just gen` must run `glue_core::gen` *before*
`dart run tool/gen_models.dart`, since the generator imports the mapper.
Same ordering for `gen-check`.

Root `justfile`: existing `just check` already fans out per-package — verify
the new `glue_core::gen-check` is wired into `glue_core::check`.

Commit `*.mapper.dart` files. They're deterministic, reviewable, and CI gets
them for free without running `build_runner` in every step. `.gitignore`
needs no change.

### 5. Update tests

`cli/test/catalog/gen_models_smoke_test.dart` continues to validate
`bundledCatalog` against `parseCatalogYaml(file)` — round-trip now goes
through JSON instead of literal-construction. No code changes expected;
re-run to confirm.

## Files touched

- `packages/glue_core/lib/src/model_catalog.dart` — add annotations + `part`
- `packages/glue_core/lib/src/model_catalog.mapper.dart` — **new, generated**
- `packages/glue_core/pubspec.yaml` — add deps
- `packages/glue_core/justfile` — gen recipes
- `packages/glue_harness/lib/src/catalog/models_generated.dart` — new shape
- `cli/tool/gen_models.dart` — rewrite to ~30 LOC
- `cli/justfile` — ordering for `gen` / `gen-check`

## Verification

```bash
# 1. glue_core builds its mapper files
cd packages/glue_core && dart pub get && \
  dart run build_runner build --delete-conflicting-outputs
dart analyze

# 2. cli regenerates the bundled catalog
cd ../../cli && dart pub get && just gen

# 3. Smoke tests pass
dart test test/catalog/
dart test test/app/model_display_test.dart
dart test test/integration/model_flag_resolution_test.dart

# 4. Full quality gate
cd .. && just check

# 5. AOT binary still builds (catches const-vs-final regressions)
cd cli && just build && ../dist/glue --version

# 6. Drift detection
just gen-check  # passes after step 2
```

## Risks

- **Mapper-file drift in PRs**: `gen-check` enforces no diff between committed
  `.mapper.dart` and a fresh `build_runner` run. Reviewers should re-run
  locally if the diff looks surprising.
- **`AuthKind` snake_case**: `apiKey → api_key`, `oauth → oauth`, `none → none`
  matches what `parseCatalogYaml` produces today. Round-trip safe.
- **`Set<String>` capabilities**: `dart_mappable` handles `Set<String>`
  natively (JSON array → `Set` via constructor coercion). Verify in the
  smoke test.
- **`dart compile exe` interaction**: build_runner is dev-only; the AOT path
  doesn't see it. Confirmed safe by [data_assets research][hooks-research]
  (build hooks would break AOT; codegen via `build_runner` does not).

[hooks-research]: see conversation 2026-05-21 — `dart compile exe` rejects
build hooks, but `build_runner`-emitted Dart source is just regular Dart code.

## Follow-up opportunities (out of scope; documented for sequencing)

Once the pattern is proven on the catalog, the next highest-ROI targets:

### Tier 1 — ACP message hierarchy
- `packages/glue_server/lib/src/acp/messages.dart` (~401 LOC, 20+
  toJson/fromJson pairs)
- `packages/glue_server/lib/src/acp/content.dart` (~205 LOC, sealed
  `AcpContentBlock` with 5+ subclasses)
- Sealed-class polymorphism is exactly where `dart_mappable`'s discriminator
  support shines. External contract (ACP spec) locks field names — handled
  via `@MappableField(key: ...)`.
- Estimated ~250 LOC removed.

### Tier 2 — Session persistence
- `packages/glue_harness/lib/src/storage/session_store.dart` (`SessionMeta`,
  25+ fields, schema v1-v2 migration logic)
- ~80 LOC removed; requires careful round-trip tests across schema versions
  before merging.

### Tier 3 — Smaller wins
- Selected MCP protocol types in
  `packages/glue_strategies/lib/src/mcp_client/protocol.dart` (~20 LOC; skip
  the polymorphic/pass-through cases)
- `MountEntry` in `packages/glue_strategies/lib/src/shell/docker_config.dart`
  (~10 LOC)

### Skip
- `UsageStats` / `UsageReport` — mutable fields conflict with codegen
  immutability assumption; refactor cost outweighs the ~30 LOC saved.
- `CredentialRef` — sealed class with no serialization; current `==` /
  `hashCode` are fine.
- `RuntimeDiffMeta` — 10 LOC, not worth a codegen dep.

Each follow-up tier should be its own PR with its own plan doc. This plan
covers only the catalog.
