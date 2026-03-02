# Bash Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add shell passthrough mode triggered by `!` prefix, with blocking execution, background jobs via `&`, and fieldset/legend output rendering.

**Architecture:** `App` tracks `_bashMode` bool and intercepts `!`/backspace at cursor pos 0 before `LineEditor`. Blocking commands run as `Process` with stdout/stderr collected. Background jobs managed by `ShellJobManager` with ring-buffered output. New `_EntryKind.bash` for fieldset-style rendering. Double-tap Ctrl+C guard for safe exit.

**Tech Stack:** Dart 3.4+, `dart:io` Process, `dart:collection` ListQueue, `package:test`

---

### Task 1: LineRingBuffer

**Files:**

- Create: `lib/src/shell/line_ring_buffer.dart`
- Test: `test/shell/line_ring_buffer_test.dart`

**Step 1: Write the failing tests**

```dart
import 'package:test/test.dart';
import 'package:glue/src/shell/line_ring_buffer.dart';

void main() {
  group('LineRingBuffer', () {
    test('stores and retrieves added lines', () {
      final buf = LineRingBuffer(maxLines: 100, maxBytes: 10000);
      buf.addText('line one\nline two\nline three');
      expect(buf.dump(), equals('line one\nline two\nline three'));
    });

    test('tail returns last N lines', () {
      final buf = LineRingBuffer(maxLines: 100, maxBytes: 10000);
      for (var i = 0; i < 10; i++) {
        buf.addText('line $i\n');
      }
      final tail = buf.tail(lines: 3);
      expect(tail, contains('line 7'));
      expect(tail, contains('line 8'));
      expect(tail, contains('line 9'));
      expect(tail, isNot(contains('line 6')));
    });

    test('evicts oldest lines when maxLines exceeded', () {
      final buf = LineRingBuffer(maxLines: 5, maxBytes: 100000);
      for (var i = 0; i < 10; i++) {
        buf.addText('line $i\n');
      }
      final dump = buf.dump();
      expect(dump, isNot(contains('line 0')));
      expect(dump, isNot(contains('line 4')));
      expect(dump, contains('line 5'));
      expect(dump, contains('line 9'));
    });

    test('evicts oldest lines when maxBytes exceeded', () {
      final buf = LineRingBuffer(maxLines: 10000, maxBytes: 30);
      buf.addText('aaaaaaaaaa\n'); // 11 bytes
      buf.addText('bbbbbbbbbb\n'); // 11 bytes
      buf.addText('cccccccccc\n'); // 11 bytes -> exceeds 30, evict oldest
      final dump = buf.dump();
      expect(dump, isNot(contains('aaa')));
      expect(dump, contains('bbb'));
      expect(dump, contains('ccc'));
    });

    test('lineCount tracks stored lines', () {
      final buf = LineRingBuffer(maxLines: 100, maxBytes: 10000);
      buf.addText('a\nb\nc');
      expect(buf.lineCount, equals(3));
    });

    test('handles empty input', () {
      final buf = LineRingBuffer(maxLines: 100, maxBytes: 10000);
      buf.addText('');
      expect(buf.dump(), equals(''));
    });

    test('handles multiple addText calls building partial lines', () {
      final buf = LineRingBuffer(maxLines: 100, maxBytes: 10000);
      buf.addText('hello ');
      buf.addText('world\nfoo');
      final dump = buf.dump();
      expect(dump, contains('hello world'));
      expect(dump, contains('foo'));
    });
  });
}
```

**Step 2: Run tests to verify they fail**

Run: `dart test test/shell/line_ring_buffer_test.dart`
Expected: FAIL — file not found

**Step 3: Implement LineRingBuffer**

```dart
import 'dart:collection';

class LineRingBuffer {
  final int maxLines;
  final int maxBytes;
  final _lines = ListQueue<String>();
  int _bytes = 0;

  LineRingBuffer({required this.maxLines, required this.maxBytes});

  int get lineCount => _lines.length;

  void addText(String text) {
    for (final line in text.split('\n')) {
      _pushLine(line);
    }
  }

  void _pushLine(String line) {
    final b = line.length + 1;
    _lines.add(line);
    _bytes += b;
    while (_lines.length > maxLines || _bytes > maxBytes) {
      if (_lines.isEmpty) break;
      final removed = _lines.removeFirst();
      _bytes -= (removed.length + 1);
    }
  }

  String tail({int lines = 200}) {
    final start = (_lines.length - lines).clamp(0, _lines.length);
    return _lines.skip(start).join('\n');
  }

  String dump() => _lines.join('\n');
}
```

**Step 4: Run tests to verify they pass**

Run: `dart test test/shell/line_ring_buffer_test.dart`
Expected: All pass

**Step 5: Run analyzer**

Run: `dart analyze lib/src/shell/line_ring_buffer.dart`
Expected: No issues

**Step 6: Commit**

```bash
git add lib/src/shell/line_ring_buffer.dart test/shell/line_ring_buffer_test.dart
git commit -m "feat: add LineRingBuffer for bounded output capture"
```

---

### Task 2: ShellJobManager

**Files:**

- Create: `lib/src/shell/shell_job_manager.dart`
- Test: `test/shell/shell_job_manager_test.dart`

**Step 1: Write the failing tests**

```dart
import 'package:test/test.dart';
import 'package:glue/src/shell/shell_job_manager.dart';

void main() {
  group('JobStatus', () {
    test('enum values exist', () {
      expect(JobStatus.values, containsAll([
        JobStatus.running, JobStatus.exited,
        JobStatus.failed, JobStatus.killed,
      ]));
    });
  });

  group('JobEvent sealed class', () {
    test('JobStarted holds id and command', () {
      final e = JobStarted(1, 'echo hi');
      expect(e.id, 1);
      expect(e.command, 'echo hi');
    });

    test('JobExited holds id and exitCode', () {
      final e = JobExited(1, 0);
      expect(e.id, 1);
      expect(e.exitCode, 0);
    });

    test('JobError holds id and error', () {
      final e = JobError(1, 'fail');
      expect(e.id, 1);
      expect(e.error, 'fail');
    });
  });

  group('ShellJobManager', () {
    late ShellJobManager manager;

    setUp(() {
      manager = ShellJobManager();
    });

    tearDown(() async {
      await manager.shutdown();
    });

    test('start creates a job with incremental id', () async {
      final job1 = await manager.start('echo hello');
      final job2 = await manager.start('echo world');
      expect(job1.id, 1);
      expect(job2.id, 2);
    });

    test('start emits JobStarted event', () async {
      final events = <JobEvent>[];
      manager.events.listen(events.add);
      await manager.start('echo hi');
      await Future.delayed(Duration(milliseconds: 50));
      expect(events.whereType<JobStarted>(), isNotEmpty);
    });

    test('job captures stdout in output buffer', () async {
      final job = await manager.start('echo hello');
      await Future.delayed(Duration(milliseconds: 500));
      expect(job.output.dump(), contains('hello'));
    });

    test('emits JobExited on process completion', () async {
      final events = <JobEvent>[];
      manager.events.listen(events.add);
      await manager.start('echo done');
      await Future.delayed(Duration(milliseconds: 500));
      final exits = events.whereType<JobExited>().toList();
      expect(exits, isNotEmpty);
      expect(exits.first.exitCode, 0);
    });

    test('getJob returns job by id', () async {
      final job = await manager.start('echo hi');
      expect(manager.getJob(job.id), same(job));
    });

    test('getJob returns null for unknown id', () {
      expect(manager.getJob(999), isNull);
    });

    test('jobs returns all jobs sorted by id', () async {
      await manager.start('echo a');
      await manager.start('echo b');
      final jobs = manager.jobs;
      expect(jobs.length, 2);
      expect(jobs[0].id, lessThan(jobs[1].id));
    });

    test('kill sends signal and updates status', () async {
      final job = await manager.start('sleep 30');
      await Future.delayed(Duration(milliseconds: 100));
      await manager.kill(job.id);
      await Future.delayed(Duration(milliseconds: 500));
      expect(job.status, anyOf(JobStatus.killed, JobStatus.exited, JobStatus.failed));
    });

    test('shutdown terminates all running jobs', () async {
      await manager.start('sleep 30');
      await manager.start('sleep 30');
      await Future.delayed(Duration(milliseconds: 100));
      await manager.shutdown();
      for (final job in manager.jobs) {
        expect(job.status, isNot(JobStatus.running));
      }
    });
  });
}
```

**Step 2: Run tests to verify they fail**

Run: `dart test test/shell/shell_job_manager_test.dart`
Expected: FAIL — file not found

**Step 3: Implement ShellJobManager**

```dart
import 'dart:async';
import 'dart:io';

import 'line_ring_buffer.dart';

enum JobStatus { running, exited, failed, killed }

sealed class JobEvent {}

class JobStarted extends JobEvent {
  final int id;
  final String command;
  JobStarted(this.id, this.command);
}

class JobExited extends JobEvent {
  final int id;
  final int exitCode;
  JobExited(this.id, this.exitCode);
}

class JobError extends JobEvent {
  final int id;
  final Object error;
  JobError(this.id, this.error);
}

class ShellJob {
  final int id;
  final String command;
  final DateTime startTime;
  final Process process;
  final LineRingBuffer output;

  JobStatus status = JobStatus.running;
  int? exitCode;

  ShellJob({
    required this.id,
    required this.command,
    required this.startTime,
    required this.process,
    required this.output,
  });
}

class ShellJobManager {
  int _nextId = 1;
  final _jobs = <int, ShellJob>{};
  final _events = StreamController<JobEvent>.broadcast();

  Stream<JobEvent> get events => _events.stream;

  List<ShellJob> get jobs =>
      _jobs.values.toList()..sort((a, b) => a.id.compareTo(b.id));

  Future<ShellJob> start(String command) async {
    final id = _nextId++;
    final process = await Process.start('sh', ['-c', command]);

    final job = ShellJob(
      id: id,
      command: command,
      startTime: DateTime.now(),
      process: process,
      output: LineRingBuffer(maxLines: 2000, maxBytes: 256 * 1024),
    );
    _jobs[id] = job;
    _events.add(JobStarted(id, command));

    process.stdout.transform(const SystemEncoding().decoder).listen(
      (chunk) => job.output.addText(chunk),
    );
    process.stderr.transform(const SystemEncoding().decoder).listen(
      (chunk) => job.output.addText(chunk),
    );

    unawaited(() async {
      try {
        final code = await process.exitCode;
        job.exitCode = code;
        if (job.status == JobStatus.killed) return;
        job.status = code == 0 ? JobStatus.exited : JobStatus.failed;
        _events.add(JobExited(id, code));
      } catch (e) {
        if (job.status == JobStatus.killed) return;
        job.status = JobStatus.failed;
        _events.add(JobError(id, e));
      }
    }());

    return job;
  }

  ShellJob? getJob(int id) => _jobs[id];

  Future<void> kill(int id) async {
    final job = _jobs[id];
    if (job == null || job.status != JobStatus.running) return;
    job.status = JobStatus.killed;
    job.process.kill(ProcessSignal.sigterm);
  }

  Future<void> shutdown() async {
    final running =
        _jobs.values.where((j) => j.status == JobStatus.running).toList();
    for (final j in running) {
      j.status = JobStatus.killed;
      j.process.kill(ProcessSignal.sigterm);
    }
    if (running.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 800));
      for (final j in running) {
        try {
          j.process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    }
    await _events.close();
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `dart test test/shell/shell_job_manager_test.dart`
Expected: All pass

**Step 5: Run analyzer**

Run: `dart analyze lib/src/shell/shell_job_manager.dart`
Expected: No issues

**Step 6: Commit**

```bash
git add lib/src/shell/shell_job_manager.dart test/shell/shell_job_manager_test.dart
git commit -m "feat: add ShellJobManager for background job lifecycle"
```

---

### Task 3: BlockRenderer.renderBash — fieldset/legend box

**Files:**

- Modify: `lib/src/rendering/block_renderer.dart`
- Modify: `test/block_renderer_test.dart`

**Step 1: Write the failing tests**

Add to `test/block_renderer_test.dart`:

```dart
group('renderBash', () {
  test('renders fieldset box with command in legend', () {
    final output = renderer.renderBash('git push', 'Everything up-to-date');
    final stripped = stripAnsi(output);
    expect(stripped, contains('git push'));
    expect(stripped, contains('Everything up-to-date'));
  });

  test('renders top border with command legend', () {
    final output = renderer.renderBash('ls', 'file.txt');
    final stripped = stripAnsi(output);
    final lines = stripped.split('\n');
    expect(lines.first, contains('┌'));
    expect(lines.first, contains('ls'));
    expect(lines.first, contains('┐'));
  });

  test('renders bottom border', () {
    final output = renderer.renderBash('ls', 'file.txt');
    final stripped = stripAnsi(output);
    final lines = stripped.split('\n');
    expect(lines.last, contains('└'));
    expect(lines.last, contains('┘'));
  });

  test('renders side borders on content lines', () {
    final output = renderer.renderBash('ls', 'file.txt');
    final stripped = stripAnsi(output);
    final contentLines = stripped.split('\n')
        .where((l) => l.contains('file.txt'))
        .toList();
    expect(contentLines, isNotEmpty);
    for (final line in contentLines) {
      expect(line, contains('│'));
    }
  });

  test('handles empty output', () {
    final output = renderer.renderBash('true', '');
    final stripped = stripAnsi(output);
    expect(stripped, contains('true'));
    expect(stripped, contains('┌'));
    expect(stripped, contains('└'));
  });

  test('handles multi-line output', () {
    final output = renderer.renderBash('ls', 'a.txt\nb.txt\nc.txt');
    final stripped = stripAnsi(output);
    expect(stripped, contains('a.txt'));
    expect(stripped, contains('b.txt'));
    expect(stripped, contains('c.txt'));
  });

  test('truncates long output with notice', () {
    final longOutput = List.generate(60, (i) => 'line $i').join('\n');
    final output = renderer.renderBash('cmd', longOutput, maxLines: 50);
    final stripped = stripAnsi(output);
    expect(stripped, contains('lines above'));
    expect(stripped, contains('line 59'));
    expect(stripped, isNot(contains('line 0\n')));
  });

  test('content lines do not exceed terminal width', () {
    final r = BlockRenderer(40);
    final longLine = 'x' * 100;
    final output = r.renderBash('cmd', longLine);
    for (final line in output.split('\n')) {
      expect(stripAnsi(line).length, lessThanOrEqualTo(40));
    }
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `dart test test/block_renderer_test.dart`
Expected: FAIL — `renderBash` not defined

**Step 3: Implement renderBash**

Add to `lib/src/rendering/block_renderer.dart`:

```dart
String renderBash(String command, String output, {int maxLines = 50}) {
  final boxWidth = _inner;
  final contentWidth = boxWidth - 4; // │ + space + content + space + │

  // Top border: ┌─ command ─────┐
  final legend = ' $command ';
  final topFill = boxWidth - 2 - legend.length; // -2 for ┌ and ┐
  final topBar = topFill > 0
      ? '─' * topFill
      : '';
  final top = ' \x1b[90m┌─\x1b[0m\x1b[1m$legend\x1b[0m\x1b[90m$topBar┐\x1b[0m';

  // Bottom border: └──────────────┘
  final bottom = ' \x1b[90m└${'─' * (boxWidth - 2)}┘\x1b[0m';

  // Content lines
  final lines = output.isEmpty ? <String>[] : output.split('\n');
  final truncated = lines.length > maxLines;
  final visible = truncated ? lines.sublist(lines.length - maxLines) : lines;

  final contentLines = <String>[];
  if (truncated) {
    final notice = '… (${lines.length - maxLines} lines above)';
    contentLines.add(
      ' \x1b[90m│\x1b[0m \x1b[90m${ansiTruncate(notice, contentWidth)}\x1b[0m${_pad(notice, contentWidth)}\x1b[90m│\x1b[0m',
    );
  }
  for (final line in visible) {
    final stripped = stripAnsi(line);
    final display = visibleLength(stripped) > contentWidth
        ? ansiTruncate(stripped, contentWidth)
        : stripped;
    contentLines.add(
      ' \x1b[90m│\x1b[0m $display${_pad(display, contentWidth)}\x1b[90m│\x1b[0m',
    );
  }

  if (contentLines.isEmpty) {
    contentLines.add(
      ' \x1b[90m│\x1b[0m${' ' * (boxWidth - 2)}\x1b[90m│\x1b[0m',
    );
  }

  return [top, ...contentLines, bottom].join('\n');
}

String _pad(String text, int width) {
  final vis = visibleLength(text);
  final pad = width - vis;
  return pad > 0 ? ' ' * (pad + 1) : ' ';
}
```

**Step 4: Run tests to verify they pass**

Run: `dart test test/block_renderer_test.dart`
Expected: All pass

**Step 5: Run analyzer**

Run: `dart analyze lib/src/rendering/block_renderer.dart`
Expected: No issues

**Step 6: Commit**

```bash
git add lib/src/rendering/block_renderer.dart test/block_renderer_test.dart
git commit -m "feat: add renderBash fieldset/legend box renderer"
```

---

### Task 4: GlueConfig — bashMaxLines setting

**Files:**

- Modify: `lib/src/config/glue_config.dart`
- Modify: `test/config/glue_config_test.dart`

**Step 1: Write the failing test**

Add to `test/config/glue_config_test.dart`:

```dart
test('bashMaxLines defaults to 50', () {
  final config = GlueConfig(anthropicApiKey: 'sk-ant-test');
  expect(config.bashMaxLines, 50);
});

test('bashMaxLines can be set explicitly', () {
  final config = GlueConfig(
    anthropicApiKey: 'sk-ant-test',
    bashMaxLines: 100,
  );
  expect(config.bashMaxLines, 100);
});
```

**Step 2: Run tests to verify they fail**

Run: `dart test test/config/glue_config_test.dart`
Expected: FAIL — `bashMaxLines` not a field

**Step 3: Add bashMaxLines to GlueConfig**

In `lib/src/config/glue_config.dart`:

Add field `final int bashMaxLines;` to the class.

Add `this.bashMaxLines = 50,` to the constructor.

In `GlueConfig.load()`, resolve from config file:

```dart
final bashMaxLines = (fileConfig?['bash'] as Map?)?['max_lines'] as int? ?? 50;
```

Pass `bashMaxLines: bashMaxLines` to the constructor call.

**Step 4: Run tests to verify they pass**

Run: `dart test test/config/glue_config_test.dart`
Expected: All pass

**Step 5: Run analyzer**

Run: `dart analyze lib/src/config/glue_config.dart`
Expected: No issues

**Step 6: Commit**

```bash
git add lib/src/config/glue_config.dart test/config/glue_config_test.dart
git commit -m "feat: add bashMaxLines config setting"
```

---

### Task 5: \_ConversationEntry.bash + AppMode.bashRunning

**Files:**

- Modify: `lib/src/app.dart`

**Step 1: Add AppMode.bashRunning variant**

In the `AppMode` enum in `lib/src/app.dart`, add:

```dart
/// A bash command is currently executing.
bashRunning,
```

**Step 2: Add \_EntryKind.bash and factory**

In `_EntryKind` enum, add `bash`.

Add factory constructor:

```dart
factory _ConversationEntry.bash(String command, String output) =>
    _ConversationEntry._(_EntryKind.bash, output, expandedText: command);
```

**Step 3: Wire bash entry into \_doRender block switch**

In the `switch (block.kind)` inside `_doRender`, add:

```dart
_EntryKind.bash => renderer.renderBash(
  block.expandedText ?? 'shell',
  block.text,
  maxLines: _config?.bashMaxLines ?? 50,
),
```

**Step 4: Update status bar mode indicator**

In the `modeIndicator` switch, add:

```dart
AppMode.bashRunning => '! Running',
```

**Step 5: Run analyzer**

Run: `dart analyze lib/src/app.dart`
Expected: No issues

**Step 6: Commit**

```bash
git add lib/src/app.dart
git commit -m "feat: add bash entry kind and bashRunning app mode"
```

---

### Task 6: Bash mode switching in App

**Files:**

- Modify: `lib/src/app.dart`

**Step 1: Add \_bashMode state field**

Add to the App class fields (near `_activeModal`):

```dart
bool _bashMode = false;
```

**Step 2: Add double-tap Ctrl+C state fields**

```dart
DateTime? _lastCtrlC;
static const _ctrlCWindow = Duration(seconds: 2);
```

**Step 3: Intercept `!` and backspace in \_handleTerminalEvent**

In `_handleTerminalEvent`, after the modal handling block and scroll handling block, but before the `_mode == AppMode.streaming || _mode == AppMode.toolRunning` check, add bash mode switching logic:

```dart
// Bash mode switching — before passing to editor.
if (_mode == AppMode.idle) {
  if (!_bashMode && event is CharEvent && event.char == '!' && editor.cursor == 0) {
    _bashMode = true;
    _render();
    return;
  }
  if (_bashMode && event is KeyEvent && event.key == Key.backspace && editor.cursor == 0) {
    _bashMode = false;
    _render();
    return;
  }
}
```

**Step 4: Update prompt rendering in \_doRender**

Replace the existing prompt switch:

```dart
final prompt = switch ((_mode, _bashMode)) {
  (AppMode.idle, true) => '! ',
  (AppMode.idle, false) => '❯ ',
  _ => '  ',
};
```

Update the `layout.paintInput` call — when bash mode is active and idle, use a different style. This requires passing the prompt styling separately. For now, the prompt string itself changes and the color is handled by adding ANSI codes:

```dart
final prompt = switch ((_mode, _bashMode)) {
  (AppMode.idle, true) => '! ',
  (AppMode.idle, false) => '❯ ',
  _ => '  ',
};
final promptStyle = switch ((_mode, _bashMode)) {
  (AppMode.idle, true) => AnsiStyle.red,
  (AppMode.idle, false) => AnsiStyle.yellow,
  _ => AnsiStyle.dim,
};
```

Update `paintInput` call to use `promptStyle` — check if `Layout.paintInput` supports a style parameter. If not, the prompt ANSI can be baked into the string before passing. Check existing `paintInput` implementation — it calls `terminal.writeStyled(prompt, style: AnsiStyle.yellow)`. Update this to accept a `style` parameter or pass styled prompt from App.

Review `Layout.paintInput` at `lib/src/terminal/layout.dart:135` — it hardcodes `AnsiStyle.yellow`. Modify it to accept an optional `AnsiStyle promptStyle` parameter:

```dart
void paintInput(String prompt, String text, int cursorPos, {
  bool showCursor = true,
  AnsiStyle promptStyle = AnsiStyle.yellow,
}) {
  // ... existing code, but use promptStyle instead of AnsiStyle.yellow
  terminal.writeStyled(prompt, style: promptStyle);
  // ...
}
```

Then in `_doRender`:

```dart
layout.paintInput(prompt, editor.text, editor.cursor,
    showCursor: showCursor, promptStyle: promptStyle);
```

**Step 5: Update double-tap Ctrl+C logic**

Replace the `case InputAction.interrupt:` handler in the idle-mode input handling:

```dart
case InputAction.interrupt:
  if (_mode != AppMode.idle) {
    _events.add(UserCancel());
  } else {
    final now = DateTime.now();
    if (_lastCtrlC != null && now.difference(_lastCtrlC!) < _ctrlCWindow) {
      _lastCtrlC = null;
      requestExit();
    } else {
      _lastCtrlC = now;
      _blocks.add(_ConversationEntry.system('Press Ctrl+C again to exit.'));
      _render();
    }
  }
```

Wait — looking at the current code more carefully, the `InputAction.interrupt` handler is inside the idle-mode section (after autocomplete/atHint handling). But for non-idle modes (streaming, toolRunning), Ctrl+C is handled earlier as `KeyEvent(key: Key.ctrlC)` which calls `_cancelAgent()`. We need to also handle it for `bashRunning` (Task 7). The double-tap logic applies only to idle mode.

Current code at line 452-453:

```dart
case InputAction.interrupt:
  requestExit();
```

Replace with:

```dart
case InputAction.interrupt:
  final now = DateTime.now();
  if (_lastCtrlC != null && now.difference(_lastCtrlC!) < _ctrlCWindow) {
    _lastCtrlC = null;
    requestExit();
  } else {
    _lastCtrlC = now;
    _blocks.add(_ConversationEntry.system('Press Ctrl+C again to exit.'));
    _render();
  }
```

**Step 6: Run analyzer**

Run: `dart analyze lib/src/app.dart lib/src/terminal/layout.dart`
Expected: No issues

**Step 7: Commit**

```bash
git add lib/src/app.dart lib/src/terminal/layout.dart
git commit -m "feat: bash mode switching, prompt styling, double-tap Ctrl+C"
```

---

### Task 7: Blocking bash execution

**Files:**

- Modify: `lib/src/app.dart`

**Step 1: Add \_bashRunProcess field**

Add to App class fields:

```dart
Process? _bashRunProcess;
```

**Step 2: Add bash submit handling in \_handleAppEvent**

In `_handleAppEvent`, the `UserSubmit` case currently checks `text.startsWith('/')`. Add bash mode check before the slash command check:

```dart
case UserSubmit(:final text):
  if (_bashMode) {
    _handleBashSubmit(text);
  } else if (text.startsWith('/')) {
    // ... existing slash command handling
  } else {
    // ... existing agent start
  }
```

**Step 3: Implement \_handleBashSubmit**

```dart
void _handleBashSubmit(String text) {
  if (text.isEmpty) return;

  // Background job: & prefix
  if (text.startsWith('& ') || text == '&') {
    final command = text.substring(1).trim();
    if (command.isEmpty) return;
    _startBackgroundJob(command);
    return;
  }

  // Blocking execution
  _mode = AppMode.bashRunning;
  _render();
  unawaited(_runBlockingBash(text));
}
```

**Step 4: Implement \_runBlockingBash**

```dart
Future<void> _runBlockingBash(String command) async {
  try {
    final process = await Process.start('sh', ['-c', command]);
    _bashRunProcess = process;

    final stdoutFuture =
        process.stdout.transform(const SystemEncoding().decoder).join();
    final stderrFuture =
        process.stderr.transform(const SystemEncoding().decoder).join();

    final exitCode = await process.exitCode;
    _bashRunProcess = null;

    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;

    final output = StringBuffer();
    if (stdout.isNotEmpty) output.write(stdout);
    if (stderr.isNotEmpty) {
      if (output.isNotEmpty) output.write('\n');
      output.write(stderr);
    }

    final stripped = stripAnsi(output.toString().trimRight());
    _blocks.add(_ConversationEntry.bash(command, stripped));
  } catch (e) {
    _bashRunProcess = null;
    _blocks.add(_ConversationEntry.error('Bash error: $e'));
  }
  _mode = AppMode.idle;
  _render();
}
```

Add import at top of app.dart: `import 'rendering/ansi_utils.dart';` (for `stripAnsi`). Check if it's already available via block_renderer.dart import — it imports `ansi_utils.dart` but that's in the rendering package. App needs its own import.

**Step 5: Handle Ctrl+C / Escape during bashRunning**

In the `_handleTerminalEvent` method, the block at line 370-381 handles `streaming` and `toolRunning`. Extend it to include `bashRunning`:

```dart
if (_mode == AppMode.streaming || _mode == AppMode.toolRunning || _mode == AppMode.bashRunning) {
  if (event case KeyEvent(key: Key.ctrlC) || KeyEvent(key: Key.escape)) {
    if (_mode == AppMode.bashRunning) {
      _cancelBash();
    } else {
      _cancelAgent();
    }
    return;
  }
  // ... rest of pre-typing handling
}
```

**Step 6: Implement \_cancelBash**

```dart
void _cancelBash() {
  _bashRunProcess?.kill(ProcessSignal.sigterm);
  _bashRunProcess = null;
  _mode = AppMode.idle;
  _blocks.add(_ConversationEntry.system('[bash command cancelled]'));
  _render();
}
```

**Step 7: Run analyzer**

Run: `dart analyze lib/src/app.dart`
Expected: No issues

**Step 8: Commit**

```bash
git add lib/src/app.dart
git commit -m "feat: blocking bash command execution with cancellation"
```

---

### Task 8: Background job integration in App

**Files:**

- Modify: `lib/src/app.dart`

**Step 1: Add ShellJobManager to App**

Add import:

```dart
import 'shell/shell_job_manager.dart';
```

Add field:

```dart
final ShellJobManager _jobManager;
```

Update constructor to accept and store it:

```dart
App({
  // ... existing params
  ShellJobManager? jobManager,
}) : // ... existing initializers
     _jobManager = jobManager ?? ShellJobManager() {
  // ...
}
```

In `App.create()`, create a `ShellJobManager()` and pass it.

**Step 2: Subscribe to job events in run()**

After the existing subscription lines, add:

```dart
final jobSub = _jobManager.events.listen(_handleJobEvent);
```

In the `finally` block, add:

```dart
await jobSub.cancel();
await _jobManager.shutdown();
```

**Step 3: Implement \_handleJobEvent**

```dart
void _handleJobEvent(JobEvent event) {
  switch (event) {
    case JobStarted(:final id, :final command):
      _blocks.add(_ConversationEntry.system('↳ Started job #$id: $command'));
      _render();
    case JobExited(:final id, :final exitCode):
      final job = _jobManager.getJob(id);
      final cmd = job?.command ?? '?';
      final label = exitCode == 0 ? 'exited' : 'failed';
      _blocks.add(_ConversationEntry.system('↳ Job #$id $label ($exitCode): $cmd'));
      _render();
    case JobError(:final id, :final error):
      _blocks.add(_ConversationEntry.system('↳ Job #$id error: $error'));
      _render();
  }
}
```

**Step 4: Implement \_startBackgroundJob**

```dart
void _startBackgroundJob(String command) {
  unawaited(() async {
    try {
      await _jobManager.start(command);
    } catch (e) {
      _blocks.add(_ConversationEntry.error('Failed to start job: $e'));
      _render();
    }
  }());
}
```

**Step 5: Run analyzer**

Run: `dart analyze lib/src/app.dart`
Expected: No issues

**Step 6: Commit**

```bash
git add lib/src/app.dart
git commit -m "feat: wire ShellJobManager into App for background jobs"
```

---

### Task 9: Barrel exports

**Files:**

- Modify: `lib/glue.dart`

**Step 1: Add exports**

Add to `lib/glue.dart`:

```dart
export 'src/shell/line_ring_buffer.dart' show LineRingBuffer;
export 'src/shell/shell_job_manager.dart' show ShellJobManager, ShellJob, JobStatus, JobEvent, JobStarted, JobExited, JobError;
```

**Step 2: Run analyzer**

Run: `dart analyze lib/glue.dart`
Expected: No issues

**Step 3: Commit**

```bash
git add lib/glue.dart
git commit -m "feat: export shell module types"
```

---

### Task 10: Full integration test

**Files:**

- Run all tests, verify analyzer clean

**Step 1: Run all tests**

Run: `dart test`
Expected: All pass

**Step 2: Run full analyzer**

Run: `dart analyze`
Expected: No issues

**Step 3: Manual smoke test (optional)**

Run: `dart run bin/glue.dart`

- Type `!ls` → should show directory listing in fieldset box
- Type `!` then `echo hello` then Enter → same result
- In bash mode, press Home then Backspace → should return to normal mode
- Type `!& sleep 5` → should see "Started job #1" immediately, then "Job #1 exited (0)" after 5s
- Press Ctrl+C → should see "Press Ctrl+C again to exit"
- Press Ctrl+C again quickly → should exit

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat: bash mode — shell passthrough with background jobs"
```
