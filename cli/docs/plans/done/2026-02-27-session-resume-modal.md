# Session Resume Modal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Upgrade `/resume` from a text list to a selectable PanelModal, and add `--resume`/`--continue` CLI flags.

**Architecture:** Extend `PanelModal` with an optional `selectable` mode that tracks a `selectedIndex`, highlights the selected row with inverse video, and completes a `Future<int?>` on Enter/Escape. The `/resume` command opens this panel (same pattern as `/help`). CLI flags plumb startup actions into `App.run()`.

**Tech Stack:** Dart 3.4+, `package:test`, `package:args`

---

### Task 1: Add selection mode to PanelModal — tests

**Files:**

- Modify: `test/ui/panel_modal_test.dart`

**Step 1: Write failing tests for selectable PanelModal**

Add a new `group('PanelModal selectable', ...)` after the existing `group('PanelModal', ...)` block at the end of the file:

```dart
group('PanelModal selectable', () {
  late PanelModal panel;

  setUp(() {
    panel = PanelModal(
      title: 'SELECT',
      lines: List.generate(20, (i) => 'Item $i'),
      style: PanelStyle.simple,
      barrier: BarrierStyle.dim,
      width: PanelFixed(40),
      height: PanelFixed(10),
      selectable: true,
    );
  });

  test('initial selectedIndex is 0', () {
    expect(panel.selectedIndex, 0);
  });

  test('down moves selection forward', () {
    panel.handleEvent(KeyEvent(Key.down));
    expect(panel.selectedIndex, 1);
  });

  test('up at top stays at 0', () {
    panel.handleEvent(KeyEvent(Key.up));
    expect(panel.selectedIndex, 0);
  });

  test('selection clamps to last item', () {
    for (var i = 0; i < 50; i++) {
      panel.handleEvent(KeyEvent(Key.down));
    }
    expect(panel.selectedIndex, 19);
  });

  test('enter completes selection with index', () async {
    panel.handleEvent(KeyEvent(Key.down));
    panel.handleEvent(KeyEvent(Key.down));
    panel.handleEvent(KeyEvent(Key.enter));
    expect(panel.isComplete, true);
    expect(await panel.selection, 2);
  });

  test('escape completes selection with null', () async {
    panel.handleEvent(KeyEvent(Key.down));
    panel.handleEvent(KeyEvent(Key.escape));
    expect(panel.isComplete, true);
    expect(await panel.selection, null);
  });

  test('selection auto-scrolls when moving past visible area', () {
    // visible height = 10 - 2 = 8
    for (var i = 0; i < 9; i++) {
      panel.handleEvent(KeyEvent(Key.down));
    }
    expect(panel.selectedIndex, 9);
    expect(panel.scrollOffset, greaterThan(0));
  });

  test('render highlights selected row with inverse video', () {
    final bg = List.generate(24, (i) => '');
    final rendered = panel.render(80, 24, bg);
    final allText = rendered.join();
    // Inverse video escape code should be present
    expect(allText, contains('\x1b[7m'));
  });

  test('non-selectable panel has no selection future', () async {
    final plain = PanelModal(
      title: 'PLAIN',
      lines: ['a', 'b'],
      style: PanelStyle.simple,
      barrier: BarrierStyle.dim,
    );
    expect(await plain.selection, null);
  });

  test('selectedIndex is -1 for non-selectable panel', () {
    final plain = PanelModal(
      title: 'PLAIN',
      lines: ['a', 'b'],
      style: PanelStyle.simple,
      barrier: BarrierStyle.dim,
    );
    expect(plain.selectedIndex, -1);
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `dart test test/ui/panel_modal_test.dart`
Expected: FAIL — `selectable` parameter doesn't exist, `selectedIndex` and `selection` getters don't exist.

---

### Task 2: Add selection mode to PanelModal — implementation

**Files:**

- Modify: `lib/src/ui/panel_modal.dart`

**Step 1: Add selectable fields to PanelModal**

Add these fields and constructor changes to `PanelModal`:

```dart
class PanelModal {
  final String title;
  final List<String> lines;
  final PanelStyle style;
  final BarrierStyle barrier;
  final PanelSize _width;
  final PanelSize _height;
  final bool dismissable;
  final bool selectable;

  int _scrollOffset = 0;
  int _selectedIndex = 0;
  final Completer<void> _completer = Completer<void>();
  final Completer<int?> _selectionCompleter = Completer<int?>();
  int _lastVisibleHeight = 0;
```

Update constructor to accept `selectable`:

```dart
PanelModal({
  required this.title,
  required this.lines,
  this.style = PanelStyle.tape,
  this.barrier = BarrierStyle.dim,
  PanelSize? width,
  PanelSize? height,
  this.dismissable = true,
  this.selectable = false,
})  : _width = width ?? PanelFluid(0.7, 40),
      _height = height ?? PanelFluid(0.7, 10) {
  if (_height case PanelFixed(:final size)) {
    _lastVisibleHeight = size - 2;
  }
}
```

Add getters:

```dart
int get selectedIndex => selectable ? _selectedIndex : -1;
Future<int?> get selection =>
    selectable ? _selectionCompleter.future : Future.value(null);
```

**Step 2: Update dismiss to complete selection**

```dart
void dismiss() {
  if (!_completer.isCompleted) _completer.complete();
  if (selectable && !_selectionCompleter.isCompleted) {
    _selectionCompleter.complete(null);
  }
}
```

**Step 3: Update handleEvent for selection mode**

Replace the `handleEvent` method body with logic that branches on `selectable`:

```dart
bool handleEvent(TerminalEvent event) {
  if (isComplete) return false;

  final visibleH = max<int>(_lastVisibleHeight, 1);
  final maxScroll = max<int>(0, lines.length - visibleH);

  switch (event) {
    case KeyEvent(key: Key.escape):
      if (dismissable) dismiss();
      return true;
    case KeyEvent(key: Key.enter):
      if (selectable) {
        if (!_selectionCompleter.isCompleted) {
          _selectionCompleter.complete(_selectedIndex);
        }
        if (!_completer.isCompleted) _completer.complete();
      }
      return true;
    case KeyEvent(key: Key.up):
      if (selectable) {
        _selectedIndex = max<int>(0, _selectedIndex - 1);
        if (_selectedIndex < _scrollOffset) {
          _scrollOffset = _selectedIndex;
        }
      } else {
        _scrollOffset = max<int>(0, _scrollOffset - 1);
      }
      return true;
    case KeyEvent(key: Key.down):
      if (selectable) {
        _selectedIndex = min<int>(lines.length - 1, _selectedIndex + 1);
        if (_selectedIndex >= _scrollOffset + visibleH) {
          _scrollOffset = _selectedIndex - visibleH + 1;
        }
      } else {
        _scrollOffset = min<int>(maxScroll, _scrollOffset + 1);
      }
      return true;
    case KeyEvent(key: Key.pageUp):
      if (selectable) {
        _selectedIndex = max<int>(0, _selectedIndex - visibleH);
        _scrollOffset = max<int>(0, _scrollOffset - visibleH);
      } else {
        _scrollOffset = max<int>(0, _scrollOffset - visibleH);
      }
      return true;
    case KeyEvent(key: Key.pageDown):
      if (selectable) {
        _selectedIndex = min<int>(lines.length - 1, _selectedIndex + visibleH);
        _scrollOffset = min<int>(maxScroll, _scrollOffset + visibleH);
      } else {
        _scrollOffset = min<int>(maxScroll, _scrollOffset + visibleH);
      }
      return true;
    default:
      return true;
  }
}
```

**Step 4: Update render to highlight selected row**

In the `render` method, in the content row rendering section (the `else` branch at approx line 247), add inverse video when `selectable` and the row is selected. Change the padded line to:

```dart
// Inside the else block where contentIdx < visibleLines.length
final contentIdx = r - 1;
final raw = contentIdx < visibleLines.length ? visibleLines[contentIdx] : '';
final truncated = ansiTruncate(raw, contentW);
final padLen = contentW - visibleLength(truncated);
final padded = '$truncated${' ' * max(0, padLen)}';

final isSelected = selectable &&
    (contentIdx + _scrollOffset) == _selectedIndex;
final styledContent = isSelected
    ? '\x1b[7m$padded\x1b[27m'
    : padded;
```

Then use `styledContent` instead of `padded` in the line assembly:

```dart
panelLines.add('$leftBorder $styledContent $rightBorder');
```

**Step 5: Run tests**

Run: `dart test test/ui/panel_modal_test.dart`
Expected: ALL PASS

**Step 6: Run analyze**

Run: `dart analyze`
Expected: No issues found

**Step 7: Commit**

```bash
git add lib/src/ui/panel_modal.dart test/ui/panel_modal_test.dart
git commit -m "feat: add selectable mode to PanelModal"
```

---

### Task 3: Wire /resume command to open selection panel

**Files:**

- Modify: `lib/src/app.dart`

**Step 1: Add \_openResumePanel method to App**

Add this method after `_openHelpPanel()` (around line 511):

```dart
void _openResumePanel() {
  final home = GlueHome();
  final sessions = SessionStore.listSessions(home.sessionsDir);
  if (sessions.isEmpty) {
    _blocks.add(_ConversationEntry.system('No saved sessions found.'));
    _render();
    return;
  }

  final displayLines = <String>[];
  for (final s in sessions) {
    final ago = _timeAgo(s.startTime);
    final shortCwd = _shortenPath(s.cwd);
    final id = s.id.length > 8 ? s.id.substring(0, 8) : s.id;
    displayLines.add('$id…  ${s.model}  $shortCwd  $ago');
  }

  final panel = PanelModal(
    title: 'Resume Session',
    lines: displayLines,
    style: PanelStyle.tape,
    barrier: BarrierStyle.dim,
    height: PanelFluid(0.5, 10),
    selectable: true,
  );
  _activePanel = panel;
  _render();

  panel.selection.then((idx) {
    _activePanel = null;
    if (idx == null) {
      _render();
      return;
    }
    final result = _resumeSession(sessions[idx]);
    if (result.isNotEmpty) {
      _blocks.add(_ConversationEntry.system(result));
    }
    _render();
  });
}
```

**Step 2: Update /resume slash command registration**

Replace the existing `/resume` command registration in `_initCommands()` with:

```dart
_commands.register(SlashCommand(
  name: 'resume',
  description: 'Resume a previous session',
  execute: (args) {
    _openResumePanel();
    return '';
  },
));
```

**Step 3: Run analyze**

Run: `dart analyze`
Expected: No issues found

**Step 4: Commit**

```bash
git add lib/src/app.dart
git commit -m "feat: /resume opens selectable session panel"
```

---

### Task 4: Add --resume and --continue CLI flags

**Files:**

- Modify: `bin/glue.dart`
- Modify: `lib/src/app.dart`

**Step 1: Add startup action fields to App**

Add two fields to `App` and update the constructor:

In the field declarations (around line 122), add:

```dart
final bool _startupResume;
final bool _startupContinue;
```

Update the `App` constructor parameter list to add:

```dart
bool startupResume = false,
bool startupContinue = false,
```

And in the initializer list:

```dart
_startupResume = startupResume,
_startupContinue = startupContinue,
```

**Step 2: Add startup action handling in App.run()**

In `App.run()`, after the initial `_render();` call (around line 257), add:

```dart
if (_startupResume) {
  _openResumePanel();
} else if (_startupContinue) {
  final home = GlueHome();
  final sessions = SessionStore.listSessions(home.sessionsDir);
  if (sessions.isNotEmpty) {
    final result = _resumeSession(sessions.first);
    if (result.isNotEmpty) {
      _blocks.add(_ConversationEntry.system(result));
    }
    _render();
  } else {
    _blocks.add(_ConversationEntry.system('No sessions to continue.'));
    _render();
  }
}
```

**Step 3: Update App.create() to accept startup flags**

Add parameters to `App.create()`:

```dart
factory App.create({String? provider, String? model, bool startupResume = false, bool startupContinue = false}) {
```

And pass them through in the `return App(...)` call:

```dart
return App(
  ...existing params...,
  startupResume: startupResume,
  startupContinue: startupContinue,
);
```

**Step 4: Add CLI flags to bin/glue.dart**

Add these flags to the `ArgParser`:

```dart
..addFlag('resume', negatable: false, help: 'Start with session picker open.')
..addFlag('continue', negatable: false, help: 'Resume most recent session.')
```

Update the `App.create` call:

```dart
final app = App.create(
  provider: provider,
  model: model,
  startupResume: results.flag('resume'),
  startupContinue: results.flag('continue'),
);
```

**Step 5: Run analyze**

Run: `dart analyze`
Expected: No issues found

**Step 6: Commit**

```bash
git add bin/glue.dart lib/src/app.dart
git commit -m "feat: add --resume and --continue CLI flags"
```

---

### Task 5: Update barrel export

**Files:**

- Check: `lib/glue.dart`

**Step 1: Verify exports**

The `PanelModal` export in `lib/glue.dart` already exists on line 22. No changes needed since we only added optional parameters, no new public classes.

**Step 2: Run full test suite**

Run: `dart test`
Expected: ALL PASS

**Step 3: Final analyze**

Run: `dart analyze`
Expected: No issues found
