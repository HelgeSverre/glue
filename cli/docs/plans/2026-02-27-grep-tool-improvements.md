# Grep Tool Improvements — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expand `GrepTool` with high-utility parameters — glob filtering, case-insensitive search, context lines, output truncation, files-with-matches mode, fixed-string mode, and proper stderr/exit-code handling.

**Architecture:** All changes are confined to `GrepTool` in `lib/src/agent/tools.dart` and its tests. No app wiring changes needed — the tool is already registered. New parameters are all optional with sensible defaults so existing behaviour is unchanged.

**Tech Stack:** Dart 3.4+, `package:test`, `rg` (ripgrep, preferred) / `grep` (fallback)

---

### Task 1: Add `glob`, `case_sensitive`, and `context` parameters

**Files:**

- Modify: `lib/src/agent/tools.dart`
- Create: `test/tools/grep_tool_test.dart`

**Step 1: Write failing tests**

Create `test/tools/grep_tool_test.dart`:

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:glue/src/agent/tools.dart';

void main() {
  late GrepTool tool;
  late Directory tmpDir;

  setUp(() async {
    tool = GrepTool();
    tmpDir = await Directory.systemTemp.createTemp('grep_tool_test_');
    await File(p.join(tmpDir.path, 'main.dart')).writeAsString(
      'void main() {\n  print("Hello");\n}\n',
    );
    await File(p.join(tmpDir.path, 'README.md')).writeAsString(
      '# Hello World\nThis is a readme.\n',
    );
    await File(p.join(tmpDir.path, 'config.yaml')).writeAsString(
      'key: value\nhello: world\n',
    );
    await Directory(p.join(tmpDir.path, 'lib')).create();
    await File(p.join(tmpDir.path, 'lib', 'util.dart')).writeAsString(
      'String greet() => "Hello";\n',
    );
  });

  tearDown(() => tmpDir.delete(recursive: true));

  group('GrepTool', () {
    test('basic pattern match returns results', () async {
      final result = await tool.execute({'pattern': 'Hello', 'path': tmpDir.path});
      expect(result, isNot('No matches found.'));
      expect(result, contains('Hello'));
    });

    test('no matches returns No matches found', () async {
      final result = await tool.execute({'pattern': 'zzznomatch', 'path': tmpDir.path});
      expect(result, 'No matches found.');
    });

    test('glob filters to matching file types only', () async {
      final result = await tool.execute({
        'pattern': 'Hello',
        'path': tmpDir.path,
        'glob': '*.dart',
      });
      expect(result, contains('.dart'));
      expect(result, isNot(contains('.md')));
      expect(result, isNot(contains('.yaml')));
    });

    test('glob works with negation pattern', () async {
      final result = await tool.execute({
        'pattern': 'Hello',
        'path': tmpDir.path,
        'glob': '!*.md',
      });
      expect(result, isNot(contains('.md')));
    });

    test('case_sensitive false matches regardless of case', () async {
      final result = await tool.execute({
        'pattern': 'hello',
        'path': tmpDir.path,
        'case_sensitive': false,
      });
      expect(result, isNot('No matches found.'));
      expect(result.toLowerCase(), contains('hello'));
    });

    test('case_sensitive true (default) does not match wrong case', () async {
      // 'hello' lowercase only appears in config.yaml — 'Hello' in others
      final result = await tool.execute({
        'pattern': 'hello',
        'path': tmpDir.path,
        'glob': '*.dart',
        'case_sensitive': true,
      });
      // dart files only have 'Hello' (capital), not 'hello'
      expect(result, 'No matches found.');
    });

    test('context lines includes surrounding lines', () async {
      final result = await tool.execute({
        'pattern': 'print',
        'path': tmpDir.path,
        'glob': '*.dart',
        'context': 1,
      });
      // Should include the line before (void main) and after (})
      expect(result, contains('main'));
      expect(result, contains('}'));
    });
  });
}
```

Run: `dart test test/tools/grep_tool_test.dart`
Expected: Several FAIL — parameters not wired yet.

**Step 2: Add parameters to `GrepTool`**

In `lib/src/agent/tools.dart`, replace the `parameters` getter and `execute` method of `GrepTool`:

```dart
@override
List<ToolParameter> get parameters => const [
      ToolParameter(
        name: 'pattern',
        type: 'string',
        description: 'Regex pattern to search for.',
      ),
      ToolParameter(
        name: 'path',
        type: 'string',
        description: 'File or directory to search in. Defaults to current directory.',
        required: false,
      ),
      ToolParameter(
        name: 'glob',
        type: 'string',
        description:
            'Glob pattern to filter files (e.g. "*.dart", "!*.yaml"). '
            'Only supported with ripgrep.',
        required: false,
      ),
      ToolParameter(
        name: 'case_sensitive',
        type: 'boolean',
        description: 'Whether the search is case-sensitive. Defaults to true.',
        required: false,
      ),
      ToolParameter(
        name: 'context',
        type: 'integer',
        description:
            'Number of context lines to show before and after each match. '
            'Defaults to 0.',
        required: false,
      ),
    ];
```

**Step 3: Update `execute` to pass new flags**

```dart
@override
Future<String> execute(Map<String, dynamic> args) async {
  final pattern = args['pattern'];
  if (pattern is! String || pattern.isEmpty) {
    return 'Error: no pattern provided';
  }
  final path = args['path'];
  final searchPath = (path is String && path.isNotEmpty) ? path : '.';
  final glob = args['glob'] as String?;
  final caseSensitive = args['case_sensitive'] as bool? ?? true;
  final context = args['context'] as int? ?? 0;

  final useRg = await _which('rg') != null;
  final executable = useRg ? 'rg' : 'grep';

  final List<String> arguments;
  if (useRg) {
    arguments = ['--line-number', '--no-heading'];
    if (!caseSensitive) arguments.add('--ignore-case');
    if (context > 0) arguments.addAll(['--context', '$context']);
    if (glob != null && glob.isNotEmpty) arguments.addAll(['--glob', glob]);
    arguments.addAll([pattern, searchPath]);
  } else {
    arguments = ['-rn'];
    if (!caseSensitive) arguments.add('-i');
    if (context > 0) arguments.addAll(['-C', '$context']);
    arguments.addAll([pattern, searchPath]);
  }

  try {
    final result = await Process.run(executable, arguments)
        .timeout(Duration(seconds: AppConstants.grepTimeoutSeconds));

    final stderr = (result.stderr as String).trim();
    if (result.exitCode != 0 && (result.stdout as String).isEmpty) {
      return stderr.isNotEmpty
          ? 'Error: $stderr'
          : 'No matches found.';
    }
    if ((result.stdout as String).isEmpty) return 'No matches found.';
    return result.stdout as String;
  } on TimeoutException {
    return 'Error: grep timed out after ${AppConstants.grepTimeoutSeconds} seconds';
  }
}
```

**Step 4: Run tests**

Run: `dart test test/tools/grep_tool_test.dart`
Expected: ALL PASS

**Step 5: Run dart analyze**

Run: `dart analyze`
Expected: No issues found.

**Step 6: Commit**

```bash
git add lib/src/agent/tools.dart test/tools/grep_tool_test.dart
git commit -m "feat(grep): add glob, case_sensitive, context parameters"
```

---

### Task 2: Add output truncation

**Files:**

- Modify: `lib/src/agent/tools.dart`
- Modify: `lib/src/config/constants.dart`
- Modify: `test/tools/grep_tool_test.dart`

**Step 1: Write failing test**

Add to the `GrepTool` group in `test/tools/grep_tool_test.dart`:

```dart
test('output is truncated when it exceeds line cap', () async {
  // Write a file with many matching lines
  final bigFile = File(p.join(tmpDir.path, 'big.txt'));
  await bigFile.writeAsString(
    List.generate(300, (i) => 'match line $i').join('\n'),
  );
  final result = await tool.execute({
    'pattern': 'match',
    'path': tmpDir.path,
    'glob': '*.txt',
  });
  final lineCount = '\n'.allMatches(result).length;
  expect(lineCount, lessThanOrEqualTo(AppConstants.grepMaxOutputLines + 5));
  expect(result, contains('truncated'));
});
```

**Step 2: Add constant**

In `lib/src/config/constants.dart`, add:

```dart
static const int grepMaxOutputLines = 200;
```

**Step 3: Apply truncation in `execute`**

After the stdout check, before returning:

```dart
final output = result.stdout as String;
if (output.isEmpty) return 'No matches found.';

final lines = output.split('\n');
if (lines.length > AppConstants.grepMaxOutputLines) {
  final truncated = lines.take(AppConstants.grepMaxOutputLines).join('\n');
  final remaining = lines.length - AppConstants.grepMaxOutputLines;
  return '$truncated\n\n(truncated — $remaining more lines not shown)';
}
return output;
```

**Step 4: Run tests**

Run: `dart test test/tools/grep_tool_test.dart`
Expected: ALL PASS

**Step 5: Run dart analyze**

Run: `dart analyze`
Expected: No issues found.

**Step 6: Commit**

```bash
git add lib/src/agent/tools.dart lib/src/config/constants.dart test/tools/grep_tool_test.dart
git commit -m "feat(grep): truncate output at grepMaxOutputLines (200)"
```

---

### Task 3: Add `files_with_matches` and `fixed_string` modes

**Files:**

- Modify: `lib/src/agent/tools.dart`
- Modify: `test/tools/grep_tool_test.dart`

**Step 1: Write failing tests**

Add to `test/tools/grep_tool_test.dart`:

```dart
test('files_with_matches returns only filenames', () async {
  final result = await tool.execute({
    'pattern': 'Hello',
    'path': tmpDir.path,
    'files_with_matches': true,
  });
  expect(result, isNot('No matches found.'));
  // Each line should be a path, not a match line with line numbers
  final lines = result.trim().split('\n').where((l) => l.isNotEmpty).toList();
  for (final line in lines) {
    expect(line, isNot(matches(r':\d+:')));
  }
});

test('fixed_string treats pattern as literal not regex', () async {
  // A regex metachar that would fail as a regex but match as literal
  await File(p.join(tmpDir.path, 'literal.txt'))
      .writeAsString('price is \$5.00\n');
  final result = await tool.execute({
    'pattern': r'$5.00',
    'path': tmpDir.path,
    'glob': '*.txt',
    'fixed_string': true,
  });
  expect(result, isNot('No matches found.'));
  expect(result, contains(r'$5.00'));
});

test('fixed_string false uses regex', () async {
  await File(p.join(tmpDir.path, 'regex.txt'))
      .writeAsString('abc123\n');
  final result = await tool.execute({
    'pattern': r'\d+',
    'path': tmpDir.path,
    'glob': '*.txt',
    'fixed_string': false,
  });
  expect(result, isNot('No matches found.'));
});
```

**Step 2: Add parameters**

Append to `parameters` in `GrepTool`:

```dart
ToolParameter(
  name: 'files_with_matches',
  type: 'boolean',
  description:
      'If true, output only the names of files containing matches, '
      'not the matching lines. Useful for "which files touch X" queries.',
  required: false,
),
ToolParameter(
  name: 'fixed_string',
  type: 'boolean',
  description:
      'If true, treat the pattern as a literal string rather than a regex. '
      'Useful when searching for text containing regex metacharacters.',
  required: false,
),
```

**Step 3: Wire flags into `execute`**

Extract from args at the top of `execute`:

```dart
final filesWithMatches = args['files_with_matches'] as bool? ?? false;
final fixedString = args['fixed_string'] as bool? ?? false;
```

Add to the `rg` arguments block:

```dart
if (filesWithMatches) arguments.add('--files-with-matches');
if (fixedString) arguments.add('--fixed-strings');
```

Add to the `grep` fallback block:

```dart
if (filesWithMatches) arguments.add('-l');
if (fixedString) arguments.add('-F');
```

**Step 4: Run tests**

Run: `dart test test/tools/grep_tool_test.dart`
Expected: ALL PASS

Run: `dart test`
Expected: ALL PASS

**Step 5: Run dart analyze**

Run: `dart analyze`
Expected: No issues found.

**Step 6: Commit**

```bash
git add lib/src/agent/tools.dart test/tools/grep_tool_test.dart
git commit -m "feat(grep): add files_with_matches and fixed_string parameters"
```

---

## File Changelist

| File | Change |
|------|--------|
| `lib/src/agent/tools.dart` | **Modified** — new parameters, updated `execute`, stderr handling, output truncation |
| `lib/src/config/constants.dart` | **Modified** — add `grepMaxOutputLines = 200` |
| `test/tools/grep_tool_test.dart` | **New** — full test suite for all grep behaviours |

---

## Parameter Summary

| Parameter | Type | Default | rg flag | grep flag |
|-----------|------|---------|---------|-----------|
| `pattern` | string | — (required) | positional | positional |
| `path` | string | `.` | positional | positional |
| `glob` | string | — | `--glob` | unsupported |
| `case_sensitive` | boolean | `true` | `--ignore-case` | `-i` |
| `context` | integer | `0` | `--context N` | `-C N` |
| `files_with_matches` | boolean | `false` | `--files-with-matches` | `-l` |
| `fixed_string` | boolean | `false` | `--fixed-strings` | `-F` |

Output is capped at `grepMaxOutputLines` (200) lines with a truncation notice appended.

---

## What's Explicitly Out of Scope

- `--no-ignore` / searching `.gitignore`d files (niche, can be done via `bash` tool)
- `--max-count` per-file limit (covered by global output truncation)
- Glob support in `grep` fallback (not portable; users with only `grep` get a best-effort result without file filtering)
- Multiline match mode
- Replacing `GrepTool` with a pure Dart implementation
