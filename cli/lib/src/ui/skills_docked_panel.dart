import 'dart:async';
import 'dart:math';

import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/skills/skill_parser.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/docked_panel.dart';
import 'package:glue/src/ui/panel_modal.dart';

class SkillsDockedPanel extends DockedPanel {
  final List<SkillMeta> _skills = [];

  @override
  DockEdge edge;

  @override
  DockMode mode;

  @override
  final int extent;

  bool _visible;
  int _scrollOffset = 0;
  int _selectedIndex = 0;
  int _lastVisibleHeight = 0;
  String _query = '';
  Completer<String?> _selectionCompleter = Completer<String?>();

  SkillsDockedPanel({
    required List<SkillMeta> skills,
    this.edge = DockEdge.bottom,
    this.mode = DockMode.floating,
    this.extent = 14,
    bool visible = false,
  }) : _visible = visible {
    updateSkills(skills);
  }

  Future<String?> get selection => _selectionCompleter.future;

  void updateSkills(List<SkillMeta> skills) {
    _skills
      ..clear()
      ..addAll(skills);
    final maxIndex = max(0, _skills.length - 1);
    _selectedIndex = _selectedIndex.clamp(0, maxIndex);
    _normalizeSelectionForQuery();
  }

  @override
  bool get visible => _visible;

  @override
  bool get hasFocus => _visible;

  @override
  void show() {
    _visible = true;
    _query = '';
    _scrollOffset = 0;
    _normalizeSelectionForQuery();
    if (_selectionCompleter.isCompleted) {
      _selectionCompleter = Completer<String?>();
    }
  }

  @override
  void dismiss() {
    _visible = false;
    if (!_selectionCompleter.isCompleted) {
      _selectionCompleter.complete(null);
    }
  }

  @override
  bool handleEvent(TerminalEvent event) {
    if (!_visible) return false;

    final filtered = _filteredIndices();
    final visibleHeight = _visibleListHeight;
    final maxScroll = max(0, filtered.length - visibleHeight);

    switch (event) {
      case KeyEvent(key: Key.escape):
        dismiss();
        return true;
      case KeyEvent(key: Key.backspace):
        if (_query.isNotEmpty) {
          _query = _query.substring(0, _query.length - 1);
          _scrollOffset = 0;
          _normalizeSelectionForQuery();
        }
        return true;
      case KeyEvent(key: Key.ctrlU):
        _query = '';
        _scrollOffset = 0;
        _normalizeSelectionForQuery();
        return true;
      case KeyEvent(key: Key.enter):
        if (filtered.isEmpty) {
          dismiss();
          return true;
        }
        final selectedIndex = _selectedIndexForFiltered(filtered);
        final selected = _skills[selectedIndex].name;
        if (!_selectionCompleter.isCompleted) {
          _selectionCompleter.complete(selected);
        }
        _visible = false;
        return true;
      case KeyEvent(key: Key.up):
        if (filtered.isEmpty) return true;
        final selectedPos = _selectedPosition(filtered);
        final nextPos = max(0, selectedPos - 1);
        _selectedIndex = filtered[nextPos];
        if (nextPos < _scrollOffset) {
          _scrollOffset = nextPos;
        }
        return true;
      case KeyEvent(key: Key.down):
        if (filtered.isEmpty) return true;
        final selectedPos = _selectedPosition(filtered);
        final nextPos = min(max(0, filtered.length - 1), selectedPos + 1);
        _selectedIndex = filtered[nextPos];
        if (nextPos >= _scrollOffset + visibleHeight) {
          _scrollOffset = nextPos - visibleHeight + 1;
        }
        return true;
      case KeyEvent(key: Key.pageUp):
        if (filtered.isEmpty) return true;
        final selectedPos = _selectedPosition(filtered);
        final nextPos = max(0, selectedPos - visibleHeight);
        _selectedIndex = filtered[nextPos];
        _scrollOffset = max(0, _scrollOffset - visibleHeight);
        return true;
      case KeyEvent(key: Key.pageDown):
        if (filtered.isEmpty) return true;
        final selectedPos = _selectedPosition(filtered);
        final nextPos =
            min(max(0, filtered.length - 1), selectedPos + visibleHeight);
        _selectedIndex = filtered[nextPos];
        _scrollOffset = min(maxScroll, _scrollOffset + visibleHeight);
        return true;
      case CharEvent(:final char, alt: false) when _isSearchChar(char):
        _query += char.toLowerCase();
        _scrollOffset = 0;
        _normalizeSelectionForQuery();
        return true;
      default:
        return true;
    }
  }

  @override
  List<String> render(int width, int height) {
    final safeWidth = max(3, width);
    final safeHeight = max(3, height);
    final border = renderBorder(
      PanelStyle.simple,
      safeWidth,
      safeHeight,
      _query.isEmpty ? 'SKILLS' : 'SKILLS /$_query',
    );
    final contentHeight = safeHeight - 2;
    final contentWidth = max(1, safeWidth - 4);
    _lastVisibleHeight = contentHeight;

    final leftWidth = contentWidth > 48
        ? (contentWidth * 0.35).floor().clamp(24, contentWidth - 24)
        : (contentWidth ~/ 2).clamp(1, contentWidth - 1);
    const dividerWidth = 1;
    final rightWidth = max(1, contentWidth - leftWidth - dividerWidth);

    final filtered = _filteredIndices();
    _normalizeSelectionForQuery();

    final listHeight = _visibleListHeight;
    final maxScroll = max(0, filtered.length - listHeight);
    _scrollOffset = min(_scrollOffset, maxScroll);

    final leftItems = _buildLeftItems(filtered);
    final selectedIndex = _selectedIndexForFiltered(filtered);
    final rightLines = _buildDetail(selectedIndex, rightWidth);

    final hasOverflow = filtered.length > listHeight;
    final totalPages =
        listHeight > 0 ? (filtered.length + listHeight - 1) ~/ listHeight : 1;
    final currentPage = (_scrollOffset ~/ max(listHeight, 1)) + 1;

    const divider = '\x1b[2m│\x1b[0m';
    const leftBorder = '\x1b[2m│\x1b[0m';
    const rightBorder = '\x1b[2m│\x1b[0m';

    final lines = <String>[];
    for (var row = 0; row < safeHeight; row++) {
      if (row == 0) {
        lines.add(border.first);
        continue;
      }
      if (row == safeHeight - 1) {
        if (!hasOverflow) {
          lines.add(border.last);
          continue;
        }
        final indicator = '$currentPage/$totalPages';
        final borderText = stripAnsi(border.last);
        final insertPos = borderText.length - indicator.length - 2;
        if (insertPos <= 0) {
          lines.add(border.last);
          continue;
        }
        final before =
            border.last.substring(0, _ansiIndex(border.last, insertPos));
        final after = border.last
            .substring(_ansiIndex(border.last, insertPos + indicator.length));
        lines.add('$before$indicator$after');
        continue;
      }

      final contentRow = row - 1;

      String leftContent;
      String rightContent;

      if (contentRow == 0) {
        leftContent =
            _padAnsi(_buildFilterRow(leftWidth, filtered.length), leftWidth);
        rightContent = _padAnsi(
          '\x1b[2mType to filter | Enter select | Esc close\x1b[0m',
          rightWidth,
        );
        lines.add('$leftBorder $leftContent$divider$rightContent $rightBorder');
        continue;
      }

      final leftPos = _scrollOffset + contentRow - 1;

      if (leftPos < leftItems.length) {
        final padded = _padAnsi(leftItems[leftPos], leftWidth);
        if (leftPos < filtered.length && filtered[leftPos] == selectedIndex) {
          leftContent = '\x1b[7m${stripAnsi(padded)}\x1b[27m';
        } else {
          leftContent = padded;
        }
      } else {
        leftContent = ' ' * leftWidth;
      }

      final detailRow = contentRow - 1;
      if (detailRow < rightLines.length) {
        rightContent = _padAnsi(rightLines[detailRow], rightWidth);
      } else {
        rightContent = ' ' * rightWidth;
      }

      lines.add('$leftBorder $leftContent$divider$rightContent $rightBorder');
    }

    return lines;
  }

  List<String> _buildLeftItems(List<int> filteredIndices) {
    const cyan = '\x1b[36m';
    const green = '\x1b[32m';
    const rst = '\x1b[0m';

    if (filteredIndices.isEmpty) {
      return ['\x1b[2mNo matching skills\x1b[0m'];
    }

    final filteredSkills = filteredIndices.map((i) => _skills[i]).toList();
    final maxNameLen = filteredSkills.fold<int>(
      0,
      (current, skill) =>
          skill.name.length > current ? skill.name.length : current,
    );

    return filteredSkills.map((skill) {
      final sourceTag = switch (skill.source) {
        SkillSource.project => '${green}project$rst',
        SkillSource.global => '${cyan}global$rst',
        SkillSource.custom => '${cyan}custom$rst',
      };
      return '${skill.name.padRight(maxNameLen)}  $sourceTag';
    }).toList(growable: false);
  }

  List<String> _buildDetail(int index, int width) {
    if (_skills.isEmpty || index < 0 || index >= _skills.length) {
      return ['No skills found.'];
    }
    final skill = _skills[index];
    final lines = <String>[];

    const bold = '\x1b[1m';
    const dim = '\x1b[2m';
    const label = '\x1b[32m';
    const rst = '\x1b[0m';

    lines.add('$bold${skill.name}$rst');
    lines.add('');
    lines.addAll(_wrapText(skill.description, width));
    lines.add('');
    lines.add('${label}Source$rst      $dim${skill.skillDir}$rst');
    if (skill.license != null) {
      lines.add('${label}License$rst    $dim${skill.license}$rst');
    }
    if (skill.compatibility != null) {
      lines.add('${label}Requires$rst   $dim${skill.compatibility}$rst');
    }
    for (final entry in skill.metadata.entries) {
      final key = entry.key[0].toUpperCase() + entry.key.substring(1);
      final pad = ' ' * max(1, 11 - key.length);
      lines.add('$label$key$rst$pad$dim${entry.value}$rst');
    }
    return lines;
  }

  String _buildFilterRow(int width, int filteredCount) {
    if (_skills.isEmpty) {
      return _padAnsi('\x1b[2mNo skills available\x1b[0m', width);
    }
    if (_query.isEmpty) {
      return _padAnsi(
          '\x1b[2m/ filter  (${_skills.length} skills)\x1b[0m', width);
    }
    return _padAnsi(
      '\x1b[2m/$_query  ($filteredCount/${_skills.length})\x1b[0m',
      width,
    );
  }

  String _padAnsi(String text, int width) {
    final truncated = ansiTruncate(text, width);
    final padLen = width - visibleLength(truncated);
    return '$truncated${' ' * max(0, padLen)}';
  }

  int get _visibleListHeight => max(1, _lastVisibleHeight - 1);

  List<int> _filteredIndices() {
    if (_skills.isEmpty) return const [];
    final query = _query.trim();
    if (query.isEmpty) {
      return List<int>.generate(_skills.length, (i) => i, growable: false);
    }
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return List<int>.generate(_skills.length, (i) => i).where((i) {
      final haystack = _skillSearchText(_skills[i]);
      for (final term in terms) {
        if (!haystack.contains(term)) return false;
      }
      return true;
    }).toList(growable: false);
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

  void _normalizeSelectionForQuery() {
    final filtered = _filteredIndices();
    if (filtered.isEmpty) {
      _scrollOffset = 0;
      return;
    }
    final selectedIndex = _selectedIndexForFiltered(filtered);
    _selectedIndex = selectedIndex;

    final selectedPos = _selectedPosition(filtered);
    final visibleHeight = _visibleListHeight;
    final maxScroll = max(0, filtered.length - visibleHeight);
    if (selectedPos < _scrollOffset) {
      _scrollOffset = selectedPos;
    } else if (selectedPos >= _scrollOffset + visibleHeight) {
      _scrollOffset = selectedPos - visibleHeight + 1;
    }
    _scrollOffset = _scrollOffset.clamp(0, maxScroll);
  }

  bool _isSearchChar(String char) {
    if (char.isEmpty) return false;
    final rune = char.runes.first;
    return rune >= 0x20 && rune != 0x7f;
  }

  String _skillSearchText(SkillMeta skill) {
    final metadata = skill.metadata.entries.map((entry) {
      return '${entry.key} ${entry.value}';
    }).join(' ');
    return '${skill.name} ${skill.description} ${skill.source.name} '
            '${skill.skillDir} $metadata'
        .toLowerCase();
  }

  List<String> _wrapText(String text, int width) {
    if (width <= 0) return <String>[text];
    final words = text.split(' ');
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      if (current.isEmpty) {
        current = word;
      } else if (current.length + 1 + word.length <= width) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  int _ansiIndex(String text, int visiblePos) {
    final ansiPattern = RegExp(r'\x1b\[[0-9;]*[a-zA-Z]');
    var visible = 0;
    var i = 0;
    while (i < text.length && visible < visiblePos) {
      final match = ansiPattern.matchAsPrefix(text, i);
      if (match != null) {
        i += match.group(0)!.length;
      } else {
        visible++;
        i++;
      }
    }
    return i;
  }
}
