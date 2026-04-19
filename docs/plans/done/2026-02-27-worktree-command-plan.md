# Worktree Command Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `/worktree` commands to create, list, switch between, and remove git worktrees stored in `.worktrees/` inside the project root.

**Architecture:** New `WorktreeService` class handles all git operations and path management. Slash commands in `App` delegate to the service. Switching worktrees resets `Directory.current`, rebuilds the system prompt, and resets the agent conversation. `AgentCore` gets a `reset()` method.

**Tech Stack:** Dart 3.4+, `Process.run('git', ...)`, dart:io

---

## Task 1: Branch name sanitization and repo root discovery

**Files:**

- Create: `lib/src/commands/worktree.dart`
- Create: `test/commands/worktree_test.dart`

**Step 1: Write failing tests**

Create `test/commands/worktree_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:glue/src/commands/worktree.dart';

void main() {
  group('sanitizeBranchName', () {
    test('simple name passes through', () {
      expect(sanitizeBranchName('my-feature'), 'wt/my-feature');
    });

    test('spaces become dashes', () {
      expect(sanitizeBranchName('my feature'), 'wt/my-feature');
    });

    test('special characters removed', () {
      expect(sanitizeBranchName('feat:auth*login'), 'wt/feat-auth-login');
    });

    test('slashes become dashes', () {
      expect(sanitizeBranchName('feat/auth/login'), 'wt/feat-auth-login');
    });

    test('collapses repeated dashes', () {
      expect(sanitizeBranchName('a--b---c'), 'wt/a-b-c');
    });

    test('strips leading and trailing dashes', () {
      expect(sanitizeBranchName('-hello-'), 'wt/hello');
    });

    test('returns null for empty after sanitization', () {
      expect(sanitizeBranchName('***'), null);
    });

    test('trims whitespace', () {
      expect(sanitizeBranchName('  hello  '), 'wt/hello');
    });
  });

  group('worktreeDirName', () {
    test('simple name', () {
      expect(worktreeDirName('my-feature'), 'my-feature');
    });

    test('sanitizes for directory use', () {
      expect(worktreeDirName('feat/auth'), 'feat-auth');
    });
  });
}
```

**Step 2: Run tests to verify they fail**

Run: `dart test test/commands/worktree_test.dart`
Expected: FAIL — file/functions not defined

**Step 3: Implement sanitization**

Create `lib/src/commands/worktree.dart`:

```dart
import 'dart:io';
import 'package:path/path.dart' as p;

/// Sanitize a user-provided name into a git branch name.
///
/// Returns `wt/<sanitized>` or null if the name is empty after sanitization.
String? sanitizeBranchName(String name) {
  var sanitized = name.trim();
  sanitized = sanitized.replaceAll(RegExp(r'[/\\ :*?"<>|#]'), '-');
  sanitized = sanitized.replaceAll(RegExp(r'-{2,}'), '-');
  sanitized = sanitized.replaceAll(RegExp(r'^-+|-+$'), '');
  if (sanitized.isEmpty) return null;
  return 'wt/$sanitized';
}

/// Sanitize a name for use as a directory name under `.worktrees/`.
String worktreeDirName(String name) {
  var sanitized = name.trim();
  sanitized = sanitized.replaceAll(RegExp(r'[/\\ :*?"<>|#]'), '-');
  sanitized = sanitized.replaceAll(RegExp(r'-{2,}'), '-');
  sanitized = sanitized.replaceAll(RegExp(r'^-+|-+$'), '');
  return sanitized;
}

/// Discover the main repository root.
///
/// Uses `git rev-parse --git-common-dir` which works from inside any
/// worktree. Returns null if not in a git repository.
Future<String?> findRepoRoot() async {
  try {
    final result = await Process.run('git', ['rev-parse', '--git-common-dir']);
    if (result.exitCode != 0) return null;

    final commonDir = (result.stdout as String).trim();

    if (commonDir == '.git') {
      // We're in the main repo.
      final toplevel = await Process.run('git', ['rev-parse', '--show-toplevel']);
      if (toplevel.exitCode != 0) return null;
      return (toplevel.stdout as String).trim();
    }

    // commonDir is an absolute path like /path/to/repo/.git
    // Repo root is the parent.
    return p.dirname(commonDir);
  } catch (_) {
    return null;
  }
}
```

**Step 4: Run tests**

Run: `dart test test/commands/worktree_test.dart`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/src/commands/worktree.dart test/commands/worktree_test.dart
git commit -m "feat: add branch name sanitization and repo root discovery for worktree"
```

---

## Task 2: `.gitignore` management

**Files:**

- Modify: `lib/src/commands/worktree.dart`
- Modify: `test/commands/worktree_test.dart`

**Step 1: Write failing tests**

Add to `test/commands/worktree_test.dart`:

```dart
import 'dart:io';

  group('ensureGitignore', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('worktree_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('creates .gitignore if missing', () {
      ensureWorktreeGitignore(tmpDir.path);
      final file = File(p.join(tmpDir.path, '.gitignore'));
      expect(file.existsSync(), true);
      expect(file.readAsStringSync(), contains('/.worktrees/'));
    });

    test('appends to existing .gitignore', () {
      File(p.join(tmpDir.path, '.gitignore')).writeAsStringSync('node_modules/\n');
      ensureWorktreeGitignore(tmpDir.path);
      final content = File(p.join(tmpDir.path, '.gitignore')).readAsStringSync();
      expect(content, contains('node_modules/'));
      expect(content, contains('/.worktrees/'));
    });

    test('does not duplicate if already present', () {
      File(p.join(tmpDir.path, '.gitignore')).writeAsStringSync('/.worktrees/\n');
      ensureWorktreeGitignore(tmpDir.path);
      final content = File(p.join(tmpDir.path, '.gitignore')).readAsStringSync();
      expect('/.worktrees/'.allMatches(content).length, 1);
    });

    test('detects variant without leading slash', () {
      File(p.join(tmpDir.path, '.gitignore')).writeAsStringSync('.worktrees/\n');
      ensureWorktreeGitignore(tmpDir.path);
      final content = File(p.join(tmpDir.path, '.gitignore')).readAsStringSync();
      // Should not add duplicate
      expect(content, isNot(contains('/.worktrees/')));
      expect(content, contains('.worktrees/'));
    });
  });
```

Add `import 'package:path/path.dart' as p;` to the test imports.

**Step 2: Run tests to verify they fail**

Run: `dart test test/commands/worktree_test.dart`
Expected: FAIL — `ensureWorktreeGitignore` not defined

**Step 3: Implement gitignore management**

Add to `lib/src/commands/worktree.dart`:

```dart
/// Ensure `.worktrees/` is in the `.gitignore` at [repoRoot].
///
/// Creates the file if it doesn't exist. Silently skips if already present.
void ensureWorktreeGitignore(String repoRoot) {
  final gitignorePath = p.join(repoRoot, '.gitignore');
  final file = File(gitignorePath);

  if (file.existsSync()) {
    final content = file.readAsStringSync();
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed == '/.worktrees/' || trimmed == '.worktrees/' ||
          trimmed == '/.worktrees' || trimmed == '.worktrees') {
        return; // Already present
      }
    }
    // Append with a newline separator if file doesn't end with one.
    final separator = content.endsWith('\n') ? '' : '\n';
    file.writeAsStringSync('$separator/.worktrees/\n', mode: FileMode.append);
  } else {
    file.writeAsStringSync('/.worktrees/\n');
  }
}
```

**Step 4: Run tests**

Run: `dart test test/commands/worktree_test.dart`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/src/commands/worktree.dart test/commands/worktree_test.dart
git commit -m "feat: add .gitignore management for .worktrees/"
```

---

## Task 3: Worktree list parsing

**Files:**

- Modify: `lib/src/commands/worktree.dart`
- Modify: `test/commands/worktree_test.dart`

**Step 1: Write failing tests**

Add to `test/commands/worktree_test.dart`:

```dart
  group('parseWorktreeList', () {
    test('parses porcelain output', () {
      final output = '''
worktree /home/user/project
HEAD abc1234
branch refs/heads/main

worktree /home/user/project/.worktrees/feature-auth
HEAD def5678
branch refs/heads/wt/feature-auth

''';
      final entries = parseWorktreeList(output);
      expect(entries.length, 2);
      expect(entries[0].path, '/home/user/project');
      expect(entries[0].branch, 'main');
      expect(entries[1].path, '/home/user/project/.worktrees/feature-auth');
      expect(entries[1].branch, 'wt/feature-auth');
    });

    test('handles detached HEAD', () {
      final output = '''
worktree /home/user/project/.worktrees/review
HEAD abc1234
detached

''';
      final entries = parseWorktreeList(output);
      expect(entries.length, 1);
      expect(entries[0].branch, null);
      expect(entries[0].isDetached, true);
    });

    test('handles empty output', () {
      expect(parseWorktreeList(''), isEmpty);
    });
  });
```

**Step 2: Run tests to verify they fail**

Run: `dart test test/commands/worktree_test.dart`
Expected: FAIL — `parseWorktreeList` / `WorktreeEntry` not defined

**Step 3: Implement list parsing**

Add to `lib/src/commands/worktree.dart`:

```dart
/// A parsed entry from `git worktree list --porcelain`.
class WorktreeEntry {
  final String path;
  final String head;
  final String? branch;
  final bool isDetached;

  WorktreeEntry({
    required this.path,
    required this.head,
    this.branch,
    this.isDetached = false,
  });

  /// The short branch name (strips `refs/heads/`).
  String get branchShort => branch ?? '(detached)';
}

/// Parse the porcelain output of `git worktree list --porcelain`.
List<WorktreeEntry> parseWorktreeList(String output) {
  if (output.trim().isEmpty) return [];

  final entries = <WorktreeEntry>[];
  final blocks = output.split('\n\n');

  for (final block in blocks) {
    final lines = block.trim().split('\n');
    if (lines.isEmpty) continue;

    String? path;
    String? head;
    String? branch;
    var detached = false;

    for (final line in lines) {
      if (line.startsWith('worktree ')) {
        path = line.substring('worktree '.length);
      } else if (line.startsWith('HEAD ')) {
        head = line.substring('HEAD '.length);
      } else if (line.startsWith('branch ')) {
        final ref = line.substring('branch '.length);
        branch = ref.startsWith('refs/heads/')
            ? ref.substring('refs/heads/'.length)
            : ref;
      } else if (line.trim() == 'detached') {
        detached = true;
      }
    }

    if (path != null && head != null) {
      entries.add(WorktreeEntry(
        path: path,
        head: head,
        branch: branch,
        isDetached: detached,
      ));
    }
  }

  return entries;
}
```

**Step 4: Run tests**

Run: `dart test test/commands/worktree_test.dart`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/src/commands/worktree.dart test/commands/worktree_test.dart
git commit -m "feat: add git worktree list porcelain parser"
```

---

## Task 4: `WorktreeService` — create, list, remove operations

**Files:**

- Modify: `lib/src/commands/worktree.dart`

**Step 1: Implement `WorktreeService`**

Add to `lib/src/commands/worktree.dart`:

```dart
/// High-level worktree operations backed by git commands.
class WorktreeService {
  final String repoRoot;

  WorktreeService(this.repoRoot);

  String get worktreesDir => p.join(repoRoot, '.worktrees');

  /// Create a new worktree with a branch derived from [name].
  ///
  /// Returns the path to the new worktree, or an error message.
  Future<({String? path, String? error})> create(String name) async {
    final dirName = worktreeDirName(name);
    if (dirName.isEmpty) return (path: null, error: 'Invalid worktree name.');

    final branch = sanitizeBranchName(name);
    if (branch == null) return (path: null, error: 'Invalid worktree name.');

    final wtPath = p.join(worktreesDir, dirName);

    // Check if directory already exists.
    if (Directory(wtPath).existsSync()) {
      return (path: wtPath, error: null); // Exists — caller should switch.
    }

    // Ensure .worktrees/ is in .gitignore.
    ensureWorktreeGitignore(repoRoot);

    // Check if branch exists.
    final branchCheck = await Process.run(
      'git', ['-C', repoRoot, 'rev-parse', '--verify', branch],
    );
    final branchExists = branchCheck.exitCode == 0;

    final ProcessResult result;
    if (branchExists) {
      result = await Process.run(
        'git', ['-C', repoRoot, 'worktree', 'add', wtPath, branch],
      );
    } else {
      result = await Process.run(
        'git', ['-C', repoRoot, 'worktree', 'add', '-b', branch, wtPath, 'HEAD'],
      );
    }

    if (result.exitCode != 0) {
      return (path: null, error: (result.stderr as String).trim());
    }

    return (path: wtPath, error: null);
  }

  /// List worktrees under `.worktrees/`.
  Future<List<WorktreeEntry>> list() async {
    final result = await Process.run(
      'git', ['-C', repoRoot, 'worktree', 'list', '--porcelain'],
    );
    if (result.exitCode != 0) return [];
    return parseWorktreeList(result.stdout as String);
  }

  /// Check if [path] has uncommitted changes.
  Future<bool> isDirty(String path) async {
    final result = await Process.run(
      'git', ['-C', path, 'status', '--porcelain'],
    );
    return (result.stdout as String).trim().isNotEmpty;
  }

  /// Remove a worktree by [name], optionally with [force].
  Future<String?> remove(String name, {bool force = false}) async {
    final dirName = worktreeDirName(name);
    final wtPath = p.join(worktreesDir, dirName);

    if (!Directory(wtPath).existsSync()) {
      return 'Worktree "$name" not found.';
    }

    final args = ['-C', repoRoot, 'worktree', 'remove'];
    if (force) args.add('--force');
    args.add(wtPath);

    final result = await Process.run('git', args);
    if (result.exitCode != 0) {
      return (result.stderr as String).trim();
    }

    // Best-effort branch cleanup.
    final branch = sanitizeBranchName(name);
    if (branch != null) {
      await Process.run('git', ['-C', repoRoot, 'branch', '-D', branch]);
    }

    // Prune stale metadata.
    await Process.run('git', ['-C', repoRoot, 'worktree', 'prune']);

    return null; // Success.
  }

  /// Check if [cwd] is inside a worktree under `.worktrees/`.
  bool isInsideWorktree(String cwd) {
    return p.isWithin(worktreesDir, cwd);
  }

  /// Get the worktree name from a path inside `.worktrees/`.
  String? worktreeNameFromPath(String cwd) {
    if (!isInsideWorktree(cwd)) return null;
    final relative = p.relative(cwd, from: worktreesDir);
    return relative.split(p.separator).first;
  }
}
```

**Step 2: Run full tests**

Run: `dart test`
Expected: All pass

Run: `dart analyze`
Expected: No issues

**Step 3: Commit**

```bash
git add lib/src/commands/worktree.dart
git commit -m "feat: add WorktreeService with create/list/remove/isDirty operations"
```

---

## Task 5: `AgentCore.reset()` method

**Files:**

- Modify: `lib/src/agent/agent_core.dart`
- Modify: `test/agent_core_test.dart`

**Step 1: Write failing test**

Add to `test/agent_core_test.dart`:

```dart
  test('reset clears conversation and token count', () {
    // Run a message to build up state.
    mockLlm.responses.add([TextDelta('hello')]);
    agent.run('test').listen((_) {});

    // Wait for completion then reset.
    Future.delayed(Duration.zero, () {
      agent.reset();
      expect(agent.conversation, isEmpty);
      expect(agent.tokenCount, 0);
    });
  });
```

**Step 2: Run test to verify it fails**

Run: `dart test test/agent_core_test.dart`
Expected: FAIL — `reset` not defined

**Step 3: Implement `reset()`**

Add to `AgentCore` class in `lib/src/agent/agent_core.dart`:

```dart
  /// Reset the agent to a clean state.
  ///
  /// Clears conversation history, pending tool results, and token count.
  /// Used when switching worktrees or starting a fresh context.
  void reset() {
    for (final completer in _pendingToolResults.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Agent reset while awaiting tool result'),
        );
      }
    }
    _pendingToolResults.clear();
    _conversation.clear();
    tokenCount = 0;
  }
```

**Step 4: Run tests**

Run: `dart test test/agent_core_test.dart`
Expected: All pass

Run: `dart test`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/src/agent/agent_core.dart test/agent_core_test.dart
git commit -m "feat: add AgentCore.reset() for worktree context switching"
```

---

## Task 6: Wire `/worktree` commands into App

**Files:**

- Modify: `lib/src/app.dart`
- Modify: `lib/glue.dart`

**Step 1: Make `_cwd` mutable**

In `lib/src/app.dart`, change:

```dart
// Before:
  final String _cwd;
// After:
  String _cwd;
```

In the constructor, keep:

```dart
  _cwd = Directory.current.path;
```

**Step 2: Add `_switchWorktree` helper**

Add to `App`:

```dart
  Future<String> _switchWorktree(String wtPath) async {
    // Cancel any in-flight agent work.
    if (_mode != AppMode.idle) {
      _cancelAgent();
    }

    // Switch cwd.
    Directory.current = wtPath;
    _cwd = wtPath;

    // Rebuild system prompt and LLM client.
    if (_llmFactory != null && _config != null) {
      final newPrompt = Prompts.build(cwd: wtPath);
      final llm = _llmFactory.createFromConfig(_config, systemPrompt: newPrompt);
      agent.llm = llm;

      // Update manager prompt for subagents.
      if (_manager != null) {
        // AgentManager.systemPrompt needs to be mutable for this.
        // For now, subagents will use the old prompt until restart.
      }
    }

    // Reset agent conversation.
    agent.reset();

    return wtPath;
  }
```

**Step 3: Register `/worktree` commands**

Add imports at the top of `lib/src/app.dart`:

```dart
import 'commands/worktree.dart';
```

In `_initCommands()`, add:

```dart
    _commands.register(SlashCommand(
      name: 'worktree',
      description: 'Create or switch to a worktree',
      execute: (args) {
        if (args.isEmpty) return 'Usage: /worktree <name>';
        final name = args.join(' ');
        _handleWorktreeCreate(name);
        return '';
      },
    ));

    _commands.register(SlashCommand(
      name: 'worktree:list',
      description: 'List worktrees',
      aliases: ['worktrees'],
      execute: (_) {
        _handleWorktreeList();
        return '';
      },
    ));

    _commands.register(SlashCommand(
      name: 'worktree:remove',
      description: 'Remove a worktree',
      execute: (args) {
        if (args.isEmpty) return 'Usage: /worktree:remove <name>';
        final name = args.join(' ');
        _handleWorktreeRemove(name);
        return '';
      },
    ));
```

Add the async handler methods:

```dart
  void _handleWorktreeCreate(String name) async {
    final repoRoot = await findRepoRoot();
    if (repoRoot == null) {
      _blocks.add(_ConversationEntry.error('Not a git repository.'));
      _render();
      return;
    }

    final service = WorktreeService(repoRoot);

    // Check for uncommitted changes in current worktree.
    if (await service.isDirty(_cwd)) {
      _blocks.add(_ConversationEntry.system(
        'Warning: uncommitted changes in current worktree. '
        'Changes will remain in the current worktree.',
      ));
    }

    final result = await service.create(name);
    if (result.error != null) {
      _blocks.add(_ConversationEntry.error(result.error!));
      _render();
      return;
    }

    final wtPath = result.path!;
    await _switchWorktree(wtPath);

    final branch = sanitizeBranchName(name) ?? name;
    _blocks.add(_ConversationEntry.system(
      'Switched to worktree "$name" on branch $branch',
    ));
    _render();
  }

  void _handleWorktreeList() async {
    final repoRoot = await findRepoRoot();
    if (repoRoot == null) {
      _blocks.add(_ConversationEntry.error('Not a git repository.'));
      _render();
      return;
    }

    final service = WorktreeService(repoRoot);
    final entries = await service.list();

    if (entries.isEmpty) {
      _blocks.add(_ConversationEntry.system('No worktrees found.'));
      _render();
      return;
    }

    final buf = StringBuffer('Worktrees:\n');
    for (final entry in entries) {
      final isCurrent = entry.path == _cwd;
      final marker = isCurrent ? '▸' : ' ';
      final name = service.worktreeNameFromPath(entry.path) ??
          p.basename(entry.path);
      buf.writeln('  $marker $name    ${entry.branchShort}');
    }
    _blocks.add(_ConversationEntry.system(buf.toString()));
    _render();
  }

  void _handleWorktreeRemove(String name) async {
    final repoRoot = await findRepoRoot();
    if (repoRoot == null) {
      _blocks.add(_ConversationEntry.error('Not a git repository.'));
      _render();
      return;
    }

    final service = WorktreeService(repoRoot);
    final dirName = worktreeDirName(name);
    final wtPath = p.join(service.worktreesDir, dirName);

    // Check if we're inside the target worktree.
    if (p.isWithin(wtPath, _cwd) || _cwd == wtPath) {
      _blocks.add(_ConversationEntry.system(
        'Switching to repo root before removing worktree...',
      ));
      await _switchWorktree(repoRoot);
    }

    // Check dirty state.
    final dirty = Directory(wtPath).existsSync() &&
        await service.isDirty(wtPath);

    if (dirty) {
      _blocks.add(_ConversationEntry.system(
        'Worktree "$name" has uncommitted changes. Force removing...',
      ));
    }

    final error = await service.remove(name, force: dirty);
    if (error != null) {
      _blocks.add(_ConversationEntry.error(error));
    } else {
      _blocks.add(_ConversationEntry.system('Removed worktree "$name".'));
    }
    _render();
  }
```

Add `import 'package:path/path.dart' as p;` if not already present.

**Step 4: Export from barrel**

In `lib/glue.dart`, add:

```dart
export 'src/commands/worktree.dart' show WorktreeService, WorktreeEntry, sanitizeBranchName;
```

**Step 5: Run tests**

Run: `dart test`
Expected: All pass

Run: `dart analyze`
Expected: No issues

**Step 6: Commit**

```bash
git add lib/src/app.dart lib/src/commands/worktree.dart lib/glue.dart
git commit -m "feat: wire /worktree, /worktree:list, /worktree:remove commands"
```

---

## Execution Order

**Group A (independent):**

- Task 1: Sanitization + repo root discovery
- Task 5: AgentCore.reset()

**Group B (depends on Task 1):**

- Task 2: .gitignore management
- Task 3: Worktree list parsing

**Group C (depends on B):**

- Task 4: WorktreeService

**Group D (depends on C + Task 5):**

- Task 6: App wiring

---

## Notes

- The `/worktree` remove flow currently force-removes without a confirmation modal for simplicity. A future enhancement could use `ConfirmModal` (or the new `PanelModal`) to confirm destructive operations — but this requires the slash command system to support async execution with modals, which is a larger refactor.
- `AgentManager.systemPrompt` is currently `final`. Making it mutable so subagents use the updated prompt after a worktree switch is a small follow-up.
- Integration tests (actually creating git repos + worktrees in tmp dirs) are valuable but heavyweight. The unit tests cover parsing/sanitization; manual testing covers the git operations.
