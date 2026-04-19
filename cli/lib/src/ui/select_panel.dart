import 'dart:async';
import 'dart:math';

import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/box.dart';
import 'package:glue/src/ui/panel_modal.dart';

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

class SelectPanel<T> implements PanelOverlay {
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
          _normalizeSelection();
        }
        return true;
      case KeyEvent(key: Key.ctrlU):
        if (searchEnabled && _query.isNotEmpty) {
          _query = '';
          _scrollOffset = 0;
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
