# Slash Command Argument Autocomplete — Implementation Plan (v2)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
>
> v1 was reviewed via a 5-agent swarm and revised. Key changes: arg completers attach directly to `SlashCommand` at registration time in `App._initCommands()` (no new callbacks through `BuiltinCommands.create`); `/model` became a decision gate; activation semantics explicit; whitespace/mode-transition/alias tests added.

## Context

The first version of this plan landed `/open <target>` without autocomplete, proving that discoverability is weak: Glue's `SlashAutocomplete` dismisses on the first space, so the dropdown can't help the user remember `home|session|sessions|logs|skills|plans|cache`. The same gap bites `/provider add <id>`, `/model <ref>`, and `/skills <name>`.

**Goal:** After the user types `/<cmd> ` (space), the existing slash dropdown keeps working and filters the command's arguments instead of dismissing. Works for enumerable args (`/open`, `/provider`) and curated dynamic sets (`/skills`, optionally `/model`).

## Architecture

1. **Data model** (`cli/lib/src/commands/slash_commands.dart`): add `SlashArgCandidate` + `SlashArgCompleter` typedef, a nullable `completeArg` field on `SlashCommand`, `SlashCommandRegistry.attachArgCompleter(name, completer)`, `findByName(name)`.
2. **Overlay** (`cli/lib/src/ui/slash_autocomplete.dart`): two modes — _name_ (current) and _arg_ (new). Arg mode activates when the buffer is `/<knownCmd> <partial>` and the command has a `completeArg`. Splice-in-place on accept (mirrors `ShellAutocomplete` lines 100-114).
3. **Wire-up** (`cli/lib/src/app.dart` in `_initCommands()`): after `BuiltinCommands.create(...)` returns, call `_commands.attachArgCompleter(name, closure)` for each supported command. Closures capture `this` and read live state per keystroke.
4. **Per-command completers** live as small private methods on `App` (`_openArgCandidates`, `_providerArgCandidates`, etc.). No new callbacks on `BuiltinCommands.create`, no new impl functions in `command_helpers.dart`.

## Scope

- **In**: `/open` (static), `/provider` (2-level: subcommand then provider ID), `/skills` (simple list from registry).
- **Conditionally in**: `/model` — only if we also fix the matching semantics (see Task 5). If the fix is non-trivial, defer.
- **Out**: `/history`, `/resume`. Session IDs in a dropdown are user-hostile; their dedicated panels already solve discovery.

## Activation + acceptance semantics (explicit)

| Event                                | Name mode                                                          | Arg mode                                                                            |
| ------------------------------------ | ------------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| Buffer starts with `/`, no space yet | Active, filter by prefix                                           | n/a                                                                                 |
| User types space after known cmd     | Transition to arg mode (if completer exists)                       | Already here                                                                        |
| User backspaces past the space       | Back to name mode (revert candidates)                              | Transition                                                                          |
| Tab / Enter                          | Accept highlighted: replace buffer with `/<cmd> ` (trailing space) | Accept highlighted: splice in place; append trailing space if `candidate.continues` |
| Escape                               | Dismiss                                                            | Dismiss                                                                             |
| Typing                               | Re-filter live                                                     | Re-filter live                                                                      |

All modes require cursor at end of buffer (current constraint; out of scope to change). Activation uses **exact command-name match** after the leading `/`, but looks up completers through both `name` and `aliases` (so `/q <space>` still hits `/exit`'s completer if one exists).

---

## Task 1: Data model + registry helper

**Files**

- Modify: `cli/lib/src/commands/slash_commands.dart`
- Modify: `cli/test/slash_commands_test.dart` (exists — 133 lines)

**What to add**

```dart
class SlashArgCandidate {
  final String value;
  final String description;
  /// When true, accept appends a trailing space so the user can keep typing.
  final bool continues;
  const SlashArgCandidate({
    required this.value,
    this.description = '',
    this.continues = false,
  });
}

typedef SlashArgCompleter = List<SlashArgCandidate> Function(
  List<String> priorArgs,
  String partial,
);
```

- Add `SlashArgCompleter? completeArg` to `SlashCommand` (non-final, settable, default null — registry entries are setup-time objects, mutation is fine).
- Add `SlashCommandRegistry.attachArgCompleter(String name, SlashArgCompleter completer)` — resolves by `name`, `aliases`, or `hiddenAliases`; throws `StateError` if unknown.
- Add `SlashCommand? findByName(String name)` using the same resolution.

**Tests**

1. `attachArgCompleter` sets the completer on the target command (by primary name).
2. `attachArgCompleter` resolves through aliases and hidden aliases.
3. `attachArgCompleter` throws `StateError` on unknown name.
4. Default `SlashArgCandidate.continues == false`, `description == ''`.
5. A registered command with no completer still executes normally (backward compat).
6. `findByName` returns null on unknown name.

---

## Task 2: Dual-mode `SlashAutocomplete`

**Files**

- Modify: `cli/lib/src/ui/slash_autocomplete.dart`
- Modify: `cli/test/slash_autocomplete_test.dart` (exists — 175 lines, 15 tests)

**Design**

Replace the activation guard at `slash_autocomplete.dart:50-60`. New `update(buffer, cursor)`:

```
if empty, or not starts with '/', or cursor != buffer.length:
  dismiss(); return

// Predictable whitespace handling: require exactly-one-space separators.
if buffer.contains('\t') or buffer.contains('  '):
  dismiss(); return

parts = buffer.substring(1).split(' ')
cmdName = parts[0].toLowerCase()

if parts.length == 1:
  // Name mode (current behavior).
  filterRegistryByPrefix(cmdName)
  mode = _Mode.name
else:
  cmd = registry.findByName(cmdName)  // also resolves aliases
  if cmd == null || cmd.completeArg == null:
    dismiss(); return
  priorArgs = parts.sublist(1, parts.length - 1)
  partial = parts.last.toLowerCase()  // '' when buffer ends with ' '
  candidates = cmd.completeArg(priorArgs, partial)
  if candidates.isEmpty:
    dismiss(); return
  mode = _Mode.arg
```

**Splice in `accept()`**

```
if mode == _Mode.name:
  text = '/' + candidate.name + ' '   // trailing space — user keeps typing
  cursor = text.length
else (_Mode.arg):
  tokenStart = buffer.lastIndexOf(' ') + 1
  before = buffer.substring(0, tokenStart)
  suffix = candidate.continues ? ' ' : ''
  text = before + candidate.value + suffix
  cursor = text.length
```

Render unchanged — both modes produce a `List<_Candidate>` and feed the existing `render(width)`.

**Tests**

_Name-mode (existing, updated)_

1. Accepting `/he` → `/help ` (trailing space — adjust existing assertion).

_Arg-mode activation_ 2. `/open ` activates arg mode, lists all 7 targets. 3. `/open s` narrows to `session`, `sessions`, `skills`. 4. `/unknown ` dismisses (unregistered). 5. `/help ` dismisses (no completer). 6. Alias lookup: `/q home` resolves to `/exit`'s completer when one is attached.

_Splice semantics_ 7. Accept `session` from `/open s` yields `/open session`, cursor at end. 8. Accept candidate with `continues: true` appends trailing space. 9. Nested args: `/provider add ` → completer called with `priorArgs == ['add']`, `partial == ''`.

_Mode transitions_ 10. `/op` → type space → transitions to arg mode with `/open`'s targets visible. 11. From arg mode, backspace past the space → back to name mode with `/open` candidate.

_Whitespace edge cases_ 12. `/open  s` (double space) dismisses. 13. `/open\ts` (tab char) dismisses. 14. `/ ` (slash + space, no command) dismisses.

_Empty completer result_ 15. `/open zzzzz` dismisses.

---

## Task 3: `/open` completer (no app state)

**Files**

- Modify: `cli/lib/src/app.dart` — add `_openArgCandidates` + attach in `_initCommands`.
- Add: `cli/test/app_arg_completers_test.dart` (new; keeps `builtin_commands_test.dart` focused).

```dart
// in app.dart, near _buildPathsReport / _openGlueTarget
List<SlashArgCandidate> _openArgCandidates(List<String> prior, String partial) {
  if (prior.isNotEmpty) return const [];
  const targets = {
    'home': r'$GLUE_HOME',
    'session': 'current session folder',
    'sessions': 'all sessions',
    'logs': 'logs/',
    'skills': 'skills/',
    'plans': 'plans/',
    'cache': 'cache/',
  };
  return targets.entries
      .where((e) => e.key.startsWith(partial))
      .map((e) => SlashArgCandidate(value: e.key, description: e.value))
      .toList();
}

// in _initCommands, after BuiltinCommands.create(...):
_commands.attachArgCompleter('open', _openArgCandidates);
```

**Tests**

1. `/open ` → 7 targets with descriptions.
2. `/open s` → session, sessions, skills only.
3. `/open x` → empty.
4. Non-empty `priorArgs` → empty (`/open home extra` shouldn't complete).

---

## Task 4: `/provider` completer (catalog-dependent)

**Files**

- Modify: `cli/lib/src/app.dart` — add `_providerArgCandidates` + attach.
- Extend: `cli/test/app_arg_completers_test.dart`.

```dart
List<SlashArgCandidate> _providerArgCandidates(
    List<String> prior, String partial) {
  const subs = {
    'list': 'Open provider panel',
    'add': 'Authenticate a provider',
    'remove': 'Forget stored credentials',
    'test': 'Validate a provider',
  };
  if (prior.isEmpty) {
    return subs.entries
        .where((e) => e.key.startsWith(partial))
        .map((e) => SlashArgCandidate(
              value: e.key,
              description: e.value,
              continues: e.key != 'list',
            ))
        .toList();
  }
  if (prior.length == 1 && {'add', 'remove', 'test'}.contains(prior[0])) {
    final config = _config;
    if (config == null) return const [];
    return config.catalogData.providers.values
        .where((p) => p.id.toLowerCase().startsWith(partial))
        .map((p) => SlashArgCandidate(value: p.id, description: p.name))
        .toList();
  }
  return const [];
}
```

**Tests**

1. `/provider ` → 4 subcommands; `list` has `continues: false`, others `continues: true`.
2. `/provider add <empty>` with a test config → all provider IDs with display names.
3. `/provider add ant` → narrowed by prefix.
4. `/provider add ` with `_config == null` → empty (doesn't crash).
5. `/provider list foo` → empty (terminal subcommand takes no further arg).

---

## Task 5: `/model` — decision point

The swarm flagged `/model` as the weakest candidate:

- Catalog size (Ollama + OpenAI + Anthropic + OpenRouter): 100-500+ refs.
- Users type `sonnet`, not `anthropic/claude-sonnet-4-7`; prefix-match on the composite ref misses the way they think.
- The command itself uses `_findCatalogRow` (fuzzy/substring) — completer being prefix-only would suggest a strictly narrower set than what executes.

**Decision gate**: pick one before writing Task 5.

### Option 5a — Ship with three fixes

- Match segments independently: `p.id.startsWith(partial) || m.id.contains(partial) || m.name.contains(partial) || ref.contains(partial)`.
- `partial.length >= 1` before populating — `/model ` empty partial returns nothing (avoid flood).
- Cap results at 20 for headroom over `maxVisibleDropdownItems`.

```dart
List<SlashArgCandidate> _modelArgCandidates(List<String> prior, String partial) {
  if (prior.isNotEmpty) return const [];
  if (partial.isEmpty) return const [];
  final config = _config;
  if (config == null) return const [];
  final needle = partial.toLowerCase();
  final out = <SlashArgCandidate>[];
  for (final p in config.catalogData.providers.values) {
    for (final m in p.models.values) {
      final ref = '${p.id}/${m.id}';
      final matches = p.id.toLowerCase().startsWith(needle) ||
          m.id.toLowerCase().contains(needle) ||
          m.name.toLowerCase().contains(needle) ||
          ref.toLowerCase().contains(needle);
      if (matches) out.add(SlashArgCandidate(value: ref, description: m.name));
      if (out.length >= 20) return out;
    }
  }
  return out;
}
```

**Tests (5a)**

1. `/model ` empty partial → empty list (min-chars gate).
2. `/model son` → finds `anthropic/claude-sonnet-*` via model-segment match.
3. `/model ant` → provider prefix match.
4. `/model ` with `_config == null` → empty.
5. Result cap at 20 (stub a 100-model catalog).

### Option 5b — Defer

Leave `/model` free-form. Users type IDs; the existing `/models` panel remains the discovery surface. Revisit in a follow-up PR.

**Recommendation:** 5a if the fixes land under an hour; otherwise 5b.

### `/skills` — always ship

```dart
List<SlashArgCandidate> _skillArgCandidates(List<String> prior, String partial) {
  if (prior.isNotEmpty) return const [];
  final needle = partial.toLowerCase();
  return _skillRuntime.registry.all
      .where((s) => s.meta.name.toLowerCase().startsWith(needle))
      .map((s) => SlashArgCandidate(
            value: s.meta.name,
            description: s.meta.description,
          ))
      .toList();
}
```

_(Adapt to the actual `SkillRegistry` API at implementation time — verify `.all`, `.meta` accessors.)_

**Tests**

1. `/skills ` with 3 registered skills → 3 candidates.
2. `/skills code` → narrowed by prefix.
3. Empty registry → empty list.

---

## Task 6: Integration test (keystroke narrative)

**Files**

- Add: `cli/test/ui/slash_autocomplete_integration_test.dart`

Drive `SlashAutocomplete` against a minimal registry plus real completers (via `attachArgCompleter`):

```
type '/' → name mode, all commands
type 'o' → filters to /open (+ anything else starting with 'o')
type 'p' → single candidate /open
type ' ' → transition to arg mode, 7 targets
type 's' → narrows to session/sessions/skills
Tab → buffer becomes '/open session'
```

One focused test per transition. Also assert: Escape dismisses from both modes; backspace across space flips mode correctly; Tab on a bare `/open session` (no overlay, user typed full command) does nothing destructive.

---

## Files touched summary

| File                                                   | Change                                                                                          |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| `cli/lib/src/commands/slash_commands.dart`             | Add `SlashArgCandidate`, `SlashArgCompleter`, `completeArg`, `attachArgCompleter`, `findByName` |
| `cli/lib/src/ui/slash_autocomplete.dart`               | Dual-mode `update()`, splice-aware `accept()`, whitespace guards                                |
| `cli/lib/src/app.dart`                                 | 3-4 small candidate-producer methods + `attachArgCompleter` calls in `_initCommands`            |
| `cli/lib/glue.dart`                                    | Export new types from `slash_commands.dart`                                                     |
| `cli/test/slash_commands_test.dart`                    | Registry + attach tests                                                                         |
| `cli/test/slash_autocomplete_test.dart`                | Activation, splice, mode transitions, whitespace, aliases                                       |
| `cli/test/app_arg_completers_test.dart`                | New — per-command completer behavior                                                            |
| `cli/test/ui/slash_autocomplete_integration_test.dart` | New — keystroke-narrative integration                                                           |

**NOT touched** (deliberately, vs v1):

- `cli/lib/src/commands/builtin_commands.dart` — no new callback parameters.
- `cli/lib/src/app/command_helpers.dart` — no new `_Impl` functions.

## Verification

After each task:

```sh
dart format --set-exit-if-changed .
dart analyze --fatal-infos
dart test test/slash_commands_test.dart test/slash_autocomplete_test.dart \
  test/app_arg_completers_test.dart
```

After final task:

```sh
dart test            # docker_executor_test pre-existing failure OK
```

Manual smoke (`dart run bin/glue.dart`):

- `/open ` → dropdown lists 7 targets.
- `/open s` + Tab → buffer becomes `/open session`.
- `/provider ` → 4 subcommands; accept `add` → trailing space + provider list.
- `/model sonnet` (if 5a) → Claude Sonnet refs surface.
- `/skills ` → registered skills.

## Risks / notes

- **Backwards compat on name-mode accept**: name-mode accept now appends a trailing space. Update existing `/he → /help` assertion.
- **Activation on typing vs Tab**: typing activates, Tab accepts (matches current name-mode behavior). Tab in idle state (no overlay) does nothing — Tab only mutates when a dropdown is visible. Assert this explicitly for a bare `/open session`.
- **Alias completer lookup**: `attachArgCompleter('exit', fn)` makes `/q <space>` use the completer. Test explicitly.
- **Stale `_config`**: completers read `_config` per-keystroke; during startup it may be null and return empty. Tests cover that.
- **No collision with `ShellAutocomplete`**: it only activates in bash mode (`_bashMode`). Slash commands don't enter bash mode. The pre-mortem's collision concern is moot for listed commands — add a code comment next to the overlay so future maintainers don't re-introduce it.
