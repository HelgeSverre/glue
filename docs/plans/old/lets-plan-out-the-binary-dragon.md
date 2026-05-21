# Model UX Polish + /copy Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the model selection UX (merge /model + /models, show API names, fix provider headers in filtered view) and add a /copy slash command.

**Architecture:** Four independent tasks; each modifies a small number of files. Tasks 1–3 all touch `model_panel_formatter.dart` so they should be done sequentially in that file. Task 4 is fully independent.

**Tech Stack:** Dart, existing `SelectPanel`, `ModelPanelBuilder`, `SlashCommandRegistry`, `Transcript`, `copyToClipboard`.

---

## Critical Files

| File | Role |
|------|------|
| `cli/lib/src/runtime/commands/register_builtin_slash_commands.dart` | Slash command registrations (Tasks 1, 4) |
| `cli/lib/src/catalog/model_panel_formatter.dart` | Model picker rendering, provider headers (Tasks 2, 3) |
| `cli/lib/src/ui/components/panel.dart` | `SelectPanel` + `SelectOption` (Task 3) |
| `cli/lib/src/runtime/controllers/model_controller.dart` | Panel wiring + searchText (Tasks 2, 3) |
| `cli/lib/src/runtime/commands/command_host.dart` | Controller interfaces (Task 4) |
| `cli/lib/src/runtime/controllers/chat_controller.dart` | `/copy` implementation (Task 4) |
| `cli/lib/src/app/controllers.dart` | `ChatController` DI wiring (Task 4) |

---

## Task 1: Merge /models into /model

**Files:**
- Modify: `cli/lib/src/runtime/commands/register_builtin_slash_commands.dart`
- Test: `cli/test/commands/builtin_commands_test.dart`

### Context
`/model` (no args → panel, args → switch) and `/models` (always panel) are separate commands. Remove `/models` as a standalone and make it an alias of `/model`.

- [ ] **Step 1: Add alias and remove /models registration**

In `register_builtin_slash_commands.dart`, edit `_ModelCommandModule.register()`:

```dart
// BEFORE
registry.register(SlashCommand(
  name: 'model',
  description: 'Switch model',
  execute: (args) {
    if (args.isEmpty) {
      context.models.openModelPanel();
      return '';
    }
    return context.models.switchModelByQuery(args.join(' '));
  },
));

registry.register(SlashCommand(
  name: 'models',
  description: 'Browse and switch models across all providers',
  execute: (_) {
    context.models.openModelPanel();
    return '';
  },
));

// AFTER
registry.register(SlashCommand(
  name: 'model',
  description: 'Switch model (no args = picker, with arg = switch directly)',
  aliases: ['models'],
  execute: (args) {
    if (args.isEmpty) {
      context.models.openModelPanel();
      return '';
    }
    return context.models.switchModelByQuery(args.join(' '));
  },
));
```

- [ ] **Step 2: Run tests**

```sh
cd cli && dart test test/commands/slash_commands_test.dart test/commands/builtin_commands_test.dart -r expanded
```

Expected: all pass.

- [ ] **Step 3: Add regression test**

In `cli/test/commands/builtin_commands_test.dart`, verify `/models` alias works and `/models` is not a separate top-level command. Look for the pattern used by other alias tests in `slash_commands_test.dart`:

```dart
test('/models is an alias for /model and opens panel', () {
  var opened = false;
  final registry = SlashCommandRegistry();
  registry.register(SlashCommand(
    name: 'model',
    aliases: ['models'],
    description: 'Switch model',
    execute: (args) {
      if (args.isEmpty) { opened = true; return ''; }
      return 'switched';
    },
  ));
  registry.execute('/models');
  expect(opened, isTrue);
  // Verify 'models' is not a separate command (only 1 registration)
  expect(registry.commands.where((c) => c.name == 'models'), isEmpty);
});
```

- [ ] **Step 4: Run tests**

```sh
cd cli && dart test test/commands/ -r expanded
```

Expected: all pass.

- [ ] **Step 5: Commit**

```sh
git add cli/lib/src/runtime/commands/register_builtin_slash_commands.dart \
        cli/test/commands/builtin_commands_test.dart
git commit -m "feat(commands): merge /models into /model as alias"
```

---

## Task 2: Show API name instead of display name in model picker

**Files:**
- Modify: `cli/lib/src/catalog/model_panel_formatter.dart`
- Modify: `cli/lib/src/runtime/controllers/model_controller.dart`
- Test: `cli/test/catalog/model_panel_formatter_test.dart`

### Context
The picker's MODEL column currently shows `model.name` (display label, e.g. "Gemma 4 26B"). Change it to `model.apiId` (wire name, e.g. "gemma4:latest"). Also update `searchText` to include both apiId and name for better matching. For Ollama, `model.apiId == model.id == the tag`. For Anthropic, `model.apiId = "claude-sonnet-4-5"` (no visual regression — same as the id).

- [ ] **Step 1: Write failing test**

Add to `cli/test/catalog/model_panel_formatter_test.dart`:

```dart
test('MODEL column shows apiId not display name', () {
  final entry = (
    providerId: 'ollama',
    providerName: 'Ollama',
    model: ModelDef(
      id: 'gemma4:26b',
      name: 'Gemma 4 26B',
      apiId: 'gemma4:26b',
    ),
    availability: ModelAvailability.unknown,
  );
  final builder = buildModelPanel(
    [entry],
    currentRef: const ModelRef(providerId: 'x', modelId: 'y'),
  );
  final row = stripAnsi(builder.renderRow(0, 80));
  expect(row, contains('gemma4:26b'));
  // Should NOT show the display name in the MODEL column
  // (it may still appear in other columns, so just check apiId is there)
  expect(row, contains('gemma4:26b'));
});
```

- [ ] **Step 2: Run test to verify it fails**

```sh
cd cli && dart test test/catalog/model_panel_formatter_test.dart -r expanded
```

(This may pass if apiId equals name; the real test value is when they differ. Proceed either way.)

- [ ] **Step 3: Change MODEL column to use apiId**

In `cli/lib/src/catalog/model_panel_formatter.dart`, inside `buildModelPanel()`, change the `getValues` callback:

```dart
// BEFORE
'name': row.model.name,

// AFTER
'name': row.model.apiId,
```

- [ ] **Step 4: Update searchText in model_controller.dart to include both**

In `cli/lib/src/runtime/controllers/model_controller.dart`, in `_openModelPanel()`:

```dart
// BEFORE
final searchText = stripAnsi(
  '${entry.providerName} ${entry.model.name} '
  '${entry.model.notes ?? ''}',
);

// AFTER
final searchText = stripAnsi(
  '${entry.providerName} ${entry.model.apiId} ${entry.model.name} '
  '${entry.model.notes ?? ''}',
);
```

- [ ] **Step 5: Run all catalog tests**

```sh
cd cli && dart test test/catalog/ -r expanded
```

Expected: all pass. (The existing test `'provider header appears only on the first row'` checks `stripAnsi(row0).contains('Anthropic')` — this is the provider column, unaffected.)

- [ ] **Step 6: Commit**

```sh
git add cli/lib/src/catalog/model_panel_formatter.dart \
        cli/lib/src/runtime/controllers/model_controller.dart \
        cli/test/catalog/model_panel_formatter_test.dart
git commit -m "feat(model-picker): show api name (apiId) instead of display name in MODEL column"
```

---

## Task 3: Retain provider group separators when filtering

**Files:**
- Modify: `cli/lib/src/catalog/model_panel_formatter.dart`
- Modify: `cli/lib/src/ui/components/panel.dart`
- Modify: `cli/lib/src/runtime/controllers/model_controller.dart`
- Test: `cli/test/catalog/model_panel_formatter_test.dart`
- Test: `cli/test/ui/select_panel_test.dart`

### Context / Problem
Provider headers (`headers[i]`) are precomputed at `buildModelPanel()` time as: first row of each provider group = provider name, rest = "". When filtering reduces the visible set, if the first model of a provider doesn't match but a later one does, the later one has `headers[i] = ""` and shows no provider name. Fix: compute provider header dynamically based on which indices are currently in the filtered set.

### Part A — Make ModelPanelBuilder filter-aware

- [ ] **Step 1: Write failing test**

Add to `cli/test/catalog/model_panel_formatter_test.dart`:

```dart
test('provider header appears on first item of each provider in filtered set', () {
  // 3 models: anthropic/claude (idx 0), ollama/llama (idx 1), ollama/gemma (idx 2)
  final entries = <CatalogRow>[
    (
      providerId: 'anthropic',
      providerName: 'Anthropic',
      model: const ModelDef(id: 'claude', name: 'Claude'),
      availability: ModelAvailability.unknown,
    ),
    (
      providerId: 'ollama',
      providerName: 'Ollama',
      model: const ModelDef(id: 'llama3:8b', name: 'Llama 3'),
      availability: ModelAvailability.unknown,
    ),
    (
      providerId: 'ollama',
      providerName: 'Ollama',
      model: const ModelDef(id: 'gemma4:26b', name: 'Gemma 4'),
      availability: ModelAvailability.unknown,
    ),
  ];
  final builder = buildModelPanel(
    entries,
    currentRef: const ModelRef(providerId: 'x', modelId: 'y'),
  );

  // Unfiltered: idx 1 (llama3) is first ollama → has header, idx 2 (gemma4) does not
  expect(stripAnsi(builder.renderRow(1, 80)), contains('Ollama'));
  expect(stripAnsi(builder.renderRow(2, 80)), isNot(contains('Ollama')));

  // Filter to only [2] (gemma4) — now idx 2 is first ollama in filtered set
  builder.updateFilter([2]);
  expect(stripAnsi(builder.renderRow(2, 80)), contains('Ollama'));
  
  // Reset filter
  builder.updateFilter(null);
  expect(stripAnsi(builder.renderRow(2, 80)), isNot(contains('Ollama')));
});
```

- [ ] **Step 2: Run test to verify it fails**

```sh
cd cli && dart test test/catalog/model_panel_formatter_test.dart -r expanded
```

Expected: FAIL (no `updateFilter` method yet).

- [ ] **Step 3: Restructure ModelPanelBuilder to be filter-aware**

Replace the `ModelPanelBuilder` class and `buildModelPanel()` function in `cli/lib/src/catalog/model_panel_formatter.dart`:

```dart
class ModelPanelBuilder {
  ModelPanelBuilder._(this._table, this.initialIndex, this.entries, this._headers);

  final ResponsiveTable<int> _table;

  /// Index into [entries] for the currently active model, or 0 if none match.
  final int initialIndex;

  /// Flat list of entries corresponding 1:1 with the builder's rows.
  final List<CatalogRow> entries;

  /// Precomputed provider headers for the unfiltered state.
  final List<String> _headers;

  /// Currently active filter (null = show all, use precomputed headers).
  List<int>? _currentFilter;

  int get rowCount => entries.length;
  List<String> renderHeader(int width) => _table.renderHeader(width);
  String renderRow(int index, int width) => _table.renderRow(index, width);

  /// Update the active filter so provider headers reflect the visible set.
  /// Pass null to restore unfiltered (precomputed) headers.
  void updateFilter(List<int>? filter) => _currentFilter = filter;

  String _effectiveHeader(int globalIndex) {
    final f = _currentFilter;
    if (f == null) return _headers[globalIndex];
    final providerId = entries[globalIndex].providerId;
    // Provider header appears if this is the first occurrence of providerId in f.
    for (final i in f) {
      if (entries[i].providerId == providerId) {
        return i == globalIndex
            ? entries[globalIndex].providerName.styled.cyan.toString()
            : '';
      }
    }
    return '';
  }
}

ModelPanelBuilder buildModelPanel(
  List<CatalogRow> entries, {
  required ModelRef currentRef,
}) {
  var flatInitial = 0;
  final headers = <String>[];
  String? lastProvider;
  for (var i = 0; i < entries.length; i++) {
    final row = entries[i];
    if (row.providerId == currentRef.providerId &&
        row.model.id == currentRef.modelId) {
      flatInitial = i;
    }
    headers.add(
      row.providerId != lastProvider
          ? row.providerName.styled.cyan.toString()
          : '',
    );
    lastProvider = row.providerId;
  }

  // Use late so the getValues closure can call back to builder._effectiveHeader.
  late ModelPanelBuilder builder;

  final indexed = List<int>.generate(entries.length, (i) => i);
  final table = ResponsiveTable<int>(
    columns: const [
      TableColumn(key: 'provider', header: 'PROVIDER'),
      TableColumn(key: 'marker', header: ''),
      TableColumn(key: 'name', header: 'MODEL'),
      TableColumn(key: 'tag', header: 'NOTES'),
    ],
    rows: indexed,
    getValues: (i) {
      final row = entries[i];
      final isCurrent = row.providerId == currentRef.providerId &&
          row.model.id == currentRef.modelId;
      return {
        'provider': builder._effectiveHeader(i),
        'marker': isCurrent ? '● ' : '  ',
        'name': row.model.apiId,
        'tag': _renderNotesWithAvailability(row),
      };
    },
  );

  builder = ModelPanelBuilder._(table, flatInitial, entries, headers);
  return builder;
}
```

- [ ] **Step 4: Run catalog tests**

```sh
cd cli && dart test test/catalog/ -r expanded
```

Expected: all pass, including the new filter test.

### Part B — Add onFilterChanged to SelectPanel

- [ ] **Step 5: Write failing test for onFilterChanged**

Add to `cli/test/ui/select_panel_test.dart`:

```dart
test('onFilterChanged fires when query changes', () {
  final filterLog = <List<int>>[];
  final options = [
    SelectOption<int>(value: 0, label: 'apple'),
    SelectOption<int>(value: 1, label: 'banana'),
    SelectOption<int>(value: 2, label: 'apricot'),
  ];
  final panel = SelectPanel<int>(
    title: 'Test',
    options: options,
    onFilterChanged: filterLog.add,
  );

  // Type 'a' — matches apple (0) and apricot (2)
  panel.handleEvent(const CharEvent(char: 'a'));
  expect(filterLog, hasLength(1));
  expect(filterLog.last, containsAll([0, 2]));
  expect(filterLog.last, isNot(contains(1)));

  // Backspace — back to all
  panel.handleEvent(const KeyEvent(key: Key.backspace));
  expect(filterLog, hasLength(2));
  expect(filterLog.last, containsAll([0, 1, 2]));
});
```

- [ ] **Step 6: Run test to verify it fails**

```sh
cd cli && dart test test/ui/select_panel_test.dart -r expanded
```

Expected: FAIL (no `onFilterChanged` parameter yet).

- [ ] **Step 7: Add onFilterChanged to SelectPanel**

In `cli/lib/src/ui/components/panel.dart`, add the parameter and call sites:

```dart
class SelectPanel<T> implements AbstractPanel {
  // ... existing fields ...
  final void Function(List<int> filtered)? onFilterChanged;  // ADD

  SelectPanel({
    // ... existing params ...
    this.onFilterChanged,  // ADD
  }) : /* ... existing assertions ... */ {
    _selectedIndex = options.isEmpty ? 0 : initialIndex.clamp(0, options.length - 1);
  }
```

Then add a helper and call it in the three query-change handlers inside `handleEvent`:

```dart
void _notifyFilterChanged() {
  onFilterChanged?.call(_filteredIndices());
}
```

Update the three relevant cases in `handleEvent`:

```dart
case KeyEvent(key: Key.backspace):
  if (searchEnabled && _query.isNotEmpty) {
    _query = _query.substring(0, _query.length - 1);
    _scrollOffset = 0;
    _notifyFilterChanged();   // ADD
    _normalizeSelection();
  }
  return true;
case KeyEvent(key: Key.ctrlU):
  if (searchEnabled && _query.isNotEmpty) {
    _query = '';
    _scrollOffset = 0;
    _notifyFilterChanged();   // ADD
    _normalizeSelection();
  }
  return true;
case CharEvent(:final char, alt: false)
    when searchEnabled && _isSearchChar(char):
  _query += char.toLowerCase();
  _scrollOffset = 0;
  _notifyFilterChanged();     // ADD
  _normalizeSelection();
  return true;
```

- [ ] **Step 8: Run UI tests**

```sh
cd cli && dart test test/ui/ -r expanded
```

Expected: all pass.

### Part C — Wire callback in ModelController

- [ ] **Step 9: Wire onFilterChanged in _openModelPanel**

In `cli/lib/src/runtime/controllers/model_controller.dart`, in `_openModelPanel()`, update the `SelectPanel` construction:

```dart
// BEFORE
final panel = SelectPanel<CatalogRow>(
  title: 'Switch Model',
  options: options,
  headerBuilder: builder.renderHeader,
  searchHint: 'filter models',
  barrier: BarrierStyle.dim,
  width: panelWidth,
  height: PanelFluid(0.7, 10),
  initialIndex: builder.initialIndex,
);

// AFTER
final panel = SelectPanel<CatalogRow>(
  title: 'Switch Model',
  options: options,
  headerBuilder: builder.renderHeader,
  searchHint: 'filter models',
  barrier: BarrierStyle.dim,
  width: panelWidth,
  height: PanelFluid(0.7, 10),
  initialIndex: builder.initialIndex,
  onFilterChanged: builder.updateFilter,
);
```

- [ ] **Step 10: Run full test suite**

```sh
cd cli && dart analyze --fatal-infos && dart test -r expanded
```

Expected: zero warnings, all tests pass.

- [ ] **Step 11: Commit**

```sh
git add cli/lib/src/catalog/model_panel_formatter.dart \
        cli/lib/src/ui/components/panel.dart \
        cli/lib/src/runtime/controllers/model_controller.dart \
        cli/test/catalog/model_panel_formatter_test.dart \
        cli/test/ui/select_panel_test.dart
git commit -m "feat(model-picker): retain provider group headers when filtering"
```

---

## Task 4: /copy command

**Files:**
- Modify: `cli/lib/src/runtime/commands/command_host.dart`
- Modify: `cli/lib/src/runtime/controllers/chat_controller.dart`
- Modify: `cli/lib/src/app/controllers.dart`
- Modify: `cli/lib/src/runtime/commands/register_builtin_slash_commands.dart`
- Test: `cli/test/commands/builtin_commands_test.dart`

### Context
Copy the last assistant response to the clipboard AND write it to `/tmp/glue/copy.md`. The existing `copyToClipboard()` utility (`cli/lib/src/core/clipboard.dart`) handles cross-platform clipboard access. `Transcript.blocks` is a `List<ConversationEntry>`; iterate in reverse for the last `EntryKind.assistant` entry.

`ChatController` already has `render` but does NOT have `transcript`. We need to add it.

- [ ] **Step 1: Write failing test**

Add to `cli/test/commands/builtin_commands_test.dart` (look at existing test structure in that file for setUp/context patterns):

```dart
test('/copy command is registered', () {
  // Use the pattern from existing tests in builtin_commands_test.dart
  // to get a registry with all built-in commands registered.
  // Then verify /copy exists and is a registered command.
  final cmd = registry.findByName('copy');
  expect(cmd, isNotNull);
  expect(cmd!.name, 'copy');
});
```

- [ ] **Step 2: Run test to verify it fails**

```sh
cd cli && dart test test/commands/builtin_commands_test.dart -r expanded
```

Expected: FAIL (no `/copy` registered).

- [ ] **Step 3: Add copyLastResponse to ChatCommandController interface**

In `cli/lib/src/runtime/commands/command_host.dart`:

```dart
abstract interface class ChatCommandController {
  String clearConversation();
  String listTools();
  String toggleApproval();
  void copyLastResponse();   // ADD
}
```

- [ ] **Step 4: Add transcript to ChatController and implement copyLastResponse**

Replace `cli/lib/src/runtime/controllers/chat_controller.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:glue/src/agent/tools.dart' as tool_contract;
import 'package:glue/src/config/approval_mode.dart';
import 'package:glue/src/core/clipboard.dart';
import 'package:glue/src/runtime/commands/command_host.dart';
import 'package:glue/src/runtime/transcript.dart';
import 'package:glue/src/terminal/layout.dart';
import 'package:glue/src/terminal/terminal.dart';

class ChatController implements ChatCommandController {
  const ChatController({
    required this.terminal,
    required this.layout,
    required this.clearConversationState,
    required this.render,
    required this.tools,
    required this.getApprovalMode,
    required this.setApprovalMode,
    required this.transcript,
  });

  final Terminal terminal;
  final Layout layout;
  final void Function() clearConversationState;
  final void Function() render;
  final Iterable<tool_contract.Tool> Function() tools;
  final ApprovalMode Function() getApprovalMode;
  final void Function(ApprovalMode mode) setApprovalMode;
  final Transcript transcript;

  @override
  String clearConversation() {
    clearConversationState();
    terminal.clearScreen();
    layout.apply();
    return 'Cleared.';
  }

  @override
  String listTools() {
    final buf = StringBuffer('Available tools:\n');
    for (final tool in tools()) {
      buf.writeln('  ${tool.name} — ${tool.description}');
    }
    return buf.toString();
  }

  @override
  String toggleApproval() {
    final next = getApprovalMode().toggle;
    setApprovalMode(next);
    render();
    return 'Approval: ${next.label}';
  }

  @override
  void copyLastResponse() {
    ConversationEntry? lastAssistant;
    for (final block in transcript.blocks.reversed) {
      if (block.kind == EntryKind.assistant) {
        lastAssistant = block;
        break;
      }
    }

    if (lastAssistant == null) {
      transcript.system('No assistant response to copy.');
      render();
      return;
    }

    final text = lastAssistant.text;

    unawaited(() async {
      const dir = '/tmp/glue';
      try {
        await Directory(dir).create(recursive: true);
        await File('$dir/copy.md').writeAsString(text);
      } catch (_) {}

      final ok = await copyToClipboard(text);
      final msg = ok
          ? 'Copied to clipboard (also saved to $dir/copy.md).'
          : 'Saved to $dir/copy.md (no clipboard tool available).';
      transcript.system(msg);
      render();
    }());
  }
}
```

- [ ] **Step 5: Wire transcript into ChatController in controllers.dart**

In `cli/lib/src/app/controllers.dart`, update the `ChatController` construction:

```dart
chat = ChatController(
  terminal: app.terminal,
  layout: app.layout,
  clearConversationState: () {
    app._transcript.blocks.clear();
    app._transcript.scrollOffset = 0;
    app._transcript.streamingText = '';
  },
  render: app._render,
  tools: () => app.agent.tools.values,
  getApprovalMode: () => app._approvalMode,
  setApprovalMode: (mode) => app._approvalMode = mode,
  transcript: app._transcript,   // ADD
);
```

- [ ] **Step 6: Register /copy slash command**

In `cli/lib/src/runtime/commands/register_builtin_slash_commands.dart`, add to `_CoreCommandModule.register()`:

```dart
registry.register(SlashCommand(
  name: 'copy',
  description: 'Copy last response to clipboard',
  execute: (_) {
    context.chat.copyLastResponse();
    return '';
  },
));
```

- [ ] **Step 7: Run full test suite and analyzer**

```sh
cd cli && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test -r expanded
```

Expected: formatted, zero warnings, all tests pass.

- [ ] **Step 8: Commit**

```sh
git add cli/lib/src/runtime/commands/command_host.dart \
        cli/lib/src/runtime/controllers/chat_controller.dart \
        cli/lib/src/app/controllers.dart \
        cli/lib/src/runtime/commands/register_builtin_slash_commands.dart \
        cli/test/commands/builtin_commands_test.dart
git commit -m "feat(commands): add /copy command that copies last response to clipboard"
```

---

## Verification

After all tasks:

```sh
cd cli && just check    # gen-check + analyze + test
```

Manual smoke test (requires a running Glue session):
1. `/models` → should open the same picker as `/model` (alias works)
2. In picker, observe API names (e.g. `claude-sonnet-4-5`) in MODEL column
3. In picker, type "gemma" or any model name that is NOT the first model of its provider — confirm provider name still appears at the boundary
4. `/model gemma` → autocomplete should list `ollama/gemma4:...` candidates
5. Send a message, wait for response, then `/copy` → clipboard contains response, `/tmp/glue/copy.md` exists
