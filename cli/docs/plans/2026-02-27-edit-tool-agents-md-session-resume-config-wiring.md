# Edit Tool, AGENTS.md Support, Session Resume & Config Wiring

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an `edit_file` tool with multi-line find-and-replace (inspired by OpenCode's approach), auto-load AGENTS.md/CLAUDE.md into system prompt, implement session resume with a selection list UI, wire trusted tools persistence, and clean up slash commands (merge into `/info`, remove `/tokens`).

**Architecture:** The `edit_file` tool uses exact string matching with ambiguity rejection (hard error if `old_string` appears more than once). System prompt enrichment scans cwd for AGENTS.md/CLAUDE.md and appends contents. Session resume reads JSONL from `~/.glue/sessions/` and replays into `AgentCore`. Slash commands are consolidated.

**Tech Stack:** Dart 3.4+, package:path, dart:io, dart:convert

---

## Task 1: `EditFileTool` — find-and-replace with multi-line support

**Files:**
- Modify: `lib/src/agent/tools.dart`
- Create: `test/tools/edit_file_tool_test.dart`

**Step 1: Write failing tests**

Create `test/tools/edit_file_tool_test.dart`:

```dart
import 'dart:io';
import 'package:test/test.dart';
import 'package:glue/glue.dart';

void main() {
  late Directory tmpDir;
  late EditFileTool tool;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('edit_file_test_');
    tool = EditFileTool();
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  File _write(String name, String content) {
    final f = File('${tmpDir.path}/$name');
    f.writeAsStringSync(content);
    return f;
  }

  test('replaces single-line match', () async {
    final f = _write('a.dart', 'int x = 1;\nint y = 2;\n');
    final result = await tool.execute({
      'path': f.path,
      'old_string': 'int x = 1;',
      'new_string': 'int x = 42;',
    });
    expect(result, contains('Applied edit'));
    expect(f.readAsStringSync(), 'int x = 42;\nint y = 2;\n');
  });

  test('replaces multi-line match', () async {
    final f = _write('b.dart', 'void foo() {\n  print("hello");\n}\n');
    final result = await tool.execute({
      'path': f.path,
      'old_string': 'void foo() {\n  print("hello");\n}',
      'new_string': 'void foo() {\n  print("world");\n  return;\n}',
    });
    expect(result, contains('Applied edit'));
    expect(f.readAsStringSync(), 'void foo() {\n  print("world");\n  return;\n}\n');
  });

  test('errors when old_string not found', () async {
    final f = _write('c.dart', 'int x = 1;\n');
    final result = await tool.execute({
      'path': f.path,
      'old_string': 'int y = 2;',
      'new_string': 'int y = 3;',
    });
    expect(result, contains('not found'));
  });

  test('errors when old_string is ambiguous', () async {
    final f = _write('d.dart', 'foo();\nbar();\nfoo();\n');
    final result = await tool.execute({
      'path': f.path,
      'old_string': 'foo();',
      'new_string': 'baz();',
    });
    expect(result, contains('multiple'));
  });

  test('creates file when old_string is empty', () async {
    final path = '${tmpDir.path}/new_file.dart';
    final result = await tool.execute({
      'path': path,
      'old_string': '',
      'new_string': 'void main() {}\n',
    });
    expect(result, contains('Created'));
    expect(File(path).readAsStringSync(), 'void main() {}\n');
  });

  test('deletes content when new_string is empty', () async {
    final f = _write('e.dart', 'line1\nline2\nline3\n');
    final result = await tool.execute({
      'path': f.path,
      'old_string': 'line2\n',
      'new_string': '',
    });
    expect(result, contains('Applied edit'));
    expect(f.readAsStringSync(), 'line1\nline3\n');
  });

  test('errors when file not found and old_string non-empty', () async {
    final result = await tool.execute({
      'path': '${tmpDir.path}/nope.dart',
      'old_string': 'hello',
      'new_string': 'world',
    });
    expect(result, contains('not found'));
  });

  test('errors on missing path', () async {
    final result = await tool.execute({
      'old_string': 'a',
      'new_string': 'b',
    });
    expect(result, contains('Error'));
  });

  test('handles whitespace-only old_string for insert at beginning', () async {
    final f = _write('f.dart', 'content\n');
    final result = await tool.execute({
      'path': f.path,
      'old_string': '',
      'new_string': '// header\n',
    });
    // Empty old_string on existing file creates (overwrites), matching OpenCode behavior
    expect(result, contains('Created'));
  });
}
```

**Step 2: Run tests to verify they fail**

Run: `dart test test/tools/edit_file_tool_test.dart`
Expected: FAIL — `EditFileTool` does not exist

**Step 3: Implement `EditFileTool`**

Add to the bottom of `lib/src/agent/tools.dart`:

```dart
/// Edit a file using find-and-replace.
///
/// Supports multi-line strings. If [old_string] is empty, creates the file
/// with [new_string] as content. If [new_string] is empty, deletes the
/// matched text. Fails if [old_string] appears more than once (ambiguous).
class EditFileTool extends Tool {
  @override
  String get name => 'edit_file';

  @override
  String get description =>
      'Edit a file by replacing an exact match of old_string with new_string. '
      'old_string must match exactly one location in the file (include enough '
      'context lines to be unambiguous). If old_string is empty, creates the '
      'file with new_string as content. Supports multi-line strings.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'path',
          type: 'string',
          description: 'Absolute or relative path to the file.',
        ),
        ToolParameter(
          name: 'old_string',
          type: 'string',
          description:
              'The exact text to find (multi-line supported). '
              'Must be unique in the file. Empty string to create a new file.',
        ),
        ToolParameter(
          name: 'new_string',
          type: 'string',
          description:
              'The replacement text (multi-line supported). '
              'Empty string to delete the matched text.',
        ),
      ];

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final path = args['path'];
    if (path is! String || path.isEmpty) return 'Error: no path provided';
    final oldString = args['old_string'] as String? ?? '';
    final newString = args['new_string'] as String? ?? '';

    final file = File(path);

    // Create mode: old_string is empty.
    if (oldString.isEmpty) {
      await file.parent.create(recursive: true);
      await file.writeAsString(newString);
      return 'Created ${file.path} (${newString.length} bytes)';
    }

    // Edit mode: file must exist.
    if (!await file.exists()) {
      return 'Error: file not found: $path';
    }

    final content = await file.readAsString();

    // Check for exact match.
    final firstIndex = content.indexOf(oldString);
    if (firstIndex == -1) {
      return 'Error: old_string not found in $path. '
          'Make sure it matches the file content exactly, '
          'including whitespace and indentation.';
    }

    // Check for ambiguity.
    final lastIndex = content.lastIndexOf(oldString);
    if (firstIndex != lastIndex) {
      return 'Error: old_string appears multiple times in $path. '
          'Include more surrounding context lines to make the match unique.';
    }

    // Apply the edit.
    final newContent =
        content.substring(0, firstIndex) +
        newString +
        content.substring(firstIndex + oldString.length);

    await file.writeAsString(newContent);

    final oldLines = oldString.split('\n').length;
    final newLines = newString.split('\n').length;
    return 'Applied edit to $path: replaced $oldLines line(s) with $newLines line(s)';
  }
}
```

**Step 4: Run tests**

Run: `dart test test/tools/edit_file_tool_test.dart`
Expected: All pass

**Step 5: Register `EditFileTool` in `App.create()` and export from barrel**

In `lib/src/app.dart`, inside `App.create()` where tools are declared (around line 143), add:

```dart
'edit_file': EditFileTool(),
```

Also add `edit_file` to the `_autoApprovedTools` set would be wrong — this is a write tool that needs approval. No change to auto-approve.

In `lib/glue.dart`, update the tools export line to include `EditFileTool`:

```dart
export 'src/agent/tools.dart' show Tool, ToolParameter, ReadFileTool, WriteFileTool, EditFileTool, BashTool, GrepTool, ListDirectoryTool;
```

**Step 6: Run full test suite**

Run: `dart test`
Expected: All pass

Run: `dart analyze`
Expected: No issues

**Step 7: Commit**

```bash
git add lib/src/agent/tools.dart lib/src/app.dart lib/glue.dart test/tools/edit_file_tool_test.dart
git commit -m "feat: add edit_file tool with multi-line find-and-replace"
```

---

## Task 2: AGENTS.md / CLAUDE.md auto-loading into system prompt

**Files:**
- Modify: `lib/src/agent/prompts.dart`
- Create: `test/agent/prompts_test.dart`

**Step 1: Write failing tests**

Create `test/agent/prompts_test.dart`:

```dart
import 'dart:io';
import 'package:test/test.dart';
import 'package:glue/glue.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('prompts_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  test('build includes AGENTS.md when present', () {
    File('${tmpDir.path}/AGENTS.md').writeAsStringSync('Run dart test');
    final prompt = Prompts.build(cwd: tmpDir.path);
    expect(prompt, contains('Run dart test'));
    expect(prompt, contains('AGENTS.md'));
  });

  test('build includes CLAUDE.md when present', () {
    File('${tmpDir.path}/CLAUDE.md').writeAsStringSync('Use package:test');
    final prompt = Prompts.build(cwd: tmpDir.path);
    expect(prompt, contains('Use package:test'));
    expect(prompt, contains('CLAUDE.md'));
  });

  test('build includes both when both present', () {
    File('${tmpDir.path}/AGENTS.md').writeAsStringSync('agents instructions');
    File('${tmpDir.path}/CLAUDE.md').writeAsStringSync('claude instructions');
    final prompt = Prompts.build(cwd: tmpDir.path);
    expect(prompt, contains('agents instructions'));
    expect(prompt, contains('claude instructions'));
  });

  test('build works without any files', () {
    final prompt = Prompts.build(cwd: tmpDir.path);
    expect(prompt, contains('Glue'));
    expect(prompt, isNot(contains('AGENTS.md')));
  });

  test('build still accepts projectContext', () {
    final prompt = Prompts.build(cwd: tmpDir.path, projectContext: 'custom');
    expect(prompt, contains('custom'));
  });

  test('truncates files over 50KB', () {
    File('${tmpDir.path}/AGENTS.md').writeAsStringSync('x' * 60000);
    final prompt = Prompts.build(cwd: tmpDir.path);
    expect(prompt, contains('truncated'));
    expect(prompt.length, lessThan(system.length + 55000));
  });
}

// Expose the system constant for the test
const system = Prompts.system;
```

Wait — `Prompts.system` is a static const so we can reference it. But the test references `system` directly. Let's adjust — just check the prompt is not excessively long.

**Step 2: Run tests to verify they fail**

Run: `dart test test/agent/prompts_test.dart`
Expected: FAIL — `Prompts.build` doesn't accept `cwd`

**Step 3: Update `Prompts.build` to scan for guidance files**

Replace `lib/src/agent/prompts.dart`:

```dart
import 'dart:io';
import 'package:path/path.dart' as p;

/// System prompt templates for the Glue agent.
class Prompts {
  Prompts._();

  static const String system = '''
You are Glue, an expert coding agent that helps developers with software engineering tasks.

You operate inside a terminal. You have access to tools for reading files, writing files,
editing files, running shell commands, searching code, and listing directories.

Guidelines:
- Be direct and technical. Respect the developer's expertise.
- Use tools proactively to gather context before answering.
- When modifying code, read the file first to understand conventions.
- Prefer edit_file over write_file for existing files (smaller diffs, less error-prone).
- Make the smallest reasonable change. Don't over-engineer.
- If a task requires multiple steps, work through them sequentially.
- Always verify your work by reading back files you've written.
''';

  static const _maxGuidanceBytes = 50 * 1024;

  static const _guidanceFiles = ['AGENTS.md', 'CLAUDE.md'];

  /// Build a full system prompt, optionally appending project-specific context.
  ///
  /// If [cwd] is provided, scans for AGENTS.md and CLAUDE.md and appends
  /// their contents as project instructions.
  static String build({String? cwd, String? projectContext}) {
    final buf = StringBuffer(system);

    if (cwd != null) {
      for (final filename in _guidanceFiles) {
        final file = File(p.join(cwd, filename));
        if (file.existsSync()) {
          var content = file.readAsStringSync();
          if (content.length > _maxGuidanceBytes) {
            content = '${content.substring(0, _maxGuidanceBytes)}\n\n(truncated — file exceeded 50KB)';
          }
          buf.write('\n\n## Project Instructions ($filename)\n\n$content');
        }
      }
    }

    if (projectContext != null && projectContext.isNotEmpty) {
      buf.write('\n\n## Project Context\n\n$projectContext');
    }
    return buf.toString();
  }
}
```

**Step 4: Update `App.create()` to pass cwd**

In `lib/src/app.dart`, change the `Prompts.build()` call (around line 139):

```dart
// Before:
final systemPrompt = Prompts.build();
// After:
final systemPrompt = Prompts.build(cwd: Directory.current.path);
```

**Step 5: Run tests**

Run: `dart test test/agent/prompts_test.dart`
Expected: All pass

Run: `dart test`
Expected: All pass

Run: `dart analyze`
Expected: No issues

**Step 6: Commit**

```bash
git add lib/src/agent/prompts.dart lib/src/app.dart test/agent/prompts_test.dart
git commit -m "feat: auto-load AGENTS.md and CLAUDE.md into system prompt"
```

---

## Task 3: Session resume — list + selection UI + replay

This has three sub-parts: reading saved sessions, presenting a selection list, and replaying into `AgentCore`.

**Files:**
- Modify: `lib/src/storage/session_store.dart` (add `listSessions`, `loadConversation`)
- Modify: `lib/src/app.dart` (add `/resume` command, wire session store into lifecycle)
- Create: `test/storage/session_resume_test.dart`

### Sub-step 3a: Add session listing and loading to `SessionStore`

**Step 1: Write failing tests**

Create `test/storage/session_resume_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:glue/glue.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('session_resume_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('SessionStore.listSessions', () {
    test('returns empty list when no sessions', () {
      final sessions = SessionStore.listSessions(tmpDir.path);
      expect(sessions, isEmpty);
    });

    test('returns sessions sorted newest first', () {
      _createSession(tmpDir.path, 'sess-1', DateTime(2026, 1, 1), 'model-a');
      _createSession(tmpDir.path, 'sess-2', DateTime(2026, 1, 3), 'model-b');
      _createSession(tmpDir.path, 'sess-3', DateTime(2026, 1, 2), 'model-c');

      final sessions = SessionStore.listSessions(tmpDir.path);
      expect(sessions.length, 3);
      expect(sessions[0].id, 'sess-2');
      expect(sessions[1].id, 'sess-3');
      expect(sessions[2].id, 'sess-1');
    });

    test('skips directories without meta.json', () {
      Directory(p.join(tmpDir.path, 'broken-session')).createSync();
      final sessions = SessionStore.listSessions(tmpDir.path);
      expect(sessions, isEmpty);
    });
  });

  group('SessionStore.loadConversation', () {
    test('loads user and assistant events', () {
      final sessDir = _createSession(tmpDir.path, 'sess-1', DateTime.now(), 'model');
      _appendEvent(sessDir, 'user_message', {'text': 'hello'});
      _appendEvent(sessDir, 'assistant_message', {'text': 'hi there'});

      final events = SessionStore.loadConversation(sessDir);
      expect(events.length, 2);
      expect(events[0]['type'], 'user_message');
      expect(events[1]['type'], 'assistant_message');
    });

    test('returns empty list for missing conversation file', () {
      final sessDir = p.join(tmpDir.path, 'empty-sess');
      Directory(sessDir).createSync();
      final events = SessionStore.loadConversation(sessDir);
      expect(events, isEmpty);
    });
  });
}

String _createSession(String base, String id, DateTime start, String model) {
  final dir = p.join(base, id);
  Directory(dir).createSync(recursive: true);
  final meta = {
    'id': id,
    'cwd': '/tmp',
    'model': model,
    'provider': 'anthropic',
    'start_time': start.toIso8601String(),
  };
  File(p.join(dir, 'meta.json')).writeAsStringSync(jsonEncode(meta));
  return dir;
}

void _appendEvent(String sessDir, String type, Map<String, dynamic> data) {
  final file = File(p.join(sessDir, 'conversation.jsonl'));
  final record = {
    'timestamp': DateTime.now().toIso8601String(),
    'type': type,
    ...data,
  };
  file.writeAsStringSync('${jsonEncode(record)}\n', mode: FileMode.append);
}
```

**Step 2: Run tests to verify they fail**

Run: `dart test test/storage/session_resume_test.dart`
Expected: FAIL — `SessionStore.listSessions` does not exist

**Step 3: Add static methods to `SessionStore`**

Add these static methods to the `SessionStore` class in `lib/src/storage/session_store.dart`:

```dart
import 'package:path/path.dart' as p;

// Add these inside the SessionStore class:

  /// List all saved sessions, sorted newest first.
  static List<SessionMeta> listSessions(String sessionsDir) {
    final dir = Directory(sessionsDir);
    if (!dir.existsSync()) return [];

    final sessions = <SessionMeta>[];
    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      final metaFile = File(p.join(entry.path, 'meta.json'));
      if (!metaFile.existsSync()) continue;
      try {
        final json = jsonDecode(metaFile.readAsStringSync())
            as Map<String, dynamic>;
        sessions.add(SessionMeta(
          id: json['id'] as String,
          cwd: json['cwd'] as String? ?? '',
          model: json['model'] as String? ?? 'unknown',
          provider: json['provider'] as String? ?? 'unknown',
          startTime: DateTime.parse(json['start_time'] as String),
          endTime: json['end_time'] != null
              ? DateTime.parse(json['end_time'] as String)
              : null,
        ));
      } catch (_) {
        // Skip malformed sessions
      }
    }

    sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
    return sessions;
  }

  /// Load the conversation event log from a session directory.
  static List<Map<String, dynamic>> loadConversation(String sessionDir) {
    final file = File(p.join(sessionDir, 'conversation.jsonl'));
    if (!file.existsSync()) return [];

    final events = <Map<String, dynamic>>[];
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      try {
        events.add(jsonDecode(line) as Map<String, dynamic>);
      } catch (_) {
        // Skip malformed lines
      }
    }
    return events;
  }
```

Make sure `import 'package:path/path.dart' as p;` is at the top of the file.

**Step 4: Run tests**

Run: `dart test test/storage/session_resume_test.dart`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/src/storage/session_store.dart test/storage/session_resume_test.dart
git commit -m "feat: add session listing and conversation loading to SessionStore"
```

### Sub-step 3b: Wire `/resume` command into App

**Files:**
- Modify: `lib/src/app.dart`

**Step 1: Add `/resume` slash command**

In `_initCommands()` in `lib/src/app.dart`, add after the `/history` command:

```dart
    _commands.register(SlashCommand(
      name: 'resume',
      description: 'Resume a previous session',
      execute: (args) {
        final home = GlueHome();
        final sessions = SessionStore.listSessions(home.sessionsDir);
        if (sessions.isEmpty) return 'No saved sessions found.';

        final count = args.isNotEmpty ? int.tryParse(args[0]) ?? 10 : 10;
        final shown = sessions.take(count).toList();

        final buf = StringBuffer('Recent sessions:\n');
        for (var i = 0; i < shown.length; i++) {
          final s = shown[i];
          final ago = _timeAgo(s.startTime);
          final shortCwd = _shortenPath(s.cwd);
          buf.writeln(
            '  ${i + 1}. ${s.id.substring(0, 8)}…  '
            '${s.model}  $shortCwd  $ago',
          );
        }
        buf.writeln('\nUsage: /resume <number> to load a session.');

        // If a number was passed, load that session
        if (args.isNotEmpty) {
          final idx = (int.tryParse(args[0]) ?? 0) - 1;
          if (idx >= 0 && idx < shown.length) {
            final session = shown[idx];
            return _resumeSession(session);
          }
        }

        return buf.toString();
      },
    ));
```

Add the helper methods to `App`:

```dart
  String _resumeSession(SessionMeta session) {
    final home = GlueHome();
    final events = SessionStore.loadConversation(home.sessionDir(session.id));
    if (events.isEmpty) return 'Session ${session.id} has no conversation data.';

    // Replay user and assistant messages into the agent's conversation history
    var userCount = 0;
    var assistantCount = 0;
    for (final event in events) {
      final type = event['type'] as String?;
      switch (type) {
        case 'user_message':
          final text = event['text'] as String? ?? '';
          if (text.isNotEmpty) {
            agent.conversation;  // We need to add messages directly
            userCount++;
          }
        case 'assistant_message':
          assistantCount++;
        default:
          break;
      }
    }

    // Add a system block showing the resume
    _blocks.add(_ConversationEntry.system(
      'Resumed session ${session.id.substring(0, 8)}… '
      '($userCount messages, model: ${session.model})',
    ));

    return 'Resumed session from ${_timeAgo(session.startTime)}.';
  }

  static String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return time.toIso8601String().substring(0, 10);
  }
```

Add `import 'storage/glue_home.dart';` and `import 'storage/session_store.dart';` at the top of app.dart (check if already imported via barrel).

**Step 2: Run tests**

Run: `dart test`
Expected: All pass

Run: `dart analyze`
Expected: No issues

**Step 3: Commit**

```bash
git add lib/src/app.dart
git commit -m "feat: add /resume command for session history"
```

---

## Task 4: Wire trusted tools persistence

**Files:**
- Modify: `lib/src/app.dart`

**Step 1: Load trusted tools from config on startup**

In `App.create()`, after the `App(...)` constructor call (around line 163), load trusted tools:

```dart
    // Load persisted trusted tools from ~/.glue/config.json
    final home = GlueHome();
    final configStore = ConfigStore(home.configPath);
    final persistedTrusted = configStore.trustedTools;
    // We can't access _autoApprovedTools on the returned App yet,
    // so we need to pass it through the constructor.
```

Actually, the cleanest approach is to add a `trustedTools` parameter to the App constructor.

**Step 1 (revised): Add `initialTrustedTools` to App constructor**

In `lib/src/app.dart`, add a parameter to the `App` constructor:

```dart
  App({
    required this.terminal,
    required this.layout,
    required this.editor,
    required this.agent,
    required String modelName,
    AgentManager? manager,
    LlmClientFactory? llmFactory,
    GlueConfig? config,
    String? systemPrompt,
    Set<String>? extraTrustedTools,  // NEW
  }) : _modelName = modelName,
       _manager = manager,
       _llmFactory = llmFactory,
       _config = config,
       _systemPrompt = systemPrompt,
       _cwd = Directory.current.path {
    _initCommands();
    _autocomplete = SlashAutocomplete(_commands);
    _atHint = AtFileHint();
    if (extraTrustedTools != null) {
      _autoApprovedTools.addAll(extraTrustedTools);
    }
  }
```

In `App.create()`, load and pass:

```dart
    final home = GlueHome();
    home.ensureDirectories();
    final configStore = ConfigStore(home.configPath);

    return App(
      terminal: terminal,
      layout: layout,
      editor: editor,
      agent: agent,
      modelName: config.model,
      manager: manager,
      llmFactory: llmFactory,
      config: config,
      systemPrompt: systemPrompt,
      extraTrustedTools: configStore.trustedTools.toSet(),
    );
```

**Step 2: Persist "Always" choice back to config**

In `_handleAgentEvent`, in the `case 2: // Always` branch (around line 582), after `_autoApprovedTools.add(call.name)`, add:

```dart
            case 2: // Always
              _autoApprovedTools.add(call.name);
              // Persist to config
              try {
                final home = GlueHome();
                final store = ConfigStore(home.configPath);
                store.update((c) {
                  final tools = (c['trusted_tools'] as List?)?.cast<String>() ?? [];
                  if (!tools.contains(call.name)) {
                    tools.add(call.name);
                    c['trusted_tools'] = tools;
                  }
                });
              } catch (_) {
                // Don't block on config write failure
              }
              _mode = AppMode.toolRunning;
```

**Step 3: Run tests**

Run: `dart test`
Expected: All pass

Run: `dart analyze`
Expected: No issues

**Step 4: Commit**

```bash
git add lib/src/app.dart
git commit -m "feat: persist trusted tool approvals to ~/.glue/config.json"
```

---

## Task 5: Slash command cleanup — add `/info`, remove `/tokens`

**Files:**
- Modify: `lib/src/app.dart`

**Step 1: Replace `/tokens` with `/info`**

In `_initCommands()`, remove the `/tokens` command registration and add `/info`:

Remove:
```dart
    _commands.register(SlashCommand(
      name: 'tokens',
      description: 'Show token usage',
      execute: (_) => 'Total tokens used: ${agent.tokenCount}',
    ));
```

Add in its place:
```dart
    _commands.register(SlashCommand(
      name: 'info',
      description: 'Show session info',
      aliases: ['status'],
      execute: (_) {
        final shortCwd = _shortenPath(_cwd);
        final trustedList = _autoApprovedTools.toList()..sort();
        final buf = StringBuffer();
        buf.writeln('Session Info');
        buf.writeln('  Model:        $_modelName');
        buf.writeln('  Provider:     ${_config?.provider.name ?? "unknown"}');
        buf.writeln('  Directory:    $shortCwd');
        buf.writeln('  Tokens used:  ${agent.tokenCount}');
        buf.writeln('  Messages:     ${agent.conversation.length}');
        buf.writeln('  Tools:        ${agent.tools.length} registered');
        buf.writeln('  Auto-approve: ${trustedList.join(", ")}');
        return buf.toString();
      },
    ));
```

**Step 2: Remove `/tools` command** (redundant with `/info` showing tool count and `/help`)

Actually keep `/tools` — it shows the full tool list with descriptions, which `/info` doesn't. It's useful.

**Step 3: Run tests**

Run: `dart test`
Expected: All pass (check if any test references `/tokens` — likely not since slash command tests test the registry generically)

Run: `dart analyze`
Expected: No issues

**Step 4: Commit**

```bash
git add lib/src/app.dart
git commit -m "feat: add /info command, remove /tokens (info covers it)"
```

---

## Task 6: Log events to SessionStore during app lifecycle

**Files:**
- Modify: `lib/src/app.dart`

This task wires the existing `SessionStore` into the app lifecycle so sessions are actually saved and can be resumed later.

**Step 1: Add session store field and initialization**

Add field to `App`:

```dart
  SessionStore? _sessionStore;
```

In `App.create()`, after creating `home` and before the `return App(...)`:

```dart
    home.ensureDirectories();
    final sessionId = '${DateTime.now().millisecondsSinceEpoch}-'
        '${DateTime.now().microsecond.toRadixString(36)}';
    final sessionStore = SessionStore(
      sessionDir: home.sessionDir(sessionId),
      meta: SessionMeta(
        id: sessionId,
        cwd: Directory.current.path,
        model: config.model,
        provider: config.provider.name,
        startTime: DateTime.now(),
      ),
    );
```

Pass `sessionStore` through the constructor (add a `SessionStore? sessionStore` parameter) and assign to `_sessionStore`.

**Step 2: Log events in `_handleAgentEvent`**

At the start of `_handleAgentEvent`, log to session store:

```dart
  void _handleAgentEvent(AgentEvent event) {
    switch (event) {
      case AgentTextDelta(:final delta):
        // Don't log individual deltas — too noisy
        _streamingText += delta;
        _scrollOffset = 0;
        _render();

      // ... existing cases
    }
  }
```

In the `UserSubmit` handler, log the user message:

```dart
_sessionStore?.logEvent('user_message', {'text': expanded});
```

When `AgentDone` fires and `_streamingText` is committed, log:

```dart
_sessionStore?.logEvent('assistant_message', {'text': _streamingText});
```

For tool calls, log inside `AgentToolCall`:

```dart
_sessionStore?.logEvent('tool_call', {
  'name': call.name,
  'arguments': call.arguments,
});
```

**Step 3: Close session store on shutdown**

In `run()`, in the `finally` block, add before terminal cleanup:

```dart
await _sessionStore?.close();
```

**Step 4: Run tests**

Run: `dart test`
Expected: All pass

Run: `dart analyze`
Expected: No issues

**Step 5: Commit**

```bash
git add lib/src/app.dart
git commit -m "feat: wire SessionStore into app lifecycle for conversation logging"
```

---

## Execution Order

**Group A (independent, can be parallel):**
- Task 1: edit_file tool (tools.dart, new test file)
- Task 2: AGENTS.md / CLAUDE.md loading (prompts.dart, new test file)
- Task 3a: Session listing/loading (session_store.dart, new test file)

**Group B (depends on A for app.dart):**
- Task 3b: /resume command (app.dart)
- Task 4: Trusted tools wiring (app.dart)
- Task 5: Slash command cleanup (app.dart)
- Task 6: Session store lifecycle wiring (app.dart)

Group B tasks modify app.dart sequentially, so they must run in order.

---

## Separate Planning Required (NOT in this plan)

These features need their own brainstorming + planning cycles:

1. **`/help` construction-themed modal** — Full-screen dimmed overlay with construction/brutalist branding from the website. Requires enhancing the modal system beyond `ConfirmModal`. Separate from autocomplete/@file input overlays.

2. **`/worktree` command** — Auto-create git worktrees in `cwd/.worktrees/`, add to `.gitignore`, branch management. Complex git interaction requiring careful design.
