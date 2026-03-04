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
  Completer<String?> _selectionCompleter = Completer<String?>();

  SkillsDockedPanel({
    required List<SkillMeta> skills,
    this.edge = DockEdge.right,
    this.mode = DockMode.floating,
    this.extent = 34,
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
    final visibleHeight = max(1, _lastVisibleHeight);
    final maxScroll = max(0, _skills.length - visibleHeight);
    _scrollOffset = _scrollOffset.clamp(0, maxScroll);
  }

  @override
  bool get visible => _visible;

  @override
  bool get hasFocus => _visible;

  @override
  void show() {
    _visible = true;
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

    final visibleHeight = max(_lastVisibleHeight, 1);
    final maxScroll = max(0, _skills.length - visibleHeight);

    switch (event) {
      case KeyEvent(key: Key.escape):
        dismiss();
        return true;
      case KeyEvent(key: Key.enter):
        if (_skills.isEmpty) {
          dismiss();
          return true;
        }
        final selected = _skills[_selectedIndex].name;
        if (!_selectionCompleter.isCompleted) {
          _selectionCompleter.complete(selected);
        }
        _visible = false;
        return true;
      case KeyEvent(key: Key.up):
        _selectedIndex = max(0, _selectedIndex - 1);
        if (_selectedIndex < _scrollOffset) {
          _scrollOffset = _selectedIndex;
        }
        return true;
      case KeyEvent(key: Key.down):
        _selectedIndex = min(max(0, _skills.length - 1), _selectedIndex + 1);
        if (_selectedIndex >= _scrollOffset + visibleHeight) {
          _scrollOffset = _selectedIndex - visibleHeight + 1;
        }
        return true;
      case KeyEvent(key: Key.pageUp):
        _selectedIndex = max(0, _selectedIndex - visibleHeight);
        _scrollOffset = max(0, _scrollOffset - visibleHeight);
        return true;
      case KeyEvent(key: Key.pageDown):
        _selectedIndex =
            min(max(0, _skills.length - 1), _selectedIndex + visibleHeight);
        _scrollOffset = min(maxScroll, _scrollOffset + visibleHeight);
        return true;
      default:
        return true;
    }
  }

  @override
  List<String> render(int width, int height) {
    final safeWidth = max(3, width);
    final safeHeight = max(3, height);
    final border =
        renderBorder(PanelStyle.simple, safeWidth, safeHeight, 'SKILLS');
    final contentHeight = safeHeight - 2;
    final contentWidth = max(1, safeWidth - 4);
    _lastVisibleHeight = contentHeight;

    final leftWidth = contentWidth > 48
        ? (contentWidth * 0.35).floor().clamp(24, contentWidth - 24)
        : (contentWidth ~/ 2).clamp(1, contentWidth - 1);
    const dividerWidth = 1;
    final rightWidth = max(1, contentWidth - leftWidth - dividerWidth);

    final maxScroll = max(0, _skills.length - contentHeight);
    _scrollOffset = min(_scrollOffset, maxScroll);

    final leftItems = _buildLeftItems();
    final rightLines = _buildDetail(_selectedIndex, rightWidth);

    final hasOverflow = _skills.length > contentHeight;
    final totalPages = contentHeight > 0
        ? (_skills.length + contentHeight - 1) ~/ contentHeight
        : 1;
    final currentPage = (_scrollOffset ~/ max(contentHeight, 1)) + 1;

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
      final leftIndex = _scrollOffset + contentRow;

      String leftContent;
      if (leftIndex < leftItems.length) {
        final truncated = ansiTruncate(leftItems[leftIndex], leftWidth);
        final padLen = leftWidth - visibleLength(truncated);
        final padded = '$truncated${' ' * max(0, padLen)}';
        if (leftIndex == _selectedIndex) {
          leftContent = '\x1b[7m${stripAnsi(padded)}\x1b[27m';
        } else {
          leftContent = padded;
        }
      } else {
        leftContent = ' ' * leftWidth;
      }

      String rightContent;
      if (contentRow < rightLines.length) {
        final truncated = ansiTruncate(rightLines[contentRow], rightWidth);
        final padLen = rightWidth - visibleLength(truncated);
        rightContent = '$truncated${' ' * max(0, padLen)}';
      } else {
        rightContent = ' ' * rightWidth;
      }

      lines.add('$leftBorder $leftContent$divider$rightContent $rightBorder');
    }

    return lines;
  }

  List<String> _buildLeftItems() {
    const cyan = '\x1b[36m';
    const green = '\x1b[32m';
    const rst = '\x1b[0m';

    if (_skills.isEmpty) return ['No skills available'];

    final maxNameLen = _skills.fold<int>(
      0,
      (current, skill) =>
          skill.name.length > current ? skill.name.length : current,
    );

    return _skills.map((skill) {
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
