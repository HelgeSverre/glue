import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/constants.dart';
import '../rendering/ansi_utils.dart';

class _Candidate {
  final String displayName;
  final String completionPath;
  final bool isDirectory;
  _Candidate(this.displayName, this.completionPath, this.isDirectory);
}

class _TreeEntry {
  final String relPath;
  final String name;
  final bool isDirectory;
  _TreeEntry(this.relPath, this.name, this.isDirectory);
}

class AtFileHint {
  final String cwd;
  static const maxVisible = AppConstants.maxVisibleDropdownItems;

  bool _active = false;
  int _selected = 0;
  int _tokenStart = 0;
  List<_Candidate> _matches = [];

  String? _cachedDirPath;
  List<FileSystemEntity>? _cachedEntries;
  DateTime _cachedAt = DateTime(0);

  List<_TreeEntry>? _cachedTree;
  DateTime _cachedTreeAt = DateTime(0);

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
    final before = buffer.substring(0, cursor);
    final atIndex = before.lastIndexOf('@');
    if (atIndex < 0) {
      dismiss();
      return;
    }

    if (atIndex > 0 && before[atIndex - 1] != ' ') {
      dismiss();
      return;
    }

    _tokenStart = atIndex;
    final partial = before.substring(atIndex + 1);

    final lastSlash = partial.lastIndexOf('/');
    final dirPart = lastSlash >= 0 ? partial.substring(0, lastSlash + 1) : '';
    final prefix = lastSlash >= 0 ? partial.substring(lastSlash + 1) : partial;

    if (lastSlash >= 0) {
      _buildDirCandidates(dirPart, prefix);
    } else if (prefix.isEmpty) {
      _buildDirCandidates('', '');
    } else {
      _buildRecursiveCandidates(prefix);
    }
  }

  void _buildDirCandidates(String dirPart, String prefix) {
    final resolvedDir = p.join(cwd, dirPart);
    final dir = Directory(resolvedDir);
    if (!dir.existsSync()) {
      dismiss();
      return;
    }

    final candidates = <_Candidate>[];
    try {
      final entries = _listDir(resolvedDir);
      for (final entry in entries) {
        final name = p.basename(entry.path);
        if (name.startsWith('.')) continue;

        final isDir = entry is Directory;
        final displayName = isDir ? '$name/' : name;

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

    candidates.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

    if (candidates.length > 20) {
      candidates.removeRange(20, candidates.length);
    }

    _active = true;
    _matches = candidates;
    _selected = _selected.clamp(0, _matches.length - 1);
  }

  void _buildRecursiveCandidates(String prefix) {
    final prefixLower = prefix.toLowerCase();
    final candidates = <_Candidate>[];

    try {
      final cwdEntries = _listDir(cwd);
      for (final entry in cwdEntries) {
        final name = p.basename(entry.path);
        if (name.startsWith('.')) continue;
        final isDir = entry is Directory;
        if (!name.toLowerCase().contains(prefixLower)) continue;
        final displayName = isDir ? '$name/' : name;
        candidates.add(_Candidate(displayName, displayName, isDir));
      }
    } on FileSystemException {
      // ignore
    }

    final tree = _listTree();
    for (final entry in tree) {
      if (!entry.name.toLowerCase().contains(prefixLower)) continue;
      if (!entry.relPath.contains('/') ||
          (entry.isDirectory &&
              entry.relPath.indexOf('/') == entry.relPath.length - 1)) {
        continue;
      }
      candidates
          .add(_Candidate(entry.relPath, entry.relPath, entry.isDirectory));
    }

    if (candidates.isEmpty) {
      dismiss();
      return;
    }

    candidates.sort((a, b) {
      final aScore = _matchScore(a.displayName, prefixLower);
      final bScore = _matchScore(b.displayName, prefixLower);
      if (aScore != bScore) return aScore.compareTo(bScore);
      final aLen = a.completionPath.length;
      final bLen = b.completionPath.length;
      if (aLen != bLen) return aLen.compareTo(bLen);
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

    if (candidates.length > 20) {
      candidates.removeRange(20, candidates.length);
    }

    _active = true;
    _matches = candidates;
    _selected = _selected.clamp(0, _matches.length - 1);
  }

  int _matchScore(String displayName, String prefixLower) {
    final raw = displayName.endsWith('/')
        ? displayName.substring(0, displayName.length - 1)
        : displayName;
    final name = p.basename(raw).toLowerCase();
    if (name == prefixLower) return 0;
    if (name.startsWith(prefixLower)) return 1;
    return 2;
  }

  List<_TreeEntry> _listTree() {
    final now = DateTime.now();
    if (_cachedTree != null &&
        now.difference(_cachedTreeAt).inSeconds <
            AppConstants.atFileHintCacheTtlSeconds) {
      return _cachedTree!;
    }

    final entries = <_TreeEntry>[];
    final queue = <(String, String, int)>[(cwd, '', 1)];

    while (queue.isNotEmpty &&
        entries.length < AppConstants.atFileHintMaxTreeEntries) {
      final (dirAbs, relPrefix, depth) = queue.removeAt(0);
      List<FileSystemEntity> children;
      try {
        children = Directory(dirAbs).listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final child in children) {
        final name = p.basename(child.path);
        if (name.startsWith('.')) continue;
        final isDir = child is Directory;
        final relPath = relPrefix.isEmpty ? name : '$relPrefix/$name';
        entries.add(_TreeEntry(
          isDir ? '$relPath/' : relPath,
          name,
          isDir,
        ));
        if (isDir && depth <= AppConstants.atFileHintMaxTreeDepth) {
          queue.add((child.path, relPath, depth + 1));
        }
        if (entries.length >= AppConstants.atFileHintMaxTreeEntries) break;
      }
    }

    _cachedTree = entries;
    _cachedTreeAt = now;
    return entries;
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

  List<FileSystemEntity> _listDir(String dirPath) {
    final now = DateTime.now();
    if (dirPath == _cachedDirPath &&
        _cachedEntries != null &&
        now.difference(_cachedAt).inSeconds <
            AppConstants.atFileHintCacheTtlSeconds) {
      return _cachedEntries!;
    }
    _cachedDirPath = dirPath;
    _cachedEntries = Directory(dirPath).listSync();
    _cachedAt = now;
    return _cachedEntries!;
  }
}
