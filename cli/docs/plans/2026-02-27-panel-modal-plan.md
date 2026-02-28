# Panel Modal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a reusable, scrollable, centered floating panel modal with construction-branded styling, and wire `/help` to use it.

**Architecture:** New `PanelModal` class in `lib/src/ui/panel_modal.dart` with `PanelStyle`, `BarrierStyle`, and `PanelSize` enums/sealed classes. Renders a full-screen grid with barrier effect + centered panel. Integrated into `App` via `_activePanel` field, same event-routing pattern as `ConfirmModal`. `/help` command opens a panel instead of returning text.

**Tech Stack:** Dart 3.4+, ANSI escape codes, box-drawing/unicode characters

---

## Task 1: `PanelSize` sealed class

**Files:**

- Create: `lib/src/ui/panel_modal.dart`
- Create: `test/ui/panel_modal_test.dart`

**Step 1: Write failing tests**

Create `test/ui/panel_modal_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/ui/panel_modal.dart';

void main() {
  group('PanelSize', () {
    group('PanelFixed', () {
      test('resolve returns exact size', () {
        final size = PanelFixed(40);
        expect(size.resolve(100), 40);
      });

      test('resolve clamps to available', () {
        final size = PanelFixed(200);
        expect(size.resolve(80), 80);
      });
    });

    group('PanelFluid', () {
      test('resolve uses percentage of available', () {
        final size = PanelFluid(0.7, 10);
        expect(size.resolve(100), 70);
      });

      test('resolve respects minimum', () {
        final size = PanelFluid(0.7, 40);
        expect(size.resolve(30), 40);
      });

      test('resolve clamps to available when min exceeds it', () {
        // When min > available, clamp to available
        final size = PanelFluid(0.7, 200);
        expect(size.resolve(80), 80);
      });
    });
  });
}
```

**Step 2: Run tests to verify they fail**

Run: `dart test test/ui/panel_modal_test.dart`
Expected: FAIL — file doesn't exist / classes not defined

**Step 3: Implement `PanelSize`**

Create `lib/src/ui/panel_modal.dart`:

```dart
import 'dart:async';
import 'dart:math' as math;
import '../terminal/terminal.dart';
import '../rendering/ansi_utils.dart';

// ---------------------------------------------------------------------------
// Enums and sizing
// ---------------------------------------------------------------------------

/// Visual style for the panel border.
enum PanelStyle { tape, simple, heavy }

/// Background treatment behind the panel.
enum BarrierStyle { dim, obscure, none }

/// Panel dimension specification.
sealed class PanelSize {
  const PanelSize();

  /// Resolve to an actual size given [available] space.
  int resolve(int available);
}

/// Fixed size in columns or rows.
class PanelFixed extends PanelSize {
  final int size;
  const PanelFixed(this.size);

  @override
  int resolve(int available) => math.min(size, available);
}

/// Fluid size as a percentage of available space with a minimum.
class PanelFluid extends PanelSize {
  final double maxPercent;
  final int minSize;
  const PanelFluid(this.maxPercent, this.minSize);

  @override
  int resolve(int available) {
    final target = (available * maxPercent).floor();
    return math.min(math.max(target, minSize), available);
  }
}
```

**Step 4: Run tests**

Run: `dart test test/ui/panel_modal_test.dart`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/src/ui/panel_modal.dart test/ui/panel_modal_test.dart
git commit -m "feat: add PanelSize sealed class for panel modal dimensions"
```

---

## Task 2: Border rendering for all three `PanelStyle` variants

**Files:**

- Modify: `lib/src/ui/panel_modal.dart`
- Modify: `test/ui/panel_modal_test.dart`

**Step 1: Write failing tests**

Add to `test/ui/panel_modal_test.dart`:

```dart
  group('renderBorder', () {
    test('simple style produces correct dimensions', () {
      final lines = renderBorder(PanelStyle.simple, 30, 5, 'TEST');
      expect(lines.length, 5);
      for (final line in lines) {
        expect(visibleLength(line), 30);
      }
    });

    test('simple style has title in top border', () {
      final lines = renderBorder(PanelStyle.simple, 30, 5, 'HELP');
      final top = stripAnsi(lines.first);
      expect(top, contains('HELP'));
      expect(top, startsWith('┌'));
      expect(top, endsWith('┐'));
    });

    test('simple style has bottom border', () {
      final bottom = stripAnsi(renderBorder(PanelStyle.simple, 30, 5, 'X').last);
      expect(bottom, startsWith('└'));
      expect(bottom, endsWith('┘'));
    });

    test('heavy style uses double-line characters', () {
      final lines = renderBorder(PanelStyle.heavy, 30, 5, 'HELP');
      final top = stripAnsi(lines.first);
      expect(top, startsWith('╔'));
      expect(top, endsWith('╗'));
      final bottom = stripAnsi(lines.last);
      expect(bottom, startsWith('╚'));
      expect(bottom, endsWith('╝'));
    });

    test('tape style uses alternating tape characters', () {
      final lines = renderBorder(PanelStyle.tape, 30, 5, 'HELP');
      final top = stripAnsi(lines.first);
      expect(top, contains('▚'));
      expect(top, contains('HELP'));
    });

    test('all styles produce same dimensions', () {
      for (final style in PanelStyle.values) {
        final lines = renderBorder(style, 40, 8, 'TITLE');
        expect(lines.length, 8, reason: '$style height');
        for (final line in lines) {
          expect(visibleLength(line), 40, reason: '$style width');
        }
      }
    });

    test('interior lines have 1-char padding', () {
      final lines = renderBorder(PanelStyle.simple, 20, 5, 'X');
      // Interior lines (index 1-3) should have border + space + content area + space + border
      final interior = stripAnsi(lines[1]);
      expect(interior[0], '│');
      expect(interior[1], ' ');
      expect(interior[interior.length - 2], ' ');
      expect(interior[interior.length - 1], '│');
    });
  });
```

Add `import 'package:glue/src/rendering/ansi_utils.dart';` to the test imports.

**Step 2: Run tests to verify they fail**

Run: `dart test test/ui/panel_modal_test.dart`
Expected: FAIL — `renderBorder` not defined

**Step 3: Implement `renderBorder`**

Add to `lib/src/ui/panel_modal.dart`:

```dart
// ---------------------------------------------------------------------------
// Border rendering
// ---------------------------------------------------------------------------

/// Render a panel border frame with the given [style], [width], [height],
/// and [title]. Returns [height] lines, each exactly [width] visible
/// characters wide (with ANSI escapes for color).
///
/// Interior lines are filled with spaces and have 1-char padding inside
/// the border on each side.
List<String> renderBorder(PanelStyle style, int width, int height, String title) {
  return switch (style) {
    PanelStyle.simple => _renderSimple(width, height, title),
    PanelStyle.heavy => _renderHeavy(width, height, title),
    PanelStyle.tape => _renderTape(width, height, title),
  };
}

List<String> _renderSimple(int w, int h, String title) {
  const borderColor = '\x1b[90m'; // dim gray
  const titleColor = '\x1b[33m'; // yellow
  const rst = '\x1b[0m';

  final lines = <String>[];

  // Top: ┌─ TITLE ──...──┐
  final titlePart = ' $title ';
  final dashesAfter = w - 2 - titlePart.length - 1; // -2 for corners, -1 for dash before title
  final top = '$borderColor┌─$rst$titleColor$titlePart$rst'
      '$borderColor${'─' * dashesAfter.clamp(0, w)}┐$rst';
  lines.add(top);

  // Interior: │ <spaces> │
  final innerWidth = w - 2; // minus left and right border
  final interiorLine = '$borderColor│$rst${' ' * innerWidth}$borderColor│$rst';
  for (var i = 1; i < h - 1; i++) {
    lines.add(interiorLine);
  }

  // Bottom: └──...──┘
  final bottom = '$borderColor└${'─' * (w - 2)}┘$rst';
  lines.add(bottom);

  return lines;
}

List<String> _renderHeavy(int w, int h, String title) {
  const borderColor = '\x1b[33m'; // yellow
  const rst = '\x1b[0m';

  final lines = <String>[];

  // Top: ╔═ TITLE ══...══╗
  final titlePart = ' $title ';
  final equalsAfter = w - 2 - titlePart.length - 1;
  final top = '$borderColor╔═$titlePart${'═' * equalsAfter.clamp(0, w)}╗$rst';
  lines.add(top);

  // Interior: ║ <spaces> ║
  final innerWidth = w - 2;
  final interiorLine = '$borderColor║$rst${' ' * innerWidth}$borderColor║$rst';
  for (var i = 1; i < h - 1; i++) {
    lines.add(interiorLine);
  }

  // Bottom: ╚══...══╝
  final bottom = '$borderColor╚${'═' * (w - 2)}╝$rst';
  lines.add(bottom);

  return lines;
}

List<String> _renderTape(int w, int h, String title) {
  const tapeColor = '\x1b[33m'; // yellow
  const titleBg = '\x1b[43m\x1b[30m'; // yellow bg, black text
  const rst = '\x1b[0m';

  final lines = <String>[];

  // Top: ▚▞▚▞ TITLE ▚▞▚▞▚▞
  final titlePart = '$titleBg $title $rst';
  final titleVisible = title.length + 2; // space + title + space
  final tapeCharsNeeded = w - titleVisible;
  final tapeBefore = tapeCharsNeeded ~/ 2;
  final tapeAfter = tapeCharsNeeded - tapeBefore;
  final tapeStr = _tapeString(tapeBefore);
  final tapeStrAfter = _tapeString(tapeAfter);
  final top = '$tapeColor$tapeStr$rst$titlePart$tapeColor$tapeStrAfter$rst';
  lines.add(top);

  // Interior: │ <spaces> │
  final innerWidth = w - 2;
  final interiorLine = '$tapeColor│$rst${' ' * innerWidth}$tapeColor│$rst';
  for (var i = 1; i < h - 1; i++) {
    lines.add(interiorLine);
  }

  // Bottom: ▚▞▚▞▚▞▚▞▚▞▚▞
  final bottomTape = _tapeString(w);
  final bottom = '$tapeColor$bottomTape$rst';
  lines.add(bottom);

  return lines;
}

String _tapeString(int length) {
  final buf = StringBuffer();
  for (var i = 0; i < length; i++) {
    buf.write(i.isEven ? '▚' : '▞');
  }
  return buf.toString();
}
```

**Step 4: Run tests**

Run: `dart test test/ui/panel_modal_test.dart`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/src/ui/panel_modal.dart test/ui/panel_modal_test.dart
git commit -m "feat: add border rendering for tape/simple/heavy panel styles"
```

---

## Task 3: Barrier rendering

**Files:**

- Modify: `lib/src/ui/panel_modal.dart`
- Modify: `test/ui/panel_modal_test.dart`

**Step 1: Write failing tests**

Add to `test/ui/panel_modal_test.dart`:

```dart
  group('applyBarrier', () {
    test('dim wraps lines with dim escape', () {
      final input = ['hello', 'world'];
      final result = applyBarrier(BarrierStyle.dim, input);
      expect(result[0], contains('\x1b[2m'));
      expect(result[0], contains('hello'));
    });

    test('obscure replaces content with block chars', () {
      final input = ['hello', 'world'];
      final result = applyBarrier(BarrierStyle.obscure, input);
      for (final line in result) {
        final stripped = stripAnsi(line);
        expect(stripped, isNot(contains('hello')));
        expect(stripped, isNot(contains('world')));
      }
    });

    test('none returns lines unchanged', () {
      final input = ['hello', 'world'];
      final result = applyBarrier(BarrierStyle.none, input);
      expect(result, input);
    });

    test('dim preserves line count', () {
      final input = List.generate(20, (i) => 'line $i');
      final result = applyBarrier(BarrierStyle.dim, input);
      expect(result.length, input.length);
    });
  });
```

**Step 2: Run tests to verify they fail**

Run: `dart test test/ui/panel_modal_test.dart`
Expected: FAIL — `applyBarrier` not defined

**Step 3: Implement `applyBarrier`**

Add to `lib/src/ui/panel_modal.dart`:

```dart
// ---------------------------------------------------------------------------
// Barrier rendering
// ---------------------------------------------------------------------------

/// Apply a barrier effect to background lines.
List<String> applyBarrier(BarrierStyle style, List<String> lines) {
  return switch (style) {
    BarrierStyle.none => lines,
    BarrierStyle.dim => [
        for (final line in lines) '\x1b[2m${stripAnsi(line)}\x1b[0m',
      ],
    BarrierStyle.obscure => [
        for (final line in lines)
          '\x1b[90m${'░' * visibleLength(line)}\x1b[0m',
      ],
  };
}
```

**Step 4: Run tests**

Run: `dart test test/ui/panel_modal_test.dart`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/src/ui/panel_modal.dart test/ui/panel_modal_test.dart
git commit -m "feat: add barrier rendering (dim/obscure/none) for panel modal"
```

---

## Task 4: `PanelModal` class — state, scrolling, event handling

**Files:**

- Modify: `lib/src/ui/panel_modal.dart`
- Modify: `test/ui/panel_modal_test.dart`

**Step 1: Write failing tests**

Add to `test/ui/panel_modal_test.dart`:

```dart
  group('PanelModal', () {
    late PanelModal panel;

    setUp(() {
      panel = PanelModal(
        title: 'TEST',
        lines: List.generate(30, (i) => 'Line $i'),
        style: PanelStyle.simple,
        barrier: BarrierStyle.dim,
        width: const PanelFixed(40),
        height: const PanelFixed(10),
      );
    });

    test('initial scroll offset is 0', () {
      expect(panel.scrollOffset, 0);
    });

    test('scroll down advances offset', () {
      panel.handleEvent(KeyEvent(Key.down));
      expect(panel.scrollOffset, 1);
    });

    test('scroll up at top stays at 0', () {
      panel.handleEvent(KeyEvent(Key.up));
      expect(panel.scrollOffset, 0);
    });

    test('scroll clamps to max', () {
      // 30 lines, 8 visible (10 - 2 borders), max scroll = 22
      for (var i = 0; i < 50; i++) {
        panel.handleEvent(KeyEvent(Key.down));
      }
      expect(panel.scrollOffset, 22);
    });

    test('page down scrolls by visible height', () {
      panel.handleEvent(KeyEvent(Key.pageDown));
      expect(panel.scrollOffset, 8); // visible height = 10 - 2 borders
    });

    test('escape completes result when dismissable', () {
      expect(panel.isComplete, false);
      panel.handleEvent(KeyEvent(Key.escape));
      expect(panel.isComplete, true);
    });

    test('escape does not complete when not dismissable', () {
      final locked = PanelModal(
        title: 'LOCKED',
        lines: ['content'],
        style: PanelStyle.simple,
        barrier: BarrierStyle.dim,
        dismissable: false,
      );
      locked.handleEvent(KeyEvent(Key.escape));
      expect(locked.isComplete, false);
    });

    test('swallows all other input', () {
      final consumed = panel.handleEvent(CharEvent('a'));
      expect(consumed, true);
    });

    test('render produces correct number of lines', () {
      final bg = List.generate(24, (i) => 'bg line $i');
      final rendered = panel.render(80, 24, bg);
      expect(rendered.length, 24);
    });
  });
```

**Step 2: Run tests to verify they fail**

Run: `dart test test/ui/panel_modal_test.dart`
Expected: FAIL — `PanelModal` not defined

**Step 3: Implement `PanelModal`**

Add to `lib/src/ui/panel_modal.dart`:

```dart
// ---------------------------------------------------------------------------
// Panel modal
// ---------------------------------------------------------------------------

/// A reusable, scrollable, centered floating panel.
///
/// Renders on top of dimmed terminal content. Handles its own scrolling
/// and dismiss via Escape. Exposes [result] future that completes on
/// dismiss (same pattern as [ConfirmModal]).
class PanelModal {
  final String title;
  final List<String> lines;
  final PanelStyle style;
  final BarrierStyle barrier;
  final PanelSize width;
  final PanelSize height;
  final bool dismissable;
  final _completer = Completer<void>();
  int _scrollOffset = 0;

  PanelModal({
    required this.title,
    required this.lines,
    this.style = PanelStyle.tape,
    this.barrier = BarrierStyle.dim,
    PanelSize? width,
    PanelSize? height,
    this.dismissable = true,
  })  : width = width ?? const PanelFluid(0.7, 40),
        height = height ?? const PanelFluid(0.7, 10);

  /// The future that resolves when the panel is dismissed.
  Future<void> get result => _completer.future;

  /// Whether the panel has been dismissed.
  bool get isComplete => _completer.isCompleted;

  /// Current scroll offset.
  int get scrollOffset => _scrollOffset;

  /// Handle a terminal event. Returns true if consumed.
  bool handleEvent(TerminalEvent event) {
    if (_completer.isCompleted) return false;

    switch (event) {
      case KeyEvent(key: Key.escape):
        if (dismissable) _completer.complete();
        return true;
      case KeyEvent(key: Key.up):
        _scrollOffset = (_scrollOffset - 1).clamp(0, _maxScroll(20));
        return true;
      case KeyEvent(key: Key.down):
        _scrollOffset = (_scrollOffset + 1).clamp(0, _maxScroll(20));
        return true;
      case KeyEvent(key: Key.pageUp):
        _scrollOffset = (_scrollOffset - _lastVisibleHeight).clamp(0, _maxScroll(20));
        return true;
      case KeyEvent(key: Key.pageDown):
        _scrollOffset = (_scrollOffset + _lastVisibleHeight).clamp(0, _maxScroll(20));
        return true;
      default:
        return true; // Swallow all input while panel is open
    }
  }

  int _lastVisibleHeight = 8;

  int _maxScroll(int visibleHeight) {
    _lastVisibleHeight = visibleHeight;
    return math.max(0, lines.length - visibleHeight);
  }

  /// Close the panel programmatically.
  void dismiss() {
    if (!_completer.isCompleted) _completer.complete();
  }

  /// Render the panel over background content.
  ///
  /// Returns [termHeight] lines, each suitable for writing to the terminal.
  List<String> render(int termWidth, int termHeight, List<String> backgroundLines) {
    // 1. Resolve panel dimensions.
    final panelW = width.resolve(termWidth);
    final panelH = height.resolve(termHeight);
    final visibleContentH = panelH - 2; // minus top and bottom border
    _lastVisibleHeight = visibleContentH;
    _scrollOffset = _scrollOffset.clamp(0, _maxScroll(visibleContentH));

    // 2. Apply barrier to background.
    final bg = applyBarrier(barrier, backgroundLines);

    // 3. Pad/truncate background to fill terminal height.
    final grid = List<String>.generate(termHeight, (i) {
      return i < bg.length ? bg[i] : '';
    });

    // 4. Render the border frame.
    final border = renderBorder(style, panelW, panelH, title);

    // 5. Calculate panel position (centered).
    final topRow = math.max(0, (termHeight - panelH) ~/ 2);
    final leftCol = math.max(0, (termWidth - panelW) ~/ 2);

    // 6. Get visible content slice.
    final contentEnd = math.min(_scrollOffset + visibleContentH, lines.length);
    final contentStart = math.min(_scrollOffset, contentEnd);
    final visibleContent = lines.sublist(contentStart, contentEnd);

    // 7. Splice border into grid, filling interior with content.
    for (var i = 0; i < panelH; i++) {
      final gridRow = topRow + i;
      if (gridRow >= termHeight) break;

      if (i == 0 || i == panelH - 1) {
        // Top or bottom border line.
        grid[gridRow] = _spliceInto(grid[gridRow], border[i], leftCol, termWidth);
      } else {
        // Interior line: border with content inside (1-char padding).
        final contentIdx = i - 1;
        final innerWidth = panelW - 4; // border + padding on each side
        String content;
        if (contentIdx < visibleContent.length) {
          content = visibleContent[contentIdx];
          // Truncate if too wide.
          if (visibleLength(content) > innerWidth) {
            content = ansiTruncate(content, innerWidth);
          }
          // Pad to fill.
          final pad = innerWidth - visibleLength(content);
          if (pad > 0) content = '$content${' ' * pad}';
        } else {
          content = ' ' * innerWidth;
        }

        final interiorLine = _buildInteriorLine(style, content, panelW);
        grid[gridRow] = _spliceInto(grid[gridRow], interiorLine, leftCol, termWidth);
      }
    }

    // 8. Add scroll indicator if needed.
    if (lines.length > visibleContentH) {
      final page = (_scrollOffset ~/ visibleContentH) + 1;
      final totalPages = (lines.length / visibleContentH).ceil();
      final indicator = ' $page/$totalPages ';
      final indicatorRow = topRow + panelH - 1;
      if (indicatorRow < termHeight) {
        // Overwrite into the bottom border, near the right side.
        final indicatorCol = leftCol + panelW - indicator.length - 2;
        if (indicatorCol > leftCol) {
          grid[indicatorRow] = _spliceInto(
            grid[indicatorRow],
            '\x1b[90m$indicator\x1b[0m',
            indicatorCol,
            termWidth,
          );
        }
      }
    }

    return grid;
  }

  String _buildInteriorLine(PanelStyle style, String content, int panelW) {
    return switch (style) {
      PanelStyle.simple => '\x1b[90m│\x1b[0m $content \x1b[90m│\x1b[0m',
      PanelStyle.heavy => '\x1b[33m║\x1b[0m $content \x1b[33m║\x1b[0m',
      PanelStyle.tape => '\x1b[33m│\x1b[0m $content \x1b[33m│\x1b[0m',
    };
  }

  /// Splice [overlay] into [background] at column [col].
  String _spliceInto(String background, String overlay, int col, int totalWidth) {
    // For simplicity, pad background to totalWidth then overlay at col.
    final bgStripped = stripAnsi(background);
    final bgPadded = bgStripped.length < totalWidth
        ? '$bgStripped${' ' * (totalWidth - bgStripped.length)}'
        : bgStripped;

    final overlayVisible = visibleLength(overlay);
    final before = bgPadded.substring(0, col.clamp(0, bgPadded.length));
    final afterStart = (col + overlayVisible).clamp(0, bgPadded.length);
    final after = afterStart < bgPadded.length
        ? bgPadded.substring(afterStart)
        : '';

    return '$before$overlay$after';
  }
}
```

**Step 4: Run tests**

Run: `dart test test/ui/panel_modal_test.dart`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/src/ui/panel_modal.dart test/ui/panel_modal_test.dart
git commit -m "feat: add PanelModal class with scrolling, dismiss, and full-screen rendering"
```

---

## Task 5: Wire PanelModal into App and convert `/help`

**Files:**

- Modify: `lib/src/app.dart`
- Modify: `lib/glue.dart`

**Step 1: Add `_activePanel` field to `App`**

In `lib/src/app.dart`, add import and field:

```dart
import 'ui/panel_modal.dart';
```

Add field alongside `_activeModal`:

```dart
PanelModal? _activePanel;
```

**Step 2: Route events to panel in `_handleTerminalEvent`**

At the top of `_handleTerminalEvent`, before the `ConfirmModal` check, add:

```dart
      // Panel modal gets first crack at input.
      if (_activePanel != null && !_activePanel!.isComplete) {
        if (_activePanel!.handleEvent(event)) {
          _render();
          return;
        }
      }
```

**Step 3: Render panel in `_doRender`**

In `_doRender()`, after building `outputLines` and before painting, add a panel rendering path. If `_activePanel` is active, it takes over the entire viewport:

After the line `outputLines.add('');` (trailing blank), add:

```dart
    // Panel modal takes over the full viewport.
    if (_activePanel != null && !_activePanel!.isComplete) {
      final panelGrid = _activePanel!.render(
        terminal.columns,
        terminal.rows,
        outputLines,
      );
      // Paint the full grid directly.
      terminal.hideCursor();
      for (var i = 0; i < panelGrid.length && i < terminal.rows; i++) {
        terminal.moveTo(i + 1, 1);
        terminal.clearLine();
        terminal.write(panelGrid[i]);
      }
      terminal.hideCursor();
      return;
    }
```

**Step 4: Convert `/help` command to open a panel**

In `_initCommands()`, replace the `/help` command body:

```dart
    _commands.register(SlashCommand(
      name: 'help',
      description: 'Show available commands and keybindings',
      execute: (_) {
        _openHelpPanel();
        return '';
      },
    ));
```

Add the helper method to `App`:

```dart
  void _openHelpPanel() {
    const yellow = '\x1b[33m';
    const rst = '\x1b[0m';
    const dim = '\x1b[90m';

    final lines = <String>[];

    lines.add('$yellow■ COMMANDS$rst');
    lines.add('');
    for (final cmd in _commands.commands) {
      final aliases = cmd.aliases.isNotEmpty
          ? ' ${dim}(${cmd.aliases.map((a) => '/$a').join(', ')})$rst'
          : '';
      final name = '/${cmd.name}'.padRight(16);
      lines.add('  $yellow$name$rst${cmd.description}$aliases');
    }

    lines.add('');
    lines.add('$yellow■ KEYBINDINGS$rst');
    lines.add('');
    lines.add('  ${'Ctrl+C'.padRight(16)}${rst}Cancel / Exit');
    lines.add('  ${'Escape'.padRight(16)}${rst}Cancel generation');
    lines.add('  ${'Up / Down'.padRight(16)}${rst}History navigation');
    lines.add('  ${'Ctrl+U'.padRight(16)}${rst}Clear line');
    lines.add('  ${'Ctrl+W'.padRight(16)}${rst}Delete word');
    lines.add('  ${'Ctrl+A / E'.padRight(16)}${rst}Start / End of line');
    lines.add('  ${'PageUp / Dn'.padRight(16)}${rst}Scroll output');
    lines.add('  ${'Tab'.padRight(16)}${rst}Accept completion');

    lines.add('');
    lines.add('$yellow■ FILE REFERENCES$rst');
    lines.add('');
    lines.add('  ${'@path/to/file'.padRight(16)}${rst}Attach file to message');
    lines.add('  ${'@dir/'.padRight(16)}${rst}Browse directory');

    _activePanel = PanelModal(
      title: 'HELP',
      lines: lines,
      style: PanelStyle.tape,
      barrier: BarrierStyle.dim,
    );
    _activePanel!.result.then((_) {
      _activePanel = null;
      _render();
    });
    _render();
  }
```

**Step 5: Export from barrel**

In `lib/glue.dart`, add:

```dart
export 'src/ui/panel_modal.dart' show PanelModal, PanelStyle, BarrierStyle, PanelSize, PanelFixed, PanelFluid;
```

**Step 6: Run tests**

Run: `dart test`
Expected: All pass

Run: `dart analyze`
Expected: No issues

**Step 7: Commit**

```bash
git add lib/src/app.dart lib/src/ui/panel_modal.dart lib/glue.dart
git commit -m "feat: wire PanelModal into App, convert /help to construction-branded panel"
```

---

## Execution Order

All tasks are sequential — each builds on the previous:

1. Task 1: PanelSize sealed class
2. Task 2: Border rendering (3 styles)
3. Task 3: Barrier rendering
4. Task 4: PanelModal class
5. Task 5: App integration + /help conversion
