import 'dart:async';
import 'dart:math';

import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/box.dart';

enum PanelStyle { tape, simple, heavy }

enum BarrierStyle { dim, obscure, none }

sealed class PanelSize {
  int resolve(int available);
}

class PanelFixed extends PanelSize {
  final int size;
  PanelFixed(this.size);

  @override
  int resolve(int available) => min(size, available);
}

class PanelFluid extends PanelSize {
  final double maxPercent;
  final int minSize;
  final int margin;
  PanelFluid(this.maxPercent, this.minSize, {this.margin = 2});

  @override
  int resolve(int available) {
    if (available <= 0) return 0;
    final percent = (available * maxPercent).floor();
    if (percent >= minSize) {
      return min(percent, available);
    }
    // Floor hit. Only fall back to (available - margin) when the floor
    // dominates the terminal (> 75% of available width). Otherwise the
    // caller explicitly wanted a small panel in a big terminal; respect
    // that and return the floor.
    if (minSize * 4 > available * 3) {
      if (available - margin >= minSize) {
        return available - margin;
      }
      return available; // too tiny even for a margin
    }
    return minSize;
  }
}

List<String> renderBorder(
  PanelStyle style,
  int width,
  int height,
  String title,
) {
  return switch (style) {
    PanelStyle.simple => _renderSimple(width, height, title),
    PanelStyle.heavy => _renderHeavy(width, height, title),
    PanelStyle.tape => _renderTape(width, height, title),
  };
}

List<String> _renderSimple(int width, int height, String title) {
  final lines = <String>[];
  final innerWidth = width - 2;
  final titleStr = ' $title ';
  final fillCount = max(innerWidth - titleStr.length - 1, 0);
  final top = '\x1b[2m┌─\x1b[0m'
      '\x1b[36m$titleStr\x1b[0m'
      '\x1b[2m${'─' * fillCount}┐\x1b[0m';
  lines.add(top);

  final interior = '\x1b[2m│\x1b[0m'
      '${' ' * innerWidth}'
      '\x1b[2m│\x1b[0m';
  for (var i = 1; i < height - 1; i++) {
    lines.add(interior);
  }

  final bottom = '\x1b[2m└${'─' * innerWidth}┘\x1b[0m';
  lines.add(bottom);
  return lines;
}

List<String> _renderHeavy(int width, int height, String title) {
  final lines = <String>[];
  final innerWidth = width - 2;
  final titleStr = ' $title ';
  final fillCount = max(innerWidth - titleStr.length - 1, 0);
  final top = '\x1b[36m╔═$titleStr${'═' * fillCount}╗\x1b[0m';
  lines.add(top);

  final interior = '\x1b[36m║\x1b[0m'
      '${' ' * innerWidth}'
      '\x1b[36m║\x1b[0m';
  for (var i = 1; i < height - 1; i++) {
    lines.add(interior);
  }

  final bottom = '\x1b[36m╚${'═' * innerWidth}╝\x1b[0m';
  lines.add(bottom);
  return lines;
}

List<String> _renderTape(int width, int height, String title) {
  final lines = <String>[];
  final innerWidth = width - 2;

  final titleStr = ' $title ';
  const tapePattern = '▚▞';
  const prefixLen = 2;
  final suffixLen = max(width - titleStr.length - prefixLen, 0);
  final prefixTape = _repeatTape(tapePattern, prefixLen);
  final suffixTape = _repeatTape(tapePattern, suffixLen);
  final top = '\x1b[36m$prefixTape\x1b[0m'
      '\x1b[30;46m$titleStr\x1b[0m'
      '\x1b[36m$suffixTape\x1b[0m';
  lines.add(top);

  final interior = '\x1b[36m│\x1b[0m'
      '${' ' * innerWidth}'
      '\x1b[36m│\x1b[0m';
  for (var i = 1; i < height - 1; i++) {
    lines.add(interior);
  }

  final bottomTape = _repeatTape(tapePattern, width);
  final bottom = '\x1b[36m$bottomTape\x1b[0m';
  lines.add(bottom);
  return lines;
}

String _repeatTape(String pattern, int length) {
  final buf = StringBuffer();
  for (var i = 0; i < length; i++) {
    buf.write(pattern[i % pattern.length]);
  }
  return buf.toString();
}

List<String> applyBarrier(BarrierStyle style, List<String> lines) {
  return switch (style) {
    BarrierStyle.none => lines,
    BarrierStyle.dim =>
      lines.map((line) => '${stripAnsi(line).styled.dim}').toList(),
    BarrierStyle.obscure => lines.map((line) {
        final len = visibleLength(line);
        return ('░' * len).styled.gray.toString();
      }).toList(),
  };
}

abstract class PanelOverlay {
  bool get isComplete;
  bool handleEvent(TerminalEvent event);
  List<String> render(
      int termWidth, int termHeight, List<String> backgroundLines);
  void cancel();
}

class PanelModal implements PanelOverlay {
  final String title;
  final List<String> Function(int contentWidth) linesBuilder;
  final Box box;
  final String borderColor;
  final BarrierStyle barrier;
  final PanelSize _width;
  final PanelSize _height;
  final bool dismissable;
  final bool selectable;
  final FutureOr<void> Function()? onOpenInEditor;

  int _scrollOffset = 0;
  int _selectedIndex;
  final Completer<void> _completer = Completer<void>();
  final Completer<int?> _selectionCompleter = Completer<int?>();
  int _lastVisibleHeight = 0;
  List<String> _lastLines = const [];

  /// Snapshot of the current lines at an assumed 80-col content width.
  /// Prefer `linesBuilder(width)` for width-aware access.
  List<String> get lines =>
      _lastLines.isNotEmpty ? _lastLines : linesBuilder(80);

  PanelModal({
    required this.title,
    required List<String> lines,
    this.box = Box.light,
    this.borderColor = '\x1b[2m',
    this.barrier = BarrierStyle.dim,
    PanelSize? width,
    PanelSize? height,
    this.dismissable = true,
    this.selectable = false,
    this.onOpenInEditor,
    int initialIndex = 0,
  })  : linesBuilder = ((_) => lines),
        _lastLines = lines,
        _width = width ?? PanelFluid(0.7, 40),
        _height = height ?? PanelFluid(0.7, 10),
        _selectedIndex = initialIndex {
    if (_height case PanelFixed(:final size)) {
      _lastVisibleHeight = size - 2;
    }
  }

  PanelModal.responsive({
    required this.title,
    required this.linesBuilder,
    this.box = Box.light,
    this.borderColor = '\x1b[2m',
    this.barrier = BarrierStyle.dim,
    PanelSize? width,
    PanelSize? height,
    this.dismissable = true,
    this.selectable = false,
    this.onOpenInEditor,
    int initialIndex = 0,
  })  : _lastLines = linesBuilder(80),
        _width = width ?? PanelFluid(0.7, 40),
        _height = height ?? PanelFluid(0.7, 10),
        _selectedIndex = initialIndex {
    if (_height case PanelFixed(:final size)) {
      _lastVisibleHeight = size - 2;
    }
  }

  int get scrollOffset => _scrollOffset;
  @override
  bool get isComplete => _completer.isCompleted;
  Future<void> get result => _completer.future;
  int get selectedIndex => selectable ? _selectedIndex : -1;
  Future<int?> get selection =>
      selectable ? _selectionCompleter.future : Future.value(null);

  void dismiss() {
    if (!_completer.isCompleted) _completer.complete();
    if (selectable && !_selectionCompleter.isCompleted) {
      _selectionCompleter.complete(null);
    }
  }

  @override
  void cancel() => dismiss();

  @override
  bool handleEvent(TerminalEvent event) {
    if (isComplete) return false;

    final visibleH = max<int>(_lastVisibleHeight, 1);
    final maxScroll = max<int>(0, _lastLines.length - visibleH);

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
      case KeyEvent(key: Key.ctrlE):
        if (onOpenInEditor != null) {
          unawaited(Future.sync(onOpenInEditor!));
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
          _selectedIndex = min<int>(_lastLines.length - 1, _selectedIndex + 1);
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
          _selectedIndex =
              min<int>(_lastLines.length - 1, _selectedIndex + visibleH);
          _scrollOffset = min<int>(maxScroll, _scrollOffset + visibleH);
        } else {
          _scrollOffset = min<int>(maxScroll, _scrollOffset + visibleH);
        }
        return true;
      case CharEvent(char: 'e', alt: false):
        if (onOpenInEditor != null) {
          unawaited(Future.sync(onOpenInEditor!));
        }
        return true;
      default:
        return true;
    }
  }

  @override
  List<String> render(
      int termWidth, int termHeight, List<String> backgroundLines) {
    final panelW = _width.resolve(termWidth);
    final panelH = _height.resolve(termHeight);
    final visibleContentH = panelH - 2;
    _lastVisibleHeight = visibleContentH;

    final contentW = panelW - 4;
    _lastLines = linesBuilder(contentW);

    final maxScroll = max(0, _lastLines.length - visibleContentH);
    _scrollOffset = min(_scrollOffset, maxScroll);

    final dimmed = applyBarrier(barrier, backgroundLines);
    final grid = List<String>.generate(
        termHeight, (i) => i < dimmed.length ? dimmed[i] : '');

    final border = box.renderFrame(panelW, panelH, title, color: borderColor);

    final topRow = (termHeight - panelH) ~/ 2;
    final leftCol = (termWidth - panelW) ~/ 2;

    final visibleLines = _lastLines.sublist(
      _scrollOffset,
      min(_scrollOffset + visibleContentH, _lastLines.length),
    );

    final hasOverflow = _lastLines.length > visibleContentH;
    final totalPages =
        (_lastLines.length + visibleContentH - 1) ~/ visibleContentH;
    final currentPage = (_scrollOffset ~/ max(visibleContentH, 1)) + 1;

    final panelLines = <String>[];
    for (var r = 0; r < panelH; r++) {
      if (r == 0) {
        panelLines.add(border.first);
      } else if (r == panelH - 1) {
        if (hasOverflow) {
          final indicator = '$currentPage/$totalPages';
          final borderStr = stripAnsi(border.last);
          final insertPos = borderStr.length - indicator.length - 2;
          if (insertPos > 0) {
            final before =
                border.last.substring(0, _ansiIndex(border.last, insertPos));
            final after = border.last.substring(
                _ansiIndex(border.last, insertPos + indicator.length));
            panelLines.add('$before$indicator$after');
          } else {
            panelLines.add(border.last);
          }
        } else {
          panelLines.add(border.last);
        }
      } else {
        final contentIdx = r - 1;
        final raw =
            contentIdx < visibleLines.length ? visibleLines[contentIdx] : '';
        final truncated = ansiTruncate(raw, contentW);
        final padLen = contentW - visibleLength(truncated);
        final padded = '$truncated${' ' * max(0, padLen)}';

        final isSelected =
            selectable && (contentIdx + _scrollOffset) == _selectedIndex;
        final styledContent = isSelected ? '${padded.styled.inverse}' : padded;

        final (leftBorder, rightBorder) = box.styledSides(color: borderColor);

        panelLines.add('$leftBorder $styledContent $rightBorder');
      }
    }

    for (var r = 0; r < panelH; r++) {
      final gridRow = topRow + r;
      if (gridRow < 0 || gridRow >= termHeight) continue;
      grid[gridRow] =
          _spliceRow(grid[gridRow], leftCol, panelW, panelLines[r], termWidth);
    }

    return grid;
  }

  int _ansiIndex(String s, int visiblePos) {
    final ansiPattern = RegExp(r'\x1b\[[0-9;]*[a-zA-Z]');
    var visible = 0;
    var i = 0;
    while (i < s.length && visible < visiblePos) {
      final match = ansiPattern.matchAsPrefix(s, i);
      if (match != null) {
        i += match.group(0)!.length;
      } else {
        visible++;
        i++;
      }
    }
    return i;
  }

  String _spliceRow(
      String bgLine, int leftCol, int panelW, String overlay, int termWidth) {
    final bgVisible = visibleLength(bgLine);
    final paddedBg = bgVisible < termWidth
        ? '$bgLine${' ' * (termWidth - bgVisible)}'
        : bgLine;
    final safeLeft = leftCol.clamp(0, termWidth);
    final safeRight = (leftCol + panelW).clamp(0, termWidth);
    final beforeSlice = paddedBg.substring(0, _ansiIndex(paddedBg, safeLeft));
    final afterSlice = paddedBg.substring(_ansiIndex(paddedBg, safeRight));
    final overlayPad = max(0, panelW - visibleLength(overlay));
    if (barrier == BarrierStyle.none) {
      return '$beforeSlice$overlay${' ' * overlayPad}$afterSlice';
    }
    final before = _applyBarrierStyle(stripAnsi(beforeSlice));
    final after = _applyBarrierStyle(stripAnsi(afterSlice));
    return '$before$overlay${' ' * overlayPad}$after';
  }

  String _applyBarrierStyle(String text) {
    if (text.isEmpty) return text;
    return switch (barrier) {
      BarrierStyle.dim => '${text.styled.dim}',
      BarrierStyle.obscure => '${text.styled.gray}',
      BarrierStyle.none => text,
    };
  }
}
