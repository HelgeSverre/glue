import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:path/path.dart' as p;
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
    expect(
      environment.configPath,
      endsWith(p.join('.glue', 'preferences.json')),
    );
    expect(
      environment.configYamlPath,
      endsWith(p.join('.glue', 'config.yaml')),
    );
    expect(
      environment.sessionDir(const SessionId('abc123')),
      endsWith(p.join('.glue', 'sessions', 'abc123')),
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

  group('tilde expansion of overrides', () {
    test('glueDir expands a leading ~ in GLUE_HOME', () {
      final env = Environment.test(
        home: '/Users/me',
        vars: {'GLUE_HOME': '~/glue'},
      );
      expect(env.glueDir, '/Users/me/glue');
      expect(env.configPath, '/Users/me/glue/preferences.json');
    });

    test('catalogCachePath expands a leading ~ in GLUE_CATALOG_CACHE', () {
      final env = Environment.test(
        home: '/Users/me',
        vars: {'GLUE_CATALOG_CACHE': '~/c/models.yaml'},
      );
      expect(env.catalogCachePath, '/Users/me/c/models.yaml');
    });
  });

  group('shortenPath', () {
    final env = Environment.test(home: '/Users/helge', cwd: '/work');

    test('replaces an exact home match with ~', () {
      expect(env.shortenPath('/Users/helge'), '~');
    });

    test('replaces home + separator with ~/', () {
      expect(env.shortenPath('/Users/helge/code/x'), '~/code/x');
    });

    test('does not match a sibling sharing the home prefix', () {
      expect(env.shortenPath('/Users/helge-backup/x'), '/Users/helge-backup/x');
    });
  });
}
