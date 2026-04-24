import 'dart:async';
import 'dart:math';

import 'package:glue/src/ui/rendering/ansi_utils.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/components/box.dart';

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

abstract class AbstractPanel {
  bool get isComplete;
  bool handleEvent(TerminalEvent event);
  List<String> render(
      int termWidth, int termHeight, List<String> backgroundLines);
  void cancel();
}

class Panel implements AbstractPanel {
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

  Panel({
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

  Panel.responsive({
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
        final styledContent =
            isSelected ? '${padded.styled.bg256(237)}' : padded;

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

class SelectOption<T> {
  final T value;
  final String Function(int contentWidth) renderLabel;
  final String searchText;

  SelectOption({
    required this.value,
    required String label,
    String? searchText,
  })  : renderLabel = ((_) => label),
        searchText = searchText ?? label;

  SelectOption.responsive({
    required this.value,
    required String Function(int contentWidth) build,
    required this.searchText,
  }) : renderLabel = build;

  /// Back-compat getter — callers that need a one-shot snapshot at a default width.
  /// Prefer `renderLabel(width)` directly.
  String get label => renderLabel(80);
}

class SelectPanel<T> implements AbstractPanel {
  final String title;
  final List<SelectOption<T>> options;
  final List<String> headerLines;
  final List<String> Function(int contentWidth)? headerBuilder;
  final String emptyText;
  final bool searchEnabled;
  final String searchHint;
  final Box box;
  final String borderColor;
  final BarrierStyle barrier;
  final PanelSize _width;
  final PanelSize _height;
  final bool dismissable;
  final void Function(List<int> filtered)? onFilterChanged;

  int _scrollOffset = 0;
  int _selectedIndex = 0;
  int _lastListHeight = 1;
  int _lastContentWidth = 80;
  String _query = '';

  final Completer<void> _resultCompleter = Completer<void>();
  final Completer<T?> _selectionCompleter = Completer<T?>();

  SelectPanel({
    required this.title,
    required this.options,
    this.headerLines = const [],
    this.headerBuilder,
    this.emptyText = 'No results.',
    this.searchEnabled = true,
    this.searchHint = 'Type to filter',
    this.box = Box.light,
    this.borderColor = '\x1b[2m',
    this.barrier = BarrierStyle.dim,
    PanelSize? width,
    PanelSize? height,
    this.dismissable = true,
    int initialIndex = 0,
    this.onFilterChanged,
  })  : assert(
          headerBuilder == null || headerLines.isEmpty,
          'Provide either headerLines or headerBuilder, not both.',
        ),
        _width = width ?? PanelFluid(0.7, 40),
        _height = height ?? PanelFluid(0.6, 10) {
    _selectedIndex =
        options.isEmpty ? 0 : initialIndex.clamp(0, options.length - 1);
  }

  @override
  bool get isComplete => _resultCompleter.isCompleted;

  Future<void> get result => _resultCompleter.future;
  Future<T?> get selection => _selectionCompleter.future;

  @override
  void cancel() => dismiss();

  void dismiss() {
    if (!_resultCompleter.isCompleted) _resultCompleter.complete();
    if (!_selectionCompleter.isCompleted) _selectionCompleter.complete(null);
  }

  @override
  bool handleEvent(TerminalEvent event) {
    if (isComplete) return false;

    final filtered = _filteredIndices();
    final listHeight = _lastListHeight;
    final maxScroll = max(0, filtered.length - listHeight);

    switch (event) {
      case KeyEvent(key: Key.escape):
        if (dismissable) dismiss();
        return true;
      case KeyEvent(key: Key.enter):
        if (filtered.isEmpty) {
          dismiss();
          return true;
        }
        final selected = options[_selectedIndexForFiltered(filtered)].value;
        if (!_selectionCompleter.isCompleted) {
          _selectionCompleter.complete(selected);
        }
        if (!_resultCompleter.isCompleted) _resultCompleter.complete();
        return true;
      case KeyEvent(key: Key.backspace):
        if (searchEnabled && _query.isNotEmpty) {
          _query = _query.substring(0, _query.length - 1);
          _scrollOffset = 0;
          _notifyFilterChanged();
          _normalizeSelection();
        }
        return true;
      case KeyEvent(key: Key.ctrlU):
        if (searchEnabled && _query.isNotEmpty) {
          _query = '';
          _scrollOffset = 0;
          _notifyFilterChanged();
          _normalizeSelection();
        }
        return true;
      case KeyEvent(key: Key.up):
        if (filtered.isEmpty) return true;
        final selectedPos = _selectedPosition(filtered);
        final nextPos = max(0, selectedPos - 1);
        _selectedIndex = filtered[nextPos];
        if (nextPos < _scrollOffset) _scrollOffset = nextPos;
        return true;
      case KeyEvent(key: Key.down):
        if (filtered.isEmpty) return true;
        final selectedPos = _selectedPosition(filtered);
        final nextPos = min(filtered.length - 1, selectedPos + 1);
        _selectedIndex = filtered[nextPos];
        if (nextPos >= _scrollOffset + listHeight) {
          _scrollOffset = nextPos - listHeight + 1;
        }
        return true;
      case KeyEvent(key: Key.pageUp):
        if (filtered.isEmpty) return true;
        final selectedPos = _selectedPosition(filtered);
        final nextPos = max(0, selectedPos - listHeight);
        _selectedIndex = filtered[nextPos];
        _scrollOffset = max(0, _scrollOffset - listHeight);
        return true;
      case KeyEvent(key: Key.pageDown):
        if (filtered.isEmpty) return true;
        final selectedPos = _selectedPosition(filtered);
        final nextPos = min(filtered.length - 1, selectedPos + listHeight);
        _selectedIndex = filtered[nextPos];
        _scrollOffset = min(maxScroll, _scrollOffset + listHeight);
        return true;
      case CharEvent(:final char, alt: false)
          when searchEnabled && _isSearchChar(char):
        _query += char.toLowerCase();
        _scrollOffset = 0;
        _notifyFilterChanged();
        _normalizeSelection();
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
    final contentHeight = max(1, panelH - 2);

    final topRows = searchEnabled ? 1 : 0;
    final maxHeaderRows = max(0, contentHeight - topRows - 1);

    final contentW = max(1, panelW - 4);
    _lastContentWidth = contentW;
    final effectiveHeader = headerBuilder?.call(contentW) ?? headerLines;

    final visibleHeaderRows = min(effectiveHeader.length, maxHeaderRows);
    final listHeight = max(1, contentHeight - topRows - visibleHeaderRows);
    _lastListHeight = listHeight;

    final filtered = _filteredIndices();
    final maxScroll = max(0, filtered.length - listHeight);
    _scrollOffset = _scrollOffset.clamp(0, maxScroll);
    _normalizeSelection();

    final hasOverflow = filtered.length > listHeight;
    final totalPages =
        listHeight > 0 ? (filtered.length + listHeight - 1) ~/ listHeight : 1;
    final currentPage = (_scrollOffset ~/ max(1, listHeight)) + 1;

    final dimmed = applyBarrier(barrier, backgroundLines);
    final grid = List<String>.generate(
      termHeight,
      (i) => i < dimmed.length ? dimmed[i] : '',
    );

    final border = box.renderFrame(panelW, panelH, title, color: borderColor);
    final topRow = (termHeight - panelH) ~/ 2;
    final leftCol = (termWidth - panelW) ~/ 2;

    final selectedGlobalIndex = _selectedIndexForFiltered(filtered);

    final panelLines = <String>[];
    for (var r = 0; r < panelH; r++) {
      if (r == 0) {
        panelLines.add(border.first);
        continue;
      }
      if (r == panelH - 1) {
        if (!hasOverflow) {
          panelLines.add(border.last);
          continue;
        }
        final indicator = '$currentPage/$totalPages';
        final borderStr = stripAnsi(border.last);
        final insertPos = borderStr.length - indicator.length - 2;
        if (insertPos > 0) {
          final before =
              border.last.substring(0, _ansiIndex(border.last, insertPos));
          final after = border.last
              .substring(_ansiIndex(border.last, insertPos + indicator.length));
          panelLines.add('$before$indicator$after');
        } else {
          panelLines.add(border.last);
        }
        continue;
      }

      final contentRow = r - 1;
      final raw = _contentAtRow(
        contentRow: contentRow,
        contentHeight: contentHeight,
        visibleHeaderRows: visibleHeaderRows,
        effectiveHeader: effectiveHeader,
        filtered: filtered,
        selectedGlobalIndex: selectedGlobalIndex,
      );
      final truncated = ansiTruncate(raw.$1, contentW);
      final padded = _padAnsi(truncated, contentW);
      final styledContent = raw.$2 ? '${padded.styled.bg256(237)}' : padded;
      final (leftBorder, rightBorder) = box.styledSides(color: borderColor);
      panelLines.add('$leftBorder $styledContent $rightBorder');
    }

    for (var r = 0; r < panelH; r++) {
      final gridRow = topRow + r;
      if (gridRow < 0 || gridRow >= termHeight) continue;
      grid[gridRow] =
          _spliceRow(grid[gridRow], leftCol, panelW, panelLines[r], termWidth);
    }

    return grid;
  }

  (String, bool) _contentAtRow({
    required int contentRow,
    required int contentHeight,
    required int visibleHeaderRows,
    required List<String> effectiveHeader,
    required List<int> filtered,
    required int selectedGlobalIndex,
  }) {
    var rowOffset = 0;

    if (searchEnabled) {
      if (contentRow == 0) return (_renderSearchRow(filtered.length), false);
      rowOffset = 1;
    }

    if (contentRow < rowOffset + visibleHeaderRows) {
      final headerIdx = contentRow - rowOffset;
      return (effectiveHeader[headerIdx], false);
    }
    rowOffset += visibleHeaderRows;

    final listRow = contentRow - rowOffset;
    final optionPos = _scrollOffset + listRow;
    if (optionPos < filtered.length) {
      final optionIndex = filtered[optionPos];
      final option = options[optionIndex];
      final selected = optionIndex == selectedGlobalIndex;
      return (option.renderLabel(_lastContentWidth), selected);
    }

    if (filtered.isEmpty && listRow == 0) {
      return ('${emptyText.styled.dim}', false);
    }
    if (listRow == 0 && options.isEmpty) {
      return ('${'No items available.'.styled.dim}', false);
    }
    return ('', false);
  }

  String _renderSearchRow(int filteredCount) {
    if (!searchEnabled) return '';
    if (_query.isEmpty) {
      return '${'/$searchHint'.styled.dim} ${'(${options.length})'.styled.gray}';
    }
    return '${'/$_query'.styled.dim} ${'($filteredCount/${options.length})'.styled.gray}';
  }

  List<int> _filteredIndices() {
    if (options.isEmpty) return const [];
    final query = _query.trim();
    if (query.isEmpty) {
      return List<int>.generate(options.length, (i) => i, growable: false);
    }
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return List<int>.generate(options.length, (i) => i).where((i) {
      final haystack = stripAnsi(options[i].searchText).toLowerCase();
      for (final term in terms) {
        if (!haystack.contains(term)) return false;
      }
      return true;
    }).toList(growable: false);
  }

  void _normalizeSelection() {
    final filtered = _filteredIndices();
    if (filtered.isEmpty) {
      _scrollOffset = 0;
      return;
    }
    final selected = _selectedIndexForFiltered(filtered);
    _selectedIndex = selected;
    final pos = _selectedPosition(filtered);
    final maxScroll = max(0, filtered.length - _lastListHeight);
    if (pos < _scrollOffset) {
      _scrollOffset = pos;
    } else if (pos >= _scrollOffset + _lastListHeight) {
      _scrollOffset = pos - _lastListHeight + 1;
    }
    _scrollOffset = _scrollOffset.clamp(0, maxScroll);
  }

  int _selectedPosition(List<int> filtered) {
    final idx = filtered.indexOf(_selectedIndex);
    return idx >= 0 ? idx : 0;
  }

  int _selectedIndexForFiltered(List<int> filtered) {
    if (filtered.isEmpty) return -1;
    if (!filtered.contains(_selectedIndex)) return filtered.first;
    return _selectedIndex;
  }

  void _notifyFilterChanged() {
    onFilterChanged?.call(_filteredIndices());
  }

  bool _isSearchChar(String char) {
    if (char.isEmpty) return false;
    final rune = char.runes.first;
    return rune >= 0x20 && rune != 0x7f;
  }

  String _padAnsi(String text, int width) {
    final len = visibleLength(text);
    if (len >= width) return text;
    return '$text${' ' * (width - len)}';
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
    final afterStart = min(termWidth, leftCol + panelW);
    final beforeSlice = paddedBg.substring(0, _ansiIndex(paddedBg, safeLeft));
    final afterSlice = paddedBg.substring(_ansiIndex(paddedBg, afterStart));
    if (barrier == BarrierStyle.none) {
      return '$beforeSlice$overlay$afterSlice';
    }
    final before = _applyBarrierStyle(stripAnsi(beforeSlice));
    final after = _applyBarrierStyle(stripAnsi(afterSlice));
    return '$before$overlay$after';
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

class SplitPanel implements AbstractPanel {
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

  SplitPanel({
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
