import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('environment_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('test factory builds expected paths', () {
    final environment = Environment.test(home: tempDir.path, cwd: '/work/cwd');

    expect(environment.home, tempDir.path);
    expect(environment.cwd, '/work/cwd');
    expect(environment.configPath, endsWith('.glue/preferences.json'));
    expect(environment.configYamlPath, endsWith('.glue/config.yaml'));
    expect(
      environment.sessionDir(const SessionId('abc123')),
      endsWith('.glue/sessions/abc123'),
    );
  });

  test('ensureDirectories creates sessions, logs, and cache dirs', () {
    final environment = Environment.test(home: tempDir.path, cwd: tempDir.path);
    environment.ensureDirectories();

    expect(Directory(environment.sessionsDir).existsSync(), isTrue);
    expect(Directory(environment.logsDir).existsSync(), isTrue);
    expect(Directory(environment.cacheDir).existsSync(), isTrue);
  });

  group('remote-or-multiplexed detection', () {
    test('isTmux is true with TMUX env var', () {
      final env = Environment.test(home: '/tmp', vars: {'TMUX': '/tmp/tmux'});
      expect(env.isTmux, isTrue);
    });

    test('isTmux is false without TMUX', () {
      final env = Environment.test(home: '/tmp', vars: {});
      expect(env.isTmux, isFalse);
    });

    test('isRemoteOrMultiplexed detects TMUX', () {
      final env = Environment.test(home: '/tmp', vars: {'TMUX': '/tmp/tmux'});
      expect(env.isRemoteOrMultiplexed, isTrue);
    });

    test('isRemoteOrMultiplexed detects SSH_CONNECTION', () {
      final env = Environment.test(
        home: '/tmp',
        vars: {'SSH_CONNECTION': 'client 22 server 1234'},
      );
      expect(env.isRemoteOrMultiplexed, isTrue);
    });

    test('isRemoteOrMultiplexed detects SSH_TTY', () {
      final env = Environment.test(
        home: '/tmp',
        vars: {'SSH_TTY': '/dev/pts/0'},
      );
      expect(env.isRemoteOrMultiplexed, isTrue);
    });

    test('isRemoteOrMultiplexed is false in clean environment', () {
      final env = Environment.test(home: '/tmp', vars: {});
      expect(env.isRemoteOrMultiplexed, isFalse);
    });
  });
}
