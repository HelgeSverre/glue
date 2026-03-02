# Docker Sandbox — Isolated Command Execution Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an optional Docker execution backend that runs shell commands in ephemeral containers with bind-mounted directories, including session-scoped directory whitelisting.

**Architecture:** `DockerExecutor` implements `CommandExecutor` (from shell-executor plan). Uses `docker run --rm` per command with cidfile-based termination. Session-scoped mounts stored in `state.json`. Config additions for image, mounts, shell, and fallback behavior.

**Tech Stack:** Dart 3.4+, `dart:io` Process API, Docker CLI

**Prerequisites:** Shell Executor plan (Tasks 1-9) must be completed first.

**Design docs:** `docs/design/docker-sandbox.md`, `docs/reference/config-yaml.md`, `docs/reference/session-storage.md`

---

### Task 1: DockerConfig Data Model

**Files:**

- Create: `lib/src/shell/docker_config.dart`
- Test: `test/shell/docker_config_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:test/test.dart';
import '../../lib/src/shell/docker_config.dart';

void main() {
  group('MountEntry', () {
    test('parses path without mode suffix', () {
      final m = MountEntry.parse('/some/path');
      expect(m.hostPath, '/some/path');
      expect(m.mode, MountMode.rw);
    });

    test('parses path with :ro suffix', () {
      final m = MountEntry.parse('/some/path:ro');
      expect(m.hostPath, '/some/path');
      expect(m.mode, MountMode.ro);
    });

    test('parses path with :rw suffix', () {
      final m = MountEntry.parse('/some/path:rw');
      expect(m.hostPath, '/some/path');
      expect(m.mode, MountMode.rw);
    });

    test('rejects relative paths', () {
      expect(() => MountEntry.parse('relative/path'), throwsArgumentError);
    });

    test('toDockerArg produces -v flag value', () {
      final m = MountEntry(hostPath: '/host/dir', mode: MountMode.ro);
      expect(m.toDockerArg(), '/host/dir:/host/dir:ro');
    });

    test('toDockerArg for cwd mount maps to /work', () {
      final m = MountEntry(
        hostPath: '/host/project',
        mode: MountMode.rw,
        containerPath: '/work',
      );
      expect(m.toDockerArg(), '/host/project:/work:rw');
    });
  });

  group('DockerConfig', () {
    test('defaults', () {
      final c = DockerConfig();
      expect(c.enabled, false);
      expect(c.image, 'ubuntu:24.04');
      expect(c.shell, 'sh');
      expect(c.fallbackToHost, true);
      expect(c.mounts, isEmpty);
    });
  });

  group('MountEntry.dedup', () {
    test('later entries override earlier for same path', () {
      final a = MountEntry(hostPath: '/foo', mode: MountMode.ro);
      final b = MountEntry(hostPath: '/foo', mode: MountMode.rw);
      final result = MountEntry.dedup([a, b]);
      expect(result, hasLength(1));
      expect(result.first.mode, MountMode.rw);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/shell/docker_config_test.dart`
Expected: FAIL

**Step 3: Write minimal implementation**

```dart
enum MountMode { ro, rw }

class MountEntry {
  final String hostPath;
  final MountMode mode;
  final String? containerPath;
  final DateTime? addedAt;

  MountEntry({
    required this.hostPath,
    this.mode = MountMode.rw,
    this.containerPath,
    this.addedAt,
  });

  factory MountEntry.parse(String spec) {
    final parts = spec.split(':');
    final path = parts.first;
    if (!path.startsWith('/')) {
      throw ArgumentError('Mount path must be absolute: $path');
    }
    final mode = (parts.length > 1 && parts.last == 'ro')
        ? MountMode.ro
        : MountMode.rw;
    return MountEntry(hostPath: path, mode: mode);
  }

  String toDockerArg() {
    final target = containerPath ?? hostPath;
    return '$hostPath:$target:${mode.name}';
  }

  static List<MountEntry> dedup(List<MountEntry> entries) {
    final map = <String, MountEntry>{};
    for (final e in entries) {
      map[e.hostPath] = e;
    }
    return map.values.toList();
  }

  Map<String, dynamic> toJson() => {
        'host_path': hostPath,
        'mode': mode.name,
        if (addedAt != null) 'added_at': addedAt!.toIso8601String(),
      };

  factory MountEntry.fromJson(Map<String, dynamic> json) => MountEntry(
        hostPath: json['host_path'] as String,
        mode: json['mode'] == 'ro' ? MountMode.ro : MountMode.rw,
        addedAt: json['added_at'] != null
            ? DateTime.parse(json['added_at'] as String)
            : null,
      );
}

class DockerConfig {
  final bool enabled;
  final String image;
  final String shell;
  final bool fallbackToHost;
  final List<MountEntry> mounts;

  const DockerConfig({
    this.enabled = false,
    this.image = 'ubuntu:24.04',
    this.shell = 'sh',
    this.fallbackToHost = true,
    this.mounts = const [],
  });
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/shell/docker_config_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/shell/docker_config.dart test/shell/docker_config_test.dart
git commit -m "feat: add DockerConfig and MountEntry data models"
```

---

### Task 2: SessionState with Docker Mounts

**Files:**

- Create: `lib/src/storage/session_state.dart`
- Test: `test/storage/session_state_test.dart`

**Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import '../../lib/src/storage/session_state.dart';
import '../../lib/src/shell/docker_config.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('session_state_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('SessionState', () {
    test('load returns empty state when file missing', () {
      final state = SessionState.load(tmpDir.path);
      expect(state.dockerMounts, isEmpty);
    });

    test('addMount persists to state.json', () {
      final state = SessionState.load(tmpDir.path);
      state.addMount(MountEntry(hostPath: '/test/dir', mode: MountMode.rw));

      final file = File(p.join(tmpDir.path, 'state.json'));
      expect(file.existsSync(), true);

      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(json['version'], 1);
      expect((json['docker']['mounts'] as List), hasLength(1));
    });

    test('removeMount removes by path', () {
      final state = SessionState.load(tmpDir.path);
      state.addMount(MountEntry(hostPath: '/a'));
      state.addMount(MountEntry(hostPath: '/b'));
      state.removeMount('/a');
      expect(state.dockerMounts.map((m) => m.hostPath), ['/b']);
    });

    test('load restores persisted mounts', () {
      final state1 = SessionState.load(tmpDir.path);
      state1.addMount(MountEntry(hostPath: '/persist'));

      final state2 = SessionState.load(tmpDir.path);
      expect(state2.dockerMounts.map((m) => m.hostPath), ['/persist']);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/storage/session_state_test.dart`
Expected: FAIL

**Step 3: Write minimal implementation**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../shell/docker_config.dart';

class SessionState {
  final String _dir;
  final List<MountEntry> _dockerMounts = [];

  SessionState._(this._dir);

  List<MountEntry> get dockerMounts => List.unmodifiable(_dockerMounts);

  factory SessionState.load(String sessionDir) {
    final state = SessionState._(sessionDir);
    final file = File(p.join(sessionDir, 'state.json'));
    if (file.existsSync()) {
      try {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final docker = json['docker'] as Map<String, dynamic>?;
        final mounts = docker?['mounts'] as List?;
        if (mounts != null) {
          for (final m in mounts) {
            state._dockerMounts
                .add(MountEntry.fromJson(m as Map<String, dynamic>));
          }
        }
      } catch (_) {}
    }
    return state;
  }

  void addMount(MountEntry mount) {
    _dockerMounts.removeWhere((m) => m.hostPath == mount.hostPath);
    _dockerMounts.add(mount);
    _persist();
  }

  void removeMount(String hostPath) {
    _dockerMounts.removeWhere((m) => m.hostPath == hostPath);
    _persist();
  }

  void _persist() {
    final file = File(p.join(_dir, 'state.json'));
    file.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync(encoder.convert({
      'version': 1,
      'docker': {
        'mounts': _dockerMounts.map((m) => m.toJson()).toList(),
      },
    }));
  }
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/storage/session_state_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/storage/session_state.dart test/storage/session_state_test.dart
git commit -m "feat: add SessionState with persistent Docker mount whitelist"
```

---

### Task 3: DockerExecutor Implementation

**Files:**

- Create: `lib/src/shell/docker_executor.dart`
- Test: `test/shell/docker_executor_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:test/test.dart';
import '../../lib/src/shell/docker_executor.dart';
import '../../lib/src/shell/docker_config.dart';
import '../../lib/src/shell/command_executor.dart';

void main() {
  group('DockerExecutor', () {
    test('buildDockerArgs constructs correct argument list', () {
      final executor = DockerExecutor(
        config: DockerConfig(image: 'alpine:latest', shell: 'sh'),
        cwd: '/home/user/project',
        mounts: [
          MountEntry(hostPath: '/home/user/libs', mode: MountMode.rw),
          MountEntry(hostPath: '/home/user/data', mode: MountMode.ro),
        ],
      );

      final args = executor.buildDockerArgs('echo hello', '/tmp/cid');
      expect(args, containsAllInOrder([
        'run', '--rm', '-i',
      ]));
      expect(args, contains('--cidfile'));
      expect(args, contains('/tmp/cid'));
      expect(args, contains('-w'));
      expect(args, contains('/work'));
      expect(args, contains('alpine:latest'));
      // Last args: shell -c command
      expect(args.last, 'echo hello');
    });

    // Integration test — only runs if Docker is available
    test('runCapture executes in container', () async {
      final result = await Process.run('docker', ['--version']);
      if (result.exitCode != 0) {
        markTestSkipped('Docker not available');
        return;
      }

      final executor = DockerExecutor(
        config: DockerConfig(image: 'alpine:latest', shell: 'sh'),
        cwd: Directory.current.path,
        mounts: [],
      );

      final r = await executor.runCapture('echo hello');
      expect(r.stdout.trim(), 'hello');
      expect(r.exitCode, 0);
    }, timeout: Timeout(Duration(seconds: 30)));
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/shell/docker_executor_test.dart`
Expected: FAIL

**Step 3: Write implementation**

```dart
import 'dart:async';
import 'dart:io';

import 'command_executor.dart';
import 'docker_config.dart';

class DockerExecutor implements CommandExecutor {
  final DockerConfig config;
  final String cwd;
  final List<MountEntry> mounts;

  DockerExecutor({
    required this.config,
    required this.cwd,
    required this.mounts,
  });

  List<String> buildDockerArgs(String command, String cidfilePath) {
    final args = <String>[
      'run', '--rm', '-i',
      '--cidfile', cidfilePath,
      '-w', '/work',
      '-v', '$cwd:/work:rw',
    ];

    for (final mount in MountEntry.dedup(mounts)) {
      args.addAll(['-v', mount.toDockerArg()]);
    }

    args.addAll([
      config.image,
      config.shell, '-c', command,
    ]);

    return args;
  }

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    final cidfile = _tempCidfile();
    try {
      final args = buildDockerArgs(command, cidfile.path);
      final process = await Process.start('docker', args);

      final stdoutFuture =
          process.stdout.transform(const SystemEncoding().decoder).join();
      final stderrFuture =
          process.stderr.transform(const SystemEncoding().decoder).join();

      final int exitCode;
      if (timeout == null) {
        exitCode = await process.exitCode;
      } else {
        exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
          _killContainer(cidfile);
          process.kill();
          return -1;
        });
      }

      return CaptureResult(
        exitCode: exitCode,
        stdout: await stdoutFuture,
        stderr: await stderrFuture,
      );
    } finally {
      _cleanupCidfile(cidfile);
    }
  }

  @override
  Future<RunningCommand> startStreaming(String command) async {
    final cidfile = _tempCidfile();
    final args = buildDockerArgs(command, cidfile.path);
    final process = await Process.start('docker', args);
    return DockerRunningCommand(process, cidfile);
  }

  File _tempCidfile() {
    final dir = Directory.systemTemp;
    final name = 'glue-cid-${DateTime.now().microsecondsSinceEpoch}';
    return File('${dir.path}/$name');
  }

  void _killContainer(File cidfile) {
    try {
      if (cidfile.existsSync()) {
        final cid = cidfile.readAsStringSync().trim();
        if (cid.isNotEmpty) {
          Process.runSync('docker', ['stop', '-t', '5', cid]);
        }
      }
    } catch (_) {}
  }

  void _cleanupCidfile(File cidfile) {
    try {
      if (cidfile.existsSync()) cidfile.deleteSync();
    } catch (_) {}
  }
}

class DockerRunningCommand extends RunningCommand {
  final File _cidfile;

  DockerRunningCommand(super.process, this._cidfile);

  @override
  Future<void> kill() async {
    try {
      if (_cidfile.existsSync()) {
        final cid = (await _cidfile.readAsString()).trim();
        if (cid.isNotEmpty) {
          await Process.run('docker', ['stop', '-t', '5', cid]);
        }
      }
    } catch (_) {}
    await super.kill();
    try {
      if (_cidfile.existsSync()) _cidfile.deleteSync();
    } catch (_) {}
  }
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/shell/docker_executor_test.dart`
Expected: PASS (unit test passes; integration test skipped if no Docker)

**Step 5: Commit**

```bash
git add lib/src/shell/docker_executor.dart test/shell/docker_executor_test.dart
git commit -m "feat: add DockerExecutor with cidfile-based container management"
```

---

### Task 4: Wire DockerConfig into GlueConfig

**Files:**

- Modify: `lib/src/config/glue_config.dart`
- Modify: `test/config/glue_config_test.dart`

**Step 1: Write the failing test**

```dart
test('GlueConfig exposes dockerConfig with defaults', () {
  final config = GlueConfig();
  expect(config.dockerConfig.enabled, false);
  expect(config.dockerConfig.image, 'ubuntu:24.04');
  expect(config.dockerConfig.shell, 'sh');
  expect(config.dockerConfig.fallbackToHost, true);
  expect(config.dockerConfig.mounts, isEmpty);
});
```

**Step 2: Run test to verify it fails**

Run: `dart test test/config/glue_config_test.dart`
Expected: FAIL

**Step 3: Implement**

Add `DockerConfig dockerConfig` field to `GlueConfig`. Parse `docker.*` from config file and env vars in `GlueConfig.load()`. Parse `GLUE_DOCKER_MOUNTS` (semicolon-separated) and `GLUE_DOCKER_ENABLED`.

**Step 4: Run test to verify it passes**

Run: `dart test test/config/glue_config_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/config/glue_config.dart test/config/glue_config_test.dart
git commit -m "feat: wire DockerConfig into GlueConfig"
```

---

### Task 5: Docker Availability Check + Fallback Logic

**Files:**

- Modify: `lib/src/shell/docker_executor.dart`
- Create: `lib/src/shell/executor_factory.dart`
- Test: `test/shell/executor_factory_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:test/test.dart';
import '../../lib/src/shell/executor_factory.dart';
import '../../lib/src/shell/shell_config.dart';
import '../../lib/src/shell/docker_config.dart';
import '../../lib/src/shell/host_executor.dart';

void main() {
  group('ExecutorFactory', () {
    test('returns HostExecutor when docker disabled', () async {
      final executor = await ExecutorFactory.create(
        shellConfig: ShellConfig(),
        dockerConfig: DockerConfig(enabled: false),
        cwd: Directory.current.path,
      );
      expect(executor, isA<HostExecutor>());
    });

    test('returns HostExecutor with fallback when docker unavailable', () async {
      final executor = await ExecutorFactory.create(
        shellConfig: ShellConfig(),
        dockerConfig: DockerConfig(enabled: true, fallbackToHost: true),
        cwd: Directory.current.path,
        dockerAvailable: false,
      );
      expect(executor, isA<HostExecutor>());
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/shell/executor_factory_test.dart`
Expected: FAIL

**Step 3: Implement factory**

```dart
import 'dart:io';
import 'command_executor.dart';
import 'docker_config.dart';
import 'docker_executor.dart';
import 'host_executor.dart';
import 'shell_config.dart';

class ExecutorFactory {
  static Future<CommandExecutor> create({
    required ShellConfig shellConfig,
    required DockerConfig dockerConfig,
    required String cwd,
    List<MountEntry> sessionMounts = const [],
    bool? dockerAvailable,
  }) async {
    if (!dockerConfig.enabled) {
      return HostExecutor(shellConfig);
    }

    final available = dockerAvailable ?? await _checkDocker();
    if (!available) {
      if (dockerConfig.fallbackToHost) {
        return HostExecutor(shellConfig);
      }
      throw StateError('Docker is required but not available');
    }

    final allMounts = [...dockerConfig.mounts, ...sessionMounts];
    return DockerExecutor(
      config: dockerConfig,
      cwd: cwd,
      mounts: allMounts,
    );
  }

  static Future<bool> _checkDocker() async {
    try {
      final result = await Process.run('docker', ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
```

**Step 4: Run test to verify it passes**

Run: `dart test test/shell/executor_factory_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/shell/executor_factory.dart test/shell/executor_factory_test.dart
git commit -m "feat: add ExecutorFactory with Docker availability check and fallback"
```

---

### Task 6: Wire SessionState + ExecutorFactory into App

**Files:**

- Modify: `lib/src/app.dart`
- Modify: `lib/src/storage/glue_home.dart` (if needed)

**Step 1: Add SessionState to App**

Load `SessionState` from the session directory alongside `SessionStore`. Pass session mounts to `ExecutorFactory.create()`.

**Step 2: Use ExecutorFactory in App.create()**

Replace the direct `HostExecutor` construction with `ExecutorFactory.create()`.

**Step 3: Run full test suite**

Run: `dart test`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/src/app.dart
git commit -m "feat: wire SessionState and ExecutorFactory into App"
```

---

### Task 7: Update barrel exports + final cleanup

**Files:**

- Modify: `lib/glue.dart`

**Step 1: Add exports**

```dart
export 'src/shell/docker_config.dart';
export 'src/shell/docker_executor.dart';
export 'src/shell/executor_factory.dart';
export 'src/storage/session_state.dart';
```

**Step 2: Run dart analyze**

Run: `dart analyze`
Expected: No issues

**Step 3: Run full test suite**

Run: `dart test`
Expected: All PASS

**Step 4: Commit**

```bash
git add lib/glue.dart
git commit -m "chore: export Docker sandbox types and update barrel"
```
