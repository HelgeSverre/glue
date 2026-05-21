# Plan: `sortBy` extension + `tools.dart` cleanup

## Context

`cli/lib/src/commands/slash/tools.dart` is the only file in `cli/lib/src/commands/slash/` that uses a `StringBuffer` + `writeln` loop to produce its output — siblings either use UI panels or collection-literal `.join('\n')`. It also carries the most common shape of `.sort()` boilerplate in the codebase: `(a, b) => a.X.compareTo(b.X)`.

A repo-wide audit (12 `.sort()` call sites in `cli/`) found:

- **4 simple "sort by field"** sites: `tools.dart:19` and `tool/generate_website_api.dart:682, 703, 739`.
- **0 reverse-sort** sites.
- **8 complex** sites (default `..sort()`, multi-key, or score-based) — these stay untouched.
- **No existing helper.** `package:collection` is not in `cli/pubspec.yaml`. No `extension … on List/Iterable` exists anywhere in `cli/lib/`.

User intent: introduce a small `sortBy((e) => e.field)` extension and reshape `tools.dart` into the same listing idiom as its siblings. Scope kept tight — only patterns that actually exist today.

## Changes

### 1. New file: `packages/glue_harness/lib/src/extensions/list.dart`

The repo already has an extensions folder at `packages/glue_harness/lib/src/extensions/` (currently holds `units.dart`). New extensions go here and are re-exported from the package barrel — matches the established pattern. `cli` already depends on `glue_harness` via path, so consumers just `import 'package:glue_harness/glue_harness.dart';`.

Single extension on `List<E>`, one method, matching the in-place `..sort()` idiom. No `Iterable.sortedBy`, no `sortByDesc` — neither has a current call site. Add either when a real second site appears.

```dart
extension ListSortBy<E> on List<E> {
  /// Sorts in place by [key] in ascending natural order.
  /// Mirrors the `..sort()` cascade idiom; mutates and returns void.
  void sortBy<K extends Comparable<K>>(K Function(E) key) {
    sort((a, b) => key(a).compareTo(key(b)));
  }
}
```

### 1b. Export from package barrel

Add to `packages/glue_harness/lib/glue_harness.dart`, alongside the existing `units.dart` export (line 42):

```dart
export 'package:glue_harness/src/extensions/list.dart';
```

### 2. Apply to call sites (4)

**`cli/lib/src/commands/slash/tools.dart`** — full rewrite of `execute`, also dropping the `StringBuffer`:

```dart
import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue_harness/glue_harness.dart';

/// `/tools` — list registered tools and their descriptions.
class ToolsCommand extends SlashCommand {
  ToolsCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'tools';

  @override
  String get description => 'List available tools';

  @override
  String execute(List<String> args) {
    final tools = ctx.agent.tools.values.toList()..sortBy((t) => t.name);
    return [
      'Registered tools (${tools.length}):',
      for (final t in tools) '  ${t.name} — ${t.description}',
    ].join('\n');
  }
}
```

**`cli/tool/generate_website_api.dart`** — three sites at lines 682, 703, 739:

- `..sort((a, b) => a.stem.compareTo(b.stem))` → `..sortBy((e) => e.stem)`
- Add `import 'package:glue_harness/glue_harness.dart';` at top of file (if not already present).

### Out of scope

- The 8 complex `.sort()` sites (`at_file_hint.dart`, `gen_models.dart`, `check_layers.dart`, `glue_theme_demo.dart`). Default-comparator `..sort()` is already minimal; multi-key comparators don't fit a single-key `sortBy`.
- `sortByDesc` / `Iterable.sortedBy` — add on demand.
- Adding `package:collection` — not justified for one extension method.

## Critical files

- `packages/glue_harness/lib/src/extensions/list.dart` (new)
- `packages/glue_harness/lib/glue_harness.dart` (add export, near existing `units.dart` export at line 42)
- `cli/lib/src/commands/slash/tools.dart` (rewrite `execute`, swap imports)
- `cli/tool/generate_website_api.dart` (3 sort sites + import)

## Verification

From `cli/`:

```sh
dart format .
dart analyze --fatal-infos          # zero warnings policy
dart test test/commands/            # slash command tests
just check                          # gen-check + analyze + test
```

End-to-end smoke:

```sh
dart run bin/glue.dart
# inside the TUI: type `/tools` and confirm output is identical
# (header line "Registered tools (N):" followed by sorted "  name — description" rows)
```

Sanity grep after edits — should show one helper definition and four usages, no leftover `compareTo` boilerplate at the migrated sites:

```sh
rg -n 'sortBy\(' cli/
rg -n '\.compareTo\(' cli/lib/src/commands/slash/ cli/tool/generate_website_api.dart
```
