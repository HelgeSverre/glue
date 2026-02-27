import 'dart:io';

import 'package:path/path.dart' as p;

import '../rendering/ansi_utils.dart';

class _Candidate {
  final String displayName;
  final String completionPath;
  final bool isDirectory;
  _Candidate(this.displayName, this.completionPath, this.isDirectory);
}

class AtFileHint {
  final String cwd;
  static const maxVisible = 8;

  bool _active = false;
  int _selected = 0;
  int _tokenStart = 0;
  List<_Candidate> _matches = [];

  AtFileHint({String? cwd}) : cwd = cwd ?? Directory.current.path;

  bool get active => _active;
  int get selected => _selected;
  int get matchCount => _matches.length;
  int get tokenStart => _tokenStart;

  int get overlayHeight {
    if (!_active || _matches.isEmpty) return 0;
    return _matches.length > maxVisible ? maxVisible : _matches.length;
  }

  void dismiss() {
    _active = false;
    _matches = [];
    _selected = 0;
    _tokenStart = 0;
  }

  void update(String buffer, int cursor) {
    // Walk backward from cursor to find @
    final before = buffer.substring(0, cursor);
    final atIndex = before.lastIndexOf('@');
    if (atIndex < 0) {
      dismiss();
      return;
    }

    // @ must be at start or preceded by whitespace (not email-like)
    if (atIndex > 0 && before[atIndex - 1] != ' ') {
      dismiss();
      return;
    }

    _tokenStart = atIndex;
    final partial = before.substring(atIndex + 1);

    // Split into directory part and filename prefix
    final lastSlash = partial.lastIndexOf('/');
    final dirPart = lastSlash >= 0 ? partial.substring(0, lastSlash + 1) : '';
    final prefix = lastSlash >= 0 ? partial.substring(lastSlash + 1) : partial;

    final resolvedDir = p.join(cwd, dirPart);
    final dir = Directory(resolvedDir);
    if (!dir.existsSync()) {
      dismiss();
      return;
    }

    final candidates = <_Candidate>[];
    try {
      final entries = dir.listSync();
      for (final entry in entries) {
        final name = p.basename(entry.path);
        // Skip hidden files
        if (name.startsWith('.')) continue;

        final isDir = entry is Directory;
        final displayName = isDir ? '$name/' : name;

        // Fuzzy contains match on name
        if (prefix.isNotEmpty &&
            !name.toLowerCase().contains(prefix.toLowerCase())) {
          continue;
        }

        final completionPath = '$dirPart$displayName';
        candidates.add(_Candidate(displayName, completionPath, isDir));
      }
    } on FileSystemException {
      dismiss();
      return;
    }

    if (candidates.isEmpty) {
      dismiss();
      return;
    }

    // Sort: directories first, then alphabetical
    candidates.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

    // Cap at 20
    if (candidates.length > 20) {
      candidates.removeRange(20, candidates.length);
    }

    _active = true;
    _matches = candidates;
    _selected = _selected.clamp(0, _matches.length - 1);
  }

  void moveUp() {
    if (!_active || _matches.isEmpty) return;
    _selected = (_selected - 1) % _matches.length;
  }

  void moveDown() {
    if (!_active || _matches.isEmpty) return;
    _selected = (_selected + 1) % _matches.length;
  }

  String? accept() {
    if (!_active || _matches.isEmpty) return null;
    final candidate = _matches[_selected];
    final path = candidate.completionPath;
    dismiss();
    if (path.contains(' ')) {
      return '@"$path"';
    }
    return '@$path';
  }

  List<String> render(int width) {
    if (!_active || _matches.isEmpty) return [];

    final visible = _matches.length > maxVisible
        ? _matches.sublist(0, maxVisible)
        : _matches;

    const bgDim = '\x1b[48;5;236m\x1b[37m';
    const bgSel = '\x1b[48;5;24m\x1b[97m';
    const rst = '\x1b[0m';

    final lines = <String>[];
    for (var i = 0; i < visible.length; i++) {
      final c = visible[i];
      final bg = i == _selected ? bgSel : bgDim;
      final icon = c.isDirectory ? '  📁 ' : '     ';
      final content = '$icon${c.displayName}';
      final truncated = visibleLength(content) > width
          ? ansiTruncate(content, width)
          : content;
      final padCount = width - visibleLength(truncated);
      lines.add('$bg$truncated${' ' * (padCount > 0 ? padCount : 0)}$rst');
    }

    return lines;
  }
}
