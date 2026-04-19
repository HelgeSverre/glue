# Shell Executor — Unified Multi-Shell Execution Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Unify the 3 hardcoded `Process.start('sh', ['-c', command])` call sites behind a `CommandExecutor` abstraction that respects the user's preferred shell.

**Architecture:** Abstract `CommandExecutor` interface with `HostExecutor` implementation. `ShellConfig` added to `GlueConfig` with detection from `$SHELL` env var. All 3 call sites delegate to the executor. Docker backend deferred to separate plan.

**Tech Stack:** Dart 3.4+, `dart:io` Process API

**Design docs:** `docs/design/command-executor.md`, `docs/reference/config-yaml.md`

---

### Task 1: ShellConfig Data Model

**Files:**

- Create: `lib/src/shell/shell_config.dart`
- Test: `test/shell/shell_config_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:test/test.dart';
import '../../lib/src/shell/shell_config.dart';

void main() {
  group('ShellMode', () {
    test('fromString parses valid modes', () {
      expect(ShellMode.fromString('non_interactive'), ShellMode.nonInteractive);
      expect(ShellMode.fromString('interactive'), ShellMode.interactive);
      expect(ShellMode.fromString('login'), ShellMode.login);
    });

    test('fromString returns nonInteractive for unknown', () {
      expect(ShellMode.fromString('bogus'), ShellMode.nonInteractive);
    });
  });

  group('ShellConfig', () {
    test('defaults to sh and nonInteractive', () {
      final config = ShellConfig();
      expect(config.executable, 'sh');
      expect(config.mode, ShellMode.nonInteractive);
    });

    test('buildArgs for bash nonInteractive', () {
      final config = ShellConfig(executable: 'bash');
      expect(config.buildArgs('echo hi'), ['bash', '-c', 'echo hi']);
    });

    test('buildArgs for zsh interactive', () {
      final config = ShellConfig(
        executable: 'zsh',
        mode: ShellMode.interactive,
      );
      expect(config.buildArgs('echo hi'), ['zsh', '-i', '-c', 'echo hi']);
    });

    test('buildArgs for bash login', () {
      final config = ShellConfig(
        executable: 'bash',
        mode: ShellMode.login,
      );
      expect(config.buildArgs('echo hi'), ['bash', '-l', '-c', 'echo hi']);
    });

    test('buildArgs for fish interactive', () {
      final config = ShellConfig(
        executable: 'fish',
        mode: ShellMode.interactive,
      );
      expect(config.buildArgs('echo hi'), ['fish', '-i', '-c', 'echo hi']);
    });

    test('buildArgs for pwsh nonInteractive', () {
      final config = ShellConfig(executable: 'pwsh');
      expect(
        config.buildArgs('echo hi'),
        ['pwsh', '-NoProfile', '-Command', 'echo hi'],
      );
    });

    test('buildArgs for pwsh interactive', () {
      final config = ShellConfig(
        executable: 'pwsh',
        mode: ShellMode.interactive,
      );
      expect(config.buildArgs('echo hi'), ['pwsh', '-Command', 'echo hi']);
    });
  });

  group('ShellConfig.detect', () {
    test('returns executable from explicit value', () {
      final config = ShellConfig.detect(explicit: '/bin/zsh');
      expect(config.executable, '/bin/zsh');
    });

    test('falls back to sh when no SHELL env and no explicit', () {
      final config = ShellConfig.detect(shellEnv: null);
      expect(config.executable, 'sh');
    });

    test('uses SHELL env when no explicit value', () {
      final config = ShellConfig.detect(shellEnv: '/opt/homebrew/bin/zsh');
      expect(config.executable, '/opt/homebrew/bin/zsh');
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/shell/shell_config_test.dart`
Expected: FAIL (file doesn't exist)

**Step 3: Write minimal implementation**

```dart
enum ShellMode {
  nonInteractive,
  interactive,
  login;

  static ShellMode fromString(String s) => switch (s) {
        'interactive' => ShellMode.interactive,
        'login' => ShellMode.login,
        _ => ShellMode.nonInteractive,
      };
}

class ShellConfig {
  final String executable;
  final ShellMode mode;

  const ShellConfig({
    this.executable = 'sh',
    this.mode = ShellMode.nonInteractive,
  });

  factory ShellConfig.detect({
    String? explicit,
    String? shellEnv,
    ShellMode mode = ShellMode.nonInteractive,
  }) {
    final exe = explicit ?? shellEnv ?? 'sh';
    return ShellConfig(executable: exe, mode: mode);
  }

  /// Shell base name (strips path).
  String get _baseName {
    final name = executable.split('/').last;
    // Normalize powershell variants
    if (name == 'powershell' || name == 'powershell.exe') return 'pwsh';
    if (name.endsWith('.exe')) return name.replaceAll('.exe', '');
    return name;
  }

  bool get _isPowerShell => _baseName == 'pwsh';

  /// Build the full argument list: [executable, ...flags, command].
  List<String> buildArgs(String command) {
    if (_isPowerShell) {
      return [
        executable,
        if (mode == ShellMode.nonInteractive) '-NoProfile',
        '-Command',
        command,
      ];
    }

    // POSIX shells (sh, bash, zsh, fish, etc.)
    final isFish = _baseName == 'fish';
    return [
      executable,
      if (mode == ShellMode.interactive) '-i',
      if (mode == ShellMode.login) ...[if (isFish) '--login' else '-l'],
      '-c',
      command,
    ];
  }
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/shell/shell_config_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/shell/shell_config.dart test/shell/shell_config_test.dart
git commit -m "feat: add ShellConfig with multi-shell argument mapping"
```

---

### Task 2: CommandExecutor Interface + CaptureResult + RunningCommand

**Files:**

- Create: `lib/src/shell/command_executor.dart`
- Test: `test/shell/command_executor_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:test/test.dart';
import '../../lib/src/shell/command_executor.dart';

void main() {
  group('CaptureResult', () {
    test('stores exitCode, stdout, stderr', () {
      final r = CaptureResult(exitCode: 0, stdout: 'ok\n', stderr: '');
      expect(r.exitCode, 0);
      expect(r.stdout, 'ok\n');
      expect(r.stderr, '');
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/shell/command_executor_test.dart`
Expected: FAIL

**Step 3: Write minimal implementation**

```dart
import 'dart:io';

class CaptureResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  CaptureResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

class RunningCommand {
  final Process process;

  RunningCommand(this.process);

  Stream<List<int>> get stdout => process.stdout;
  Stream<List<int>> get stderr => process.stderr;
  Future<int> get exitCode => process.exitCode;

  Future<void> kill() async {
    process.kill(ProcessSignal.sigterm);
  }
}

abstract class CommandExecutor {
  Future<CaptureResult> runCapture(String command, {Duration? timeout});
  Future<RunningCommand> startStreaming(String command);
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/shell/command_executor_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/shell/command_executor.dart test/shell/command_executor_test.dart
git commit -m "feat: add CommandExecutor interface and data types"
```

---

### Task 3: HostExecutor Implementation

**Files:**

- Create: `lib/src/shell/host_executor.dart`
- Test: `test/shell/host_executor_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:test/test.dart';
import '../../lib/src/shell/host_executor.dart';
import '../../lib/src/shell/shell_config.dart';

void main() {
  group('HostExecutor', () {
    late HostExecutor executor;

    setUp(() {
      executor = HostExecutor(ShellConfig(executable: 'sh'));
    });

    test('runCapture captures stdout', () async {
      final result = await executor.runCapture('echo hello');
      expect(result.stdout.trim(), 'hello');
      expect(result.exitCode, 0);
    });

    test('runCapture captures stderr', () async {
      final result = await executor.runCapture('echo err >&2');
      expect(result.stderr.trim(), 'err');
    });

    test('runCapture returns non-zero exit code', () async {
      final result = await executor.runCapture('exit 42');
      expect(result.exitCode, 42);
    });

    test('runCapture times out', () async {
      final result = await executor.runCapture(
        'sleep 10',
        timeout: Duration(milliseconds: 100),
      );
      expect(result.exitCode, -1);
    });

    test('startStreaming returns RunningCommand', () async {
      final cmd = await executor.startStreaming('echo streaming');
      final output =
          await cmd.stdout.transform(const SystemEncoding().decoder).join();
      final code = await cmd.exitCode;
      expect(output.trim(), 'streaming');
      expect(code, 0);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/shell/host_executor_test.dart`
Expected: FAIL

**Step 3: Write minimal implementation**

```dart
import 'dart:async';
import 'dart:io';

import 'command_executor.dart';
import 'shell_config.dart';

class HostExecutor implements CommandExecutor {
  final ShellConfig shellConfig;

  HostExecutor(this.shellConfig);

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    final args = shellConfig.buildArgs(command);
    final exe = args.first;
    final rest = args.sublist(1);

    final process = await Process.start(exe, rest);
    final stdoutFuture =
        process.stdout.transform(const SystemEncoding().decoder).join();
    final stderrFuture =
        process.stderr.transform(const SystemEncoding().decoder).join();

    final int exitCode;
    if (timeout == null) {
      exitCode = await process.exitCode;
    } else {
      exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
        process.kill();
        return -1;
      });
    }

    return CaptureResult(
      exitCode: exitCode,
      stdout: await stdoutFuture,
      stderr: await stderrFuture,
    );
  }

  @override
  Future<RunningCommand> startStreaming(String command) async {
    final args = shellConfig.buildArgs(command);
    final exe = args.first;
    final rest = args.sublist(1);
    final process = await Process.start(exe, rest);
    return RunningCommand(process);
  }
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/shell/host_executor_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/shell/host_executor.dart test/shell/host_executor_test.dart
git commit -m "feat: add HostExecutor with shell-aware command execution"
```

---

### Task 4: Wire ShellConfig into GlueConfig

**Files:**

- Modify: `lib/src/config/glue_config.dart`
- Test: `test/config/glue_config_test.dart` (create if not exists)

**Step 1: Write the failing test**

```dart
// Test that GlueConfig exposes shellConfig with defaults
import 'package:test/test.dart';
import '../../lib/src/config/glue_config.dart';
import '../../lib/src/shell/shell_config.dart';

void main() {
  group('GlueConfig shell config', () {
    test('defaults to sh and nonInteractive', () {
      final config = GlueConfig();
      expect(config.shellConfig.executable, 'sh');
      expect(config.shellConfig.mode, ShellMode.nonInteractive);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/config/glue_config_test.dart`
Expected: FAIL (no `shellConfig` field)

**Step 3: Implement**

Add to `GlueConfig`:

- Field: `final ShellConfig shellConfig;`
- Constructor parameter: `ShellConfig? shellConfig`
- Assignment: `shellConfig = shellConfig ?? const ShellConfig()`
- In `GlueConfig.load()`: parse `shell.executable` and `shell.mode` from config file, env vars (`GLUE_SHELL`, `GLUE_SHELL_MODE`), CLI args, and `Platform.environment['SHELL']` for auto-detection. Use `ShellMode.fromString()` to safely parse the mode string — invalid values fall back to `nonInteractive`.

**Step 4: Run test to verify it passes**

Run: `dart test test/config/glue_config_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/config/glue_config.dart lib/src/shell/shell_config.dart test/config/glue_config_test.dart
git commit -m "feat: wire ShellConfig into GlueConfig with env/file/default resolution"
```

---

### Task 5: Migrate BashTool to use CommandExecutor

**Files:**

- Modify: `lib/src/agent/tools.dart` (BashTool class, ~lines 135-201)
- Test: `test/tools/bash_tool_test.dart` (update existing)

**Step 1: Update BashTool to accept a CommandExecutor**

Add `CommandExecutor` field to `BashTool`:

```dart
class BashTool extends Tool {
  final CommandExecutor executor;
  BashTool(this.executor);
  // ...
}
```

**Step 2: Replace Process.start with executor.runCapture**

Replace the body of `execute()`:

```dart
@override
Future<String> execute(Map<String, dynamic> args) async {
  final command = args['command'];
  if (command is! String || command.isEmpty) {
    return 'Error: no command provided';
  }
  final t = args['timeout_seconds'];
  final timeoutSeconds =
      (t is num) ? t.toInt() : AppConstants.bashTimeoutSeconds;
  final timeout = timeoutSeconds == 0
      ? null
      : Duration(seconds: timeoutSeconds);

  final result = await executor.runCapture(command, timeout: timeout);

  if (result.exitCode == -1 && timeout != null) {
    return 'Error: command timed out after $timeoutSeconds seconds';
  }

  final buf = StringBuffer();
  if (result.stdout.isNotEmpty) buf.writeln(result.stdout);
  if (result.stderr.isNotEmpty) buf.writeln('STDERR: ${result.stderr}');
  buf.writeln('Exit code: ${result.exitCode}');
  return buf.toString();
}
```

**Step 3: Update existing tests**

Update `test/tools/bash_tool_test.dart` to construct `BashTool` with a `HostExecutor(ShellConfig())`.

**Step 4: Run tests**

Run: `dart test test/tools/bash_tool_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/agent/tools.dart test/tools/bash_tool_test.dart
git commit -m "refactor: migrate BashTool to CommandExecutor"
```

---

### Task 6: Migrate ShellJobManager to use CommandExecutor

**Files:**

- Modify: `lib/src/shell/shell_job_manager.dart`
- Test: `test/shell/shell_job_manager_test.dart` (update if exists)

**Step 1: Add CommandExecutor to ShellJobManager**

```dart
class ShellJobManager {
  final CommandExecutor executor;
  ShellJobManager(this.executor);
  // ...
}
```

**Step 2: Replace Process.start in start()**

Replace `Process.start('sh', ['-c', command])` with:

```dart
final running = await executor.startStreaming(command);
final process = running.process;
```

The rest of the method (output buffering, exit code tracking) stays the same since it already operates on `Process`.

**Step 3: Run tests**

Run: `dart test test/shell/shell_job_manager_test.dart`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/src/shell/shell_job_manager.dart test/shell/shell_job_manager_test.dart
git commit -m "refactor: migrate ShellJobManager to CommandExecutor"
```

---

### Task 7: Migrate App.\_runBlockingBash to use CommandExecutor

**Files:**

- Modify: `lib/src/app.dart` (~lines 1022-1056)

**Step 1: Add CommandExecutor field to App**

Add field and wire via constructor + `App.create()`.

**Step 2: Replace Process.start in \_runBlockingBash**

Replace the method body to use `executor.runCapture(command)` instead of manual `Process.start`/capture.

**Step 3: Run full test suite**

Run: `dart test`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/src/app.dart
git commit -m "refactor: migrate App bash mode to CommandExecutor"
```

---

### Task 8: Wire executor construction in App.create / main

**Files:**

- Modify: `lib/src/app.dart` (App constructor / create)
- Modify: `bin/glue.dart` (if executor is built there)

**Step 1: Build executor from GlueConfig**

In `App.create()` or wherever `App` is constructed:

```dart
final shellConfig = config.shellConfig;
final executor = HostExecutor(shellConfig);
```

Pass `executor` to `BashTool(executor)`, `ShellJobManager(executor)`, and store on `App`.

**Step 2: Run full test suite + manual smoke test**

Run: `dart test`
Run: `dart run bin/glue.dart` → type `!echo $SHELL` → verify it uses the detected shell

**Step 3: Commit**

```bash
git add lib/src/app.dart bin/glue.dart
git commit -m "feat: wire CommandExecutor from GlueConfig into all shell call sites"
```

---

### Task 9: Update barrel export

**Files:**

- Modify: `lib/glue.dart`

**Step 1: Add exports**

```dart
export 'src/shell/command_executor.dart';
export 'src/shell/host_executor.dart';
export 'src/shell/shell_config.dart';
```

**Step 2: Run dart analyze**

Run: `dart analyze`
Expected: No issues

**Step 3: Commit**

```bash
git add lib/glue.dart
git commit -m "chore: export shell executor types"
```
