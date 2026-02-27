# `@file` Reference Expansion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow users to type `@path/to/file` in the input buffer to inline file contents into the message sent to the agent, with filesystem autocomplete triggered by `@` after a space.

**Architecture:** Two new components: (1) `FileExpander` — a stateless utility that finds `@path` tokens and replaces them with fenced file contents before sending to the LLM, and (2) `AtFileHint` — an autocomplete overlay (same pattern as `SlashAutocomplete`) that shows filesystem completions when typing after `@`. The overlay slot is shared — slash autocomplete takes priority when the buffer starts with `/`.

**Tech Stack:** Dart 3.4+, dart:io (file reads + directory listing), package:path

---

## Task 1: `FileExpander` utility — expansion logic

**Files:**
- Create: `lib/src/input/file_expander.dart`
- Create: `test/input/file_expander_test.dart`

### Step 1: Write failing tests

Create `test/input/file_expander_test.dart`:

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:glue/src/input/file_expander.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('file_expander_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('extractFileRefs', () {
    test('finds single @path token', () {
      final refs = extractFileRefs('look at @foo.dart please');
      expect(refs, ['foo.dart']);
    });

    test('finds multiple tokens', () {
      final refs = extractFileRefs('compare @a.dart and @b.dart');
      expect(refs, ['a.dart', 'b.dart']);
    });

    test('returns empty for no tokens', () {
      expect(extractFileRefs('no references here'), isEmpty);
    });

    test('ignores @ at start of word without space before (email-like)', () {
      expect(extractFileRefs('user@host.com'), isEmpty);
    });

    test('recognizes @ at start of input', () {
      final refs = extractFileRefs('@foo.dart is interesting');
      expect(refs, ['foo.dart']);
    });

    test('finds token with subdirectories', () {
      final refs = extractFileRefs('read @lib/src/agent/core.dart');
      expect(refs, ['lib/src/agent/core.dart']);
    });

    test('finds quoted path with spaces', () {
      final refs = extractFileRefs('read @"path with spaces/file.dart"');
      expect(refs, ['path with spaces/file.dart']);
    });

    test('finds single-quoted path', () {
      final refs = extractFileRefs("read @'my file.dart'");
      expect(refs, ['my file.dart']);
    });
  });

  group('expandFileRefs', () {
    test('expands single file reference', () {
      final file = File(p.join(tempDir.path, 'hello.dart'));
      file.writeAsStringSync('void main() {}');

      final result = expandFileRefs(
        'explain @hello.dart',
        cwd: tempDir.path,
      );
      expect(result, contains('[hello.dart]'));
      expect(result, contains('```dart'));
      expect(result, contains('void main() {}'));
    });

    test('expands multiple references', () {
      File(p.join(tempDir.path, 'a.dart')).writeAsStringSync('a');
      File(p.join(tempDir.path, 'b.dart')).writeAsStringSync('b');

      final result = expandFileRefs(
        'compare @a.dart and @b.dart',
        cwd: tempDir.path,
      );
      expect(result, contains('[a.dart]'));
      expect(result, contains('[b.dart]'));
    });

    test('leaves missing file as-is with warning', () {
      final result = expandFileRefs(
        'read @missing.dart',
        cwd: tempDir.path,
      );
      expect(result, contains('@missing.dart'));
      expect(result, contains('not found'));
    });

    test('returns input unchanged when no refs', () {
      final result = expandFileRefs('no refs here', cwd: tempDir.path);
      expect(result, 'no refs here');
    });

    test('uses correct language tag for extension', () {
      File(p.join(tempDir.path, 'data.json')).writeAsStringSync('{}');
      final result = expandFileRefs('@data.json', cwd: tempDir.path);
      expect(result, contains('```json'));
    });

    test('skips files larger than 100KB', () {
      final bigFile = File(p.join(tempDir.path, 'big.dart'));
      bigFile.writeAsStringSync('x' * (101 * 1024));

      final result = expandFileRefs(
        'read @big.dart',
        cwd: tempDir.path,
      );
      expect(result, contains('@big.dart'));
      expect(result, contains('too large'));
    });

    test('does not expand email addresses', () {
      final result = expandFileRefs(
        'email me at user@host.com',
        cwd: tempDir.path,
      );
      expect(result, 'email me at user@host.com');
    });

    test('expands file in subdirectory', () {
      final subDir = Directory(p.join(tempDir.path, 'lib', 'src'));
      subDir.createSync(recursive: true);
      File(p.join(subDir.path, 'foo.dart')).writeAsStringSync('foo');

      final result = expandFileRefs(
        'read @lib/src/foo.dart',
        cwd: tempDir.path,
      );
      expect(result, contains('[lib/src/foo.dart]'));
      expect(result, contains('foo'));
    });

    test('handles file containing triple backticks', () {
      final file = File(p.join(tempDir.path, 'meta.md'));
      file.writeAsStringSync('some\n```\ncode\n```\nhere');

      final result = expandFileRefs('@meta.md', cwd: tempDir.path);
      // Should use longer fence to avoid breaking
      expect(result, contains('````'));
    });

    test('expands quoted path with spaces', () {
      final dir = Directory(p.join(tempDir.path, 'my dir'));
      dir.createSync();
      File(p.join(dir.path, 'file.dart')).writeAsStringSync('spaced');

      final result = expandFileRefs(
        'read @"my dir/file.dart"',
        cwd: tempDir.path,
      );
      expect(result, contains('[my dir/file.dart]'));
      expect(result, contains('spaced'));
    });
  });
}
```

### Step 2: Run tests to verify they fail

Run: `dart test test/input/file_expander_test.dart`
Expected: FAIL — file doesn't exist yet

### Step 3: Implement `FileExpander`

Create `lib/src/input/file_expander.dart`:

```dart
import 'dart:io';
import 'package:path/path.dart' as p;

/// Token regex: `@` preceded by start-of-string or whitespace, followed by
/// either a quoted path or an unquoted path (stops at whitespace).
final _refPattern = RegExp(
  r'''(?:^|(?<=\s))@(?:"([^"]+)"|'([^']+)'|([\w./\-]+))''',
);

/// Maximum file size to inline (100 KB).
const _maxFileSize = 100 * 1024;

/// Extension → fenced code block language tag.
const _langTags = <String, String>{
  '.dart': 'dart',
  '.json': 'json',
  '.yaml': 'yaml',
  '.yml': 'yaml',
  '.md': 'markdown',
  '.sh': 'sh',
  '.bash': 'bash',
  '.ts': 'typescript',
  '.js': 'javascript',
  '.py': 'python',
  '.html': 'html',
  '.css': 'css',
  '.sql': 'sql',
  '.xml': 'xml',
  '.toml': 'toml',
  '.rs': 'rust',
  '.go': 'go',
  '.rb': 'ruby',
  '.java': 'java',
  '.kt': 'kotlin',
  '.swift': 'swift',
  '.c': 'c',
  '.cpp': 'cpp',
  '.h': 'c',
};

/// Extract all `@<path>` tokens from [input].
///
/// Returns the path strings (without the `@` prefix or quotes).
/// Only matches when `@` is at start of input or preceded by whitespace
/// (avoids matching emails like `user@host.com`).
List<String> extractFileRefs(String input) {
  return _refPattern.allMatches(input).map((m) {
    // Group 1: double-quoted, Group 2: single-quoted, Group 3: unquoted
    return m.group(1) ?? m.group(2) ?? m.group(3)!;
  }).toList();
}

/// Expand all `@<path>` tokens in [input] by replacing each with the
/// file's contents in a fenced code block.
///
/// - Missing files: token left as-is with `[not found]` appended.
/// - Files > 100 KB: token left as-is with `[too large]` appended.
/// - The fenced block uses a language tag based on file extension.
/// - If the file contains triple backticks, a longer fence is used.
String expandFileRefs(String input, {String? cwd}) {
  final basePath = cwd ?? Directory.current.path;

  return input.replaceAllMapped(_refPattern, (m) {
    final token = m.group(0)!;
    final path = m.group(1) ?? m.group(2) ?? m.group(3)!;
    final resolved = p.normalize(p.join(basePath, path));
    final file = File(resolved);

    if (!file.existsSync()) {
      return '$token [not found]';
    }

    final stat = file.statSync();
    if (stat.size > _maxFileSize) {
      return '$token [too large: ${(stat.size / 1024).toStringAsFixed(0)} KB]';
    }

    final contents = file.readAsStringSync();
    final ext = p.extension(path).toLowerCase();
    final lang = _langTags[ext] ?? '';

    // Use a fence longer than any consecutive backtick run in the file.
    var fenceLen = 3;
    final backtickRuns = RegExp(r'`+').allMatches(contents);
    for (final run in backtickRuns) {
      if (run.group(0)!.length >= fenceLen) {
        fenceLen = run.group(0)!.length + 1;
      }
    }
    final fence = '`' * fenceLen;

    return '\n\n[$path]\n$fence$lang\n$contents\n$fence';
  });
}
```

### Step 4: Run tests

Run: `dart analyze && dart test test/input/file_expander_test.dart`
Expected: All pass

### Step 5: Commit

```bash
git add lib/src/input/file_expander.dart test/input/file_expander_test.dart
git commit -m "feat: add FileExpander utility for @file reference expansion"
```

---

## Task 2: Wire expansion into App submit flow

**Files:**
- Modify: `lib/src/app.dart` (lines 437-448 `_handleAppEvent`, lines 467-489 `_startAgent`)
- Modify: `lib/glue.dart`

### Step 1: Import file_expander in app.dart

Add to imports:
```dart
import 'input/file_expander.dart';
```

### Step 2: Update `_startAgent` to accept separate display and expanded text

Change `_startAgent` (line 467):

```dart
void _startAgent(String displayMessage, {String? expandedMessage}) {
  _blocks.add(_ConversationEntry.user(displayMessage));
  _mode = AppMode.streaming;
  _streamingText = '';
  _render();

  final stream = agent.run(expandedMessage ?? displayMessage);
```

### Step 3: Call expansion on submit

In `_handleAppEvent`, the `UserSubmit` case (line 439):

```dart
case UserSubmit(:final text):
  if (text.startsWith('/')) {
    final result = _commands.execute(text);
    if (result != null && result.isNotEmpty) {
      _blocks.add(_ConversationEntry.system(result));
    }
    _render();
  } else {
    final expanded = expandFileRefs(text);
    _startAgent(text, expandedMessage: expanded != text ? expanded : null);
  }
```

### Step 4: Export from barrel

Add to `lib/glue.dart`:
```dart
export 'src/input/file_expander.dart' show expandFileRefs, extractFileRefs;
```

### Step 5: Run tests

Run: `dart analyze && dart test`
Expected: All pass

### Step 6: Commit

```bash
git add lib/src/app.dart lib/glue.dart
git commit -m "feat: expand @file references on submit, show raw text in UI"
```

---

## Task 3: `AtFileHint` autocomplete overlay

**Files:**
- Create: `lib/src/ui/at_file_hint.dart`
- Create: `test/ui/at_file_hint_test.dart`

### Step 1: Write failing tests

Create `test/ui/at_file_hint_test.dart`:

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:glue/src/ui/at_file_hint.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('at_file_hint_test_');
    // Create test file structure.
    File(p.join(tempDir.path, 'main.dart')).writeAsStringSync('');
    File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('');
    File(p.join(tempDir.path, 'README.md')).writeAsStringSync('');
    Directory(p.join(tempDir.path, 'lib')).createSync();
    File(p.join(tempDir.path, 'lib', 'app.dart')).writeAsStringSync('');
    File(p.join(tempDir.path, 'lib', 'utils.dart')).writeAsStringSync('');
    Directory(p.join(tempDir.path, 'my dir')).createSync();
    File(p.join(tempDir.path, 'my dir', 'spaced.dart')).writeAsStringSync('');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('AtFileHint', () {
    late AtFileHint hint;

    setUp(() {
      hint = AtFileHint(cwd: tempDir.path);
    });

    test('starts inactive', () {
      expect(hint.active, isFalse);
      expect(hint.overlayHeight, 0);
    });

    test('activates on space-@ prefix', () {
      hint.update('read @', 6);
      expect(hint.active, isTrue);
      expect(hint.matchCount, greaterThan(0));
    });

    test('activates on @ at start of input', () {
      hint.update('@', 1);
      expect(hint.active, isTrue);
    });

    test('does not activate on @ mid-word (email-like)', () {
      hint.update('user@', 5);
      expect(hint.active, isFalse);
    });

    test('filters by partial filename', () {
      hint.update('read @main', 10);
      expect(hint.active, isTrue);
      expect(hint.matchCount, 1);
    });

    test('filters by subdirectory prefix', () {
      hint.update('@lib/', 5);
      expect(hint.active, isTrue);
      // Should show app.dart, utils.dart inside lib/
      expect(hint.matchCount, 2);
    });

    test('dismisses when no matches', () {
      hint.update('@zzzznothing', 12);
      expect(hint.active, isFalse);
    });

    test('moveDown wraps around', () {
      hint.update('@', 1);
      final count = hint.matchCount;
      for (var i = 0; i < count; i++) {
        hint.moveDown();
      }
      expect(hint.selected, 0);
    });

    test('moveUp wraps around', () {
      hint.update('@', 1);
      hint.moveUp();
      expect(hint.selected, hint.matchCount - 1);
    });

    test('accept returns completed path', () {
      hint.update('@main', 5);
      final result = hint.accept();
      expect(result, isNotNull);
      expect(result, contains('main.dart'));
    });

    test('accept auto-quotes paths with spaces', () {
      hint.update('@my', 3);
      // "my dir/" should be one of the matches
      expect(hint.active, isTrue);
      // Navigate to "my dir/"
      String? result;
      for (var i = 0; i < hint.matchCount; i++) {
        hint.update('@my', 3);
        for (var j = 0; j < i; j++) {
          hint.moveDown();
        }
        result = hint.accept();
        if (result != null && result.contains('my dir')) break;
      }
      expect(result, isNotNull);
      // Should be quoted since it has a space
      expect(result, contains('"'));
    });

    test('dismiss clears state', () {
      hint.update('@', 1);
      hint.dismiss();
      expect(hint.active, isFalse);
      expect(hint.matchCount, 0);
    });

    test('render returns correct line count', () {
      hint.update('@', 1);
      final lines = hint.render(80);
      expect(lines.length, hint.overlayHeight);
    });

    test('overlayHeight capped at maxVisible', () {
      // Create many files
      for (var i = 0; i < 20; i++) {
        File(p.join(tempDir.path, 'file$i.dart')).writeAsStringSync('');
      }
      hint.update('@file', 5);
      expect(hint.overlayHeight, lessThanOrEqualTo(AtFileHint.maxVisible));
    });

    test('directories shown with trailing slash', () {
      hint.update('@lib', 4);
      final result = hint.accept();
      expect(result, isNotNull);
      expect(result, endsWith('/'));
    });
  });
}
```

### Step 2: Run tests to verify they fail

Run: `dart test test/ui/at_file_hint_test.dart`
Expected: FAIL — file doesn't exist yet

### Step 3: Implement `AtFileHint`

Create `lib/src/ui/at_file_hint.dart`:

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import '../rendering/ansi_utils.dart';

class _Candidate {
  final String display;
  final String completionPath;
  final bool isDirectory;
  _Candidate(this.display, this.completionPath, {this.isDirectory = false});
}

/// Autocomplete overlay for `@file` references.
///
/// Activates when the cursor is immediately after `@` (preceded by
/// whitespace or at start of input). Lists matching files/directories
/// under [cwd], filtering by the partial path typed after `@`.
///
/// Same API contract as [SlashAutocomplete] so App can use them
/// interchangeably.
class AtFileHint {
  final String cwd;

  bool _active = false;
  int _selected = 0;
  List<_Candidate> _matches = [];

  /// Start position of the `@token` in the editor buffer.
  int _tokenStart = 0;

  static const maxVisible = 8;

  AtFileHint({String? cwd}) : cwd = cwd ?? Directory.current.path;

  bool get active => _active;
  int get selected => _selected;
  int get matchCount => _matches.length;

  void dismiss() {
    _active = false;
    _matches = [];
    _selected = 0;
  }

  /// Update state based on current editor [buffer] and [cursor].
  ///
  /// Activates when cursor is inside or right after an `@token` where
  /// `@` is at start of input or preceded by whitespace.
  void update(String buffer, int cursor) {
    // Walk backwards from cursor to find @ token.
    final tokenInfo = _findAtToken(buffer, cursor);
    if (tokenInfo == null) {
      dismiss();
      return;
    }

    _tokenStart = tokenInfo.start;
    final partial = tokenInfo.path;

    // Split into directory part and filename prefix.
    final candidates = _listCandidates(partial);

    if (candidates.isEmpty) {
      dismiss();
      return;
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

  /// Accept current selection. Returns the full text to replace the
  /// `@token` with in the editor buffer (e.g. `@lib/src/app.dart`).
  ///
  /// Paths containing spaces are automatically quoted: `@"my dir/file.dart"`.
  /// Directory paths end with `/` so the user can keep drilling down.
  String? accept() {
    if (!_active || _matches.isEmpty) return null;
    final candidate = _matches[_selected];
    dismiss();
    final path = candidate.completionPath;
    if (path.contains(' ')) {
      return '@"$path"';
    }
    return '@$path';
  }

  /// The start position of the current `@token` in the editor buffer.
  int get tokenStart => _tokenStart;

  /// The end position (cursor position) when accept was called.
  /// The caller should replace buffer[tokenStart..cursor] with the
  /// accepted value.

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
      final icon = c.isDirectory ? '📁 ' : '   ';
      final content = '  $icon${c.display}';
      final truncated = visibleLength(content) > width
          ? ansiTruncate(content, width)
          : content;
      final padCount = width - visibleLength(truncated);
      lines.add('$bg$truncated${' ' * (padCount > 0 ? padCount : 0)}$rst');
    }
    return lines;
  }

  int get overlayHeight {
    if (!_active || _matches.isEmpty) return 0;
    return _matches.length > maxVisible ? maxVisible : _matches.length;
  }

  // ── Private helpers ──────────────────────────────────────────────────

  /// Find the `@token` at the cursor position.
  ///
  /// Returns null if cursor is not inside/after a valid `@` reference
  /// (i.e. `@` must be at start or preceded by whitespace).
  _AtToken? _findAtToken(String buffer, int cursor) {
    // Walk backwards from cursor to find @.
    var i = cursor - 1;
    while (i >= 0 && buffer[i] != '@' && buffer[i] != ' ') {
      i--;
    }
    if (i < 0 || buffer[i] != '@') return null;

    final atPos = i;

    // @ must be at start or preceded by whitespace.
    if (atPos > 0 && buffer[atPos - 1] != ' ') return null;

    final path = buffer.substring(atPos + 1, cursor);
    return _AtToken(start: atPos, path: path);
  }

  List<_Candidate> _listCandidates(String partial) {
    String dirPath;
    String prefix;

    if (partial.contains('/')) {
      final lastSlash = partial.lastIndexOf('/');
      dirPath = p.join(cwd, partial.substring(0, lastSlash));
      prefix = partial.substring(lastSlash + 1).toLowerCase();
    } else {
      dirPath = cwd;
      prefix = partial.toLowerCase();
    }

    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];

    final candidates = <_Candidate>[];
    try {
      final entries = dir.listSync();
      entries.sort((a, b) {
        // Directories first, then alphabetical.
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
        return p.basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });

      for (final entry in entries) {
        final name = p.basename(entry.path);
        // Skip hidden files.
        if (name.startsWith('.')) continue;

        if (!name.toLowerCase().contains(prefix)) continue;

        final isDir = entry is Directory;
        final relativePath = partial.contains('/')
            ? '${partial.substring(0, partial.lastIndexOf('/') + 1)}$name${isDir ? '/' : ''}'
            : '$name${isDir ? '/' : ''}';

        candidates.add(_Candidate(
          '$name${isDir ? '/' : ''}',
          relativePath,
          isDirectory: isDir,
        ));

        if (candidates.length >= 20) break;
      }
    } catch (_) {
      return [];
    }

    return candidates;
  }
}

class _AtToken {
  final int start;
  final String path;
  _AtToken({required this.start, required this.path});
}
```

### Step 4: Run tests

Run: `dart analyze && dart test test/ui/at_file_hint_test.dart`
Expected: All pass

### Step 5: Commit

```bash
git add lib/src/ui/at_file_hint.dart test/ui/at_file_hint_test.dart
git commit -m "feat: add AtFileHint autocomplete overlay for @file references"
```

---

## Task 4: Wire `AtFileHint` into App

**Files:**
- Modify: `lib/src/app.dart`
- Modify: `lib/glue.dart`

### Step 1: Add `_atHint` field and instantiate

In `App` fields (after `_autocomplete`):
```dart
late final AtFileHint _atHint;
```

In constructor body (after `_autocomplete = ...`):
```dart
_atHint = AtFileHint();
```

Add import at top of app.dart:
```dart
import 'ui/at_file_hint.dart';
```

### Step 2: Add overlay arbitration in input handling

In `_handleTerminalEvent`, after the `SlashAutocomplete` intercept block (after line 405), add an `AtFileHint` intercept block with the same pattern:

```dart
// @file hint intercepts keys when active.
if (_atHint.active) {
  if (event case KeyEvent(key: Key.up)) {
    _atHint.moveUp();
    _render();
    return;
  }
  if (event case KeyEvent(key: Key.down)) {
    _atHint.moveDown();
    _render();
    return;
  }
  if (event case KeyEvent(key: Key.enter) || KeyEvent(key: Key.tab)) {
    final accepted = _atHint.accept();
    if (accepted != null) {
      // Replace @token in buffer with accepted path.
      final buf = editor.text;
      final before = buf.substring(0, _atHint.tokenStart);
      final after = buf.substring(editor.cursor);
      editor.setText('$before$accepted$after',
          cursor: before.length + accepted.length);
    }
    _render();
    return;
  }
  if (event case KeyEvent(key: Key.escape)) {
    _atHint.dismiss();
    _render();
    return;
  }
}
```

### Step 3: Update `InputAction.changed` handler to update both overlays

In the `InputAction.changed` case (line 418), update both overlays — slash autocomplete takes priority:

```dart
case InputAction.changed:
  _autocomplete.update(editor.text, editor.cursor);
  if (!_autocomplete.active) {
    _atHint.update(editor.text, editor.cursor);
  } else {
    _atHint.dismiss();
  }
  _render();
```

### Step 4: Dismiss `_atHint` on submit

In the `InputAction.submit` case (line 410):
```dart
case InputAction.submit:
  _autocomplete.dismiss();
  _atHint.dismiss();
  final text = editor.lastSubmitted;
```

### Step 5: Update `_doRender` for overlay arbitration

In `_doRender`, replace the overlay section (lines 694-716):

```dart
// 2. Reserve overlay space for autocomplete (before computing viewport).
final activeOverlay = _autocomplete.active
    ? _autocomplete
    : _atHint.active
        ? _atHint
        : null;
layout.setOverlayHeight(activeOverlay != null
    ? (activeOverlay == _autocomplete
        ? _autocomplete.overlayHeight
        : _atHint.overlayHeight)
    : 0);
```

And the overlay painting section:
```dart
// 4. Autocomplete / @file overlay.
if (_autocomplete.active) {
  layout.paintOverlay(_autocomplete.render(terminal.columns));
} else if (_atHint.active) {
  layout.paintOverlay(_atHint.render(terminal.columns));
} else {
  layout.paintOverlay([]);
}
```

### Step 6: Export from barrel

Add to `lib/glue.dart`:
```dart
export 'src/ui/at_file_hint.dart' show AtFileHint;
```

### Step 7: Run tests

Run: `dart analyze && dart test`
Expected: All pass

### Step 8: Commit

```bash
git add lib/src/app.dart lib/glue.dart
git commit -m "feat: wire AtFileHint overlay into App with overlay arbitration"
```

---

## Execution Order

Tasks are sequential — each depends on the previous:

1. **Task 1:** `FileExpander` utility (pure logic, fully testable)
2. **Task 2:** Wire expansion into App submit
3. **Task 3:** `AtFileHint` autocomplete overlay (independent widget, fully testable)
4. **Task 4:** Wire `AtFileHint` into App

---

## File Changelist

| File | Change |
|---|---|
| `lib/src/input/file_expander.dart` | **New** — `expandFileRefs`, `extractFileRefs` |
| `lib/src/ui/at_file_hint.dart` | **New** — `AtFileHint` overlay |
| `lib/src/app.dart` | **Modified** — expand on submit, wire `AtFileHint` overlay |
| `lib/glue.dart` | **Modified** — export new types |
| `test/input/file_expander_test.dart` | **New** — expansion tests |
| `test/ui/at_file_hint_test.dart` | **New** — overlay tests |

---

## Design Decisions

- **`@` trigger requires preceding space or start-of-input** — avoids false positives on emails and `@` in code snippets.
- **Auto-quoting paths with spaces** — `@"my dir/file.dart"` on accept from autocomplete; quoted paths also supported in manual input.
- **Fuzzy matching uses `contains`** not `startsWith` — matches `@core` to `agent_core.dart`.
- **Dynamic fence length** — if file contains ` ``` `, the expansion uses ```````` to avoid breaking the markdown.
- **Raw text in UI, expanded to agent** — user sees `@lib/src/foo.dart` in conversation, LLM sees the file contents inline.
- **100 KB per-file cap** — prevents accidental prompt explosion. No total cap for v1 (keep it simple).
- **Overlay arbitration** — slash autocomplete wins when buffer starts with `/`, otherwise `@` hint. Only one overlay shown at a time.

## Out of Scope

- Directory expansion (`@lib/src/` expanding all files).
- Glob patterns (`@lib/**/*.dart`).
- Line range references (`@file.dart:120-200`).
- Truncation / summarisation of large files.
- `~` or absolute path expansion (relative to cwd only).
