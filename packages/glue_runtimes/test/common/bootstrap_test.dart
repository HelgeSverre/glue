import 'dart:io';

import 'package:test/test.dart';

import 'package:glue_runtimes/src/common/bootstrap.dart';

/// Records every `run` invocation and returns scripted results.
class _RecordingExec implements BootstrapExec {
  final Map<String, BootstrapExecResult> scripted;
  final List<String> calls = [];

  _RecordingExec(this.scripted);

  @override
  Future<BootstrapExecResult> run(String shellCommand) async {
    calls.add(shellCommand);
    return scripted[shellCommand] ??
        const BootstrapExecResult(exitCode: 0, output: '');
  }
}

void main() {
  group('WorkspaceBootstrap', () {
    test('resume path: skips clone when /workspace/.git exists', () async {
      final exec = _RecordingExec({
        "test -d '/workspace/.git'": const BootstrapExecResult(
          exitCode: 0,
          output: '',
        ),
      });
      final ws = WorkspaceBootstrap(exec: exec, sessionId: 'test');
      // Bootstrap targets the glue repo (it has a remote + HEAD)
      // but resume should short-circuit before reaching the clone.
      final result = await ws.bootstrap(
        hostCwd: Directory.current.path,
        runtimeCwd: '/workspace',
      );
      expect(result.resumed, isTrue);
      expect(result.bootstrapSha, isNull);
      // Only the probe ran.
      expect(exec.calls, ["test -d '/workspace/.git'"]);
    });

    test('clone path: runs prep, clone, checkout in order', () async {
      // The probe fails (not yet bootstrapped); subsequent commands
      // all succeed.
      final exec = _RecordingExec({
        "test -d '/workspace/.git'": const BootstrapExecResult(
          exitCode: 1,
          output: '',
        ),
      });
      final ws = WorkspaceBootstrap(
        sessionId: 'test',
        exec: exec,
        prepCommand: 'sudo mkdir -p /workspace',
      );
      final result = await ws.bootstrap(
        hostCwd: Directory.current.path,
        runtimeCwd: '/workspace',
      );
      expect(result.resumed, isFalse);
      expect(result.bootstrapSha, isNotNull);
      // Order: probe → prep → clone → checkout.
      expect(exec.calls.length, 4);
      expect(exec.calls[0], "test -d '/workspace/.git'");
      expect(exec.calls[1], 'sudo mkdir -p /workspace');
      expect(exec.calls[2], startsWith('git clone '));
      expect(exec.calls[2], endsWith(" '/workspace'"));
      expect(exec.calls[3], startsWith("cd '/workspace' && git checkout "));
    });

    test('clone path: skips prep when prepCommand is null', () async {
      final exec = _RecordingExec({
        "test -d '/workspace/.git'": const BootstrapExecResult(
          exitCode: 1,
          output: '',
        ),
      });
      final ws = WorkspaceBootstrap(exec: exec, sessionId: 'test');
      await ws.bootstrap(
        hostCwd: Directory.current.path,
        runtimeCwd: '/workspace',
      );
      // Order: probe → clone → checkout (no prep).
      expect(exec.calls.length, 3);
      expect(exec.calls[1], startsWith('git clone '));
    });

    test('prep failure surfaces as BootstrapException(stage: prep)', () async {
      final exec = _RecordingExec({
        "test -d '/workspace/.git'": const BootstrapExecResult(
          exitCode: 1,
          output: '',
        ),
        'sudo bad-cmd': const BootstrapExecResult(
          exitCode: 2,
          output: 'sudo: bad-cmd',
        ),
      });
      final ws = WorkspaceBootstrap(
        sessionId: 'test',
        exec: exec,
        prepCommand: 'sudo bad-cmd',
      );
      await expectLater(
        ws.bootstrap(hostCwd: Directory.current.path, runtimeCwd: '/workspace'),
        throwsA(
          isA<BootstrapException>().having((e) => e.stage, 'stage', 'prep'),
        ),
      );
    });

    test(
      'clone failure surfaces as BootstrapException(stage: clone)',
      () async {
        // Probe fails → no prep set → clone runs and fails.
        final scripted = <String, BootstrapExecResult>{
          "test -d '/workspace/.git'": const BootstrapExecResult(
            exitCode: 1,
            output: '',
          ),
        };
        // We don't know the exact `git clone <url> /workspace` string
        // because it depends on the test cwd's remote — use a custom
        // exec that matches the prefix.
        final exec = _PrefixMatchingExec({
          "test -d '/workspace/.git'": const BootstrapExecResult(
            exitCode: 1,
            output: '',
          ),
          'git clone ': const BootstrapExecResult(
            exitCode: 128,
            output: 'fatal: clone failure',
          ),
        });
        scripted.clear();
        final ws = WorkspaceBootstrap(exec: exec, sessionId: 'test');
        await expectLater(
          ws.bootstrap(
            hostCwd: Directory.current.path,
            runtimeCwd: '/workspace',
          ),
          throwsA(
            isA<BootstrapException>()
                .having((e) => e.stage, 'stage', 'clone')
                .having((e) => e.exitCode, 'exitCode', 128),
          ),
        );
      },
    );

    test(
      'non-git cwd + non-bundle transport throws BootstrapException(clone)',
      () async {
        // Phase 2: a non-git cwd is no longer a hard error when the
        // transport supports bundles — the host-side temp git-dir
        // synthesizes a baseline commit. But for adapters that only
        // implement BootstrapExec (no upload) we fall through to
        // clone-from-remote and that requires a real remote.
        final tmp = Directory.systemTemp.createTempSync('glue-bs-');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final exec = _RecordingExec({
          "test -d '/workspace/.git'": const BootstrapExecResult(
            exitCode: 1,
            output: '',
          ),
        });
        final ws = WorkspaceBootstrap(exec: exec, sessionId: 'test');
        await expectLater(
          ws.bootstrap(hostCwd: tmp.path, runtimeCwd: '/workspace'),
          throwsA(
            isA<BootstrapException>()
                .having((e) => e.stage, 'stage', 'clone')
                .having(
                  (e) => e.message,
                  'message',
                  contains('no bundle transport'),
                ),
          ),
        );
      },
    );
  });
}

/// Like `_RecordingExec` but matches by prefix — lets tests script
/// commands like `git clone …` without knowing the full string.
class _PrefixMatchingExec implements BootstrapExec {
  final Map<String, BootstrapExecResult> scripted;
  final List<String> calls = [];

  _PrefixMatchingExec(this.scripted);

  @override
  Future<BootstrapExecResult> run(String shellCommand) async {
    calls.add(shellCommand);
    for (final entry in scripted.entries) {
      if (shellCommand == entry.key || shellCommand.startsWith(entry.key)) {
        return entry.value;
      }
    }
    return const BootstrapExecResult(exitCode: 0, output: '');
  }
}
