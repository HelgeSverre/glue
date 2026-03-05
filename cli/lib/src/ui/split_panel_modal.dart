import 'dart:async';
import 'dart:math';

import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/panel_modal.dart';

class SplitPanelModal implements PanelOverlay {
  final String title;
  final List<String> leftItems;
  final List<String> Function(int selectedIndex, int rightWidth)
      buildRightLines;
  final PanelStyle style;
  final BarrierStyle barrier;
  final PanelSize _width;
  final PanelSize _height;
  final bool dismissable;

  int _scrollOffset = 0;
  int _selectedIndex = 0;
  final Completer<void> _completer = Completer<void>();
  final Completer<int?> _selectionCompleter = Completer<int?>();
  int _lastVisibleHeight = 0;

  SplitPanelModal({
    required this.title,
    required this.leftItems,
    required this.buildRightLines,
    this.style = PanelStyle.simple,
    this.barrier = BarrierStyle.dim,
    PanelSize? width,
    PanelSize? height,
    this.dismissable = true,
  })  : _width = width ?? PanelFluid(0.85, 60),
        _height = height ?? PanelFluid(0.7, 12) {
    if (_height case PanelFixed(:final size)) {
      _lastVisibleHeight = size - 2;
    }
  }

  int get scrollOffset => _scrollOffset;
  @override
  bool get isComplete => _completer.isCompleted;
  Future<void> get result => _completer.future;
  int get selectedIndex => _selectedIndex;
  Future<int?> get selection => _selectionCompleter.future;

  void dismiss() {
    if (!_completer.isCompleted) _completer.complete();
    if (!_selectionCompleter.isCompleted) _selectionCompleter.complete(null);
  }

  @override
  void cancel() => dismiss();

  @override
  bool handleEvent(TerminalEvent event) {
    if (isComplete) return false;

    final visibleH = max<int>(_lastVisibleHeight, 1);

    switch (event) {
      case KeyEvent(key: Key.escape):
        if (dismissable) dismiss();
        return true;
      case KeyEvent(key: Key.enter):
        if (!_selectionCompleter.isCompleted) {
          _selectionCompleter.complete(_selectedIndex);
        }
        if (!_completer.isCompleted) _completer.complete();
        return true;
      case KeyEvent(key: Key.up):
        _selectedIndex = max<int>(0, _selectedIndex - 1);
        if (_selectedIndex < _scrollOffset) {
          _scrollOffset = _selectedIndex;
        }
        return true;
      case KeyEvent(key: Key.down):
        _selectedIndex = min<int>(leftItems.length - 1, _selectedIndex + 1);
        if (_selectedIndex >= _scrollOffset + visibleH) {
          _scrollOffset = _selectedIndex - visibleH + 1;
        }
        return true;
      case KeyEvent(key: Key.pageUp):
        _selectedIndex = max<int>(0, _selectedIndex - visibleH);
        _scrollOffset = max<int>(0, _scrollOffset - visibleH);
        return true;
      case KeyEvent(key: Key.pageDown):
        final maxScroll = max<int>(0, leftItems.length - visibleH);
        _selectedIndex =
            min<int>(leftItems.length - 1, _selectedIndex + visibleH);
        _scrollOffset = min<int>(maxScroll, _scrollOffset + visibleH);
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
    final contentH = panelH - 2;
    final contentW = panelW - 4;
    _lastVisibleHeight = contentH;

    final leftW = contentW > 48
        ? (contentW * 0.35).floor().clamp(24, contentW - 24)
        : (contentW ~/ 2).clamp(1, contentW - 1);
    const dividerW = 1;
    final rightW = contentW - leftW - dividerW;

    final maxScroll = max(0, leftItems.length - contentH);
    _scrollOffset = min(_scrollOffset, maxScroll);

    final rightLines = buildRightLines(_selectedIndex, rightW);

    final dimmed = applyBarrier(barrier, backgroundLines);
    final grid = List<String>.generate(
        termHeight, (i) => i < dimmed.length ? dimmed[i] : '');

    final border = renderBorder(style, panelW, panelH, title);

    final topRow = (termHeight - panelH) ~/ 2;
    final leftCol = (termWidth - panelW) ~/ 2;

    final hasOverflow = leftItems.length > contentH;
    final totalPages = (leftItems.length + contentH - 1) ~/ max(contentH, 1);
    final currentPage = (_scrollOffset ~/ max(contentH, 1)) + 1;

    final (leftBorder, rightBorder) = switch (style) {
      PanelStyle.simple => ('\x1b[2m│\x1b[0m', '\x1b[2m│\x1b[0m'),
      PanelStyle.heavy => ('\x1b[33m║\x1b[0m', '\x1b[33m║\x1b[0m'),
      PanelStyle.tape => ('\x1b[33m│\x1b[0m', '\x1b[33m│\x1b[0m'),
    };

    const divider = '\x1b[2m│\x1b[0m';

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
        final leftIdx = _scrollOffset + contentIdx;

        String leftContent;
        if (leftIdx < leftItems.length) {
          final truncated = ansiTruncate(leftItems[leftIdx], leftW);
          final padLen = leftW - visibleLength(truncated);
          final padded = '$truncated${' ' * max(0, padLen)}';
          if (leftIdx == _selectedIndex) {
            final plain = stripAnsi(padded);
            leftContent = '\x1b[7m$plain\x1b[27m';
          } else {
            leftContent = padded;
          }
        } else {
          leftContent = ' ' * leftW;
        }

        String rightContent;
        if (contentIdx < rightLines.length) {
          final truncated = ansiTruncate(rightLines[contentIdx], rightW);
          final padLen = rightW - visibleLength(truncated);
          rightContent = '$truncated${' ' * max(0, padLen)}';
        } else {
          rightContent = ' ' * rightW;
        }

        panelLines
            .add('$leftBorder $leftContent$divider$rightContent $rightBorder');
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
