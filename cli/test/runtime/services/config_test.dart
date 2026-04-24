import 'dart:convert';
import 'dart:io';

import 'package:glue/src/core/environment.dart';
import 'package:glue/src/runtime/services/config.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Environment environment;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('config_service_test_');
    environment = Environment.test(home: tempDir.path, cwd: tempDir.path);
    environment.ensureDirectories();
    Directory(environment.glueDir).createSync(recursive: true);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('Config.current', () {
    test('returns null when read closure returns null', () {
      final config = Config(
        read: () => null,
        write: (_) {},
        environment: environment,
      );
      expect(config.current, isNull);
    });

    test('read closure is invoked every time current is read', () {
      var callCount = 0;
      final config = Config(
        read: () {
          callCount++;
          return null;
        },
        write: (_) {},
        environment: environment,
      );

      // The service never caches — each access re-reads.
      expect(config.current, isNull);
      expect(config.current, isNull);
      expect(callCount, 2);
    });
  });

  group('Config.trustTool', () {
    Config makeConfig({Iterable<String> initial = const []}) {
      return Config(
        read: () => null,
        write: (_) {},
        environment: environment,
        initialTrustedTools: initial,
      );
    }

    test('adds tool to the live trustedTools set', () {
      final config = makeConfig();
      expect(config.trustedTools, isEmpty);

      config.trustTool('read_file');

      expect(config.trustedTools, contains('read_file'));
    });

    test(
        'is idempotent — trusting the same tool twice is a no-op on '
        'the set', () {
      final config = makeConfig();
      config.trustTool('read_file');
      config.trustTool('read_file');

      expect(config.trustedTools.where((t) => t == 'read_file'), hasLength(1));
    });

    test('persists the tool name to the on-disk config store', () {
      final config = makeConfig();
      config.trustTool('write_file');

      final file = File(environment.configPath);
      expect(file.existsSync(), isTrue);
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect((data['trusted_tools'] as List).cast<String>(),
          contains('write_file'));
    });

    test(
        'second trustTool call on new name appends to existing '
        'on-disk list', () {
      final config = makeConfig();
      config.trustTool('read_file');
      config.trustTool('write_file');

      final file = File(environment.configPath);
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final tools = (data['trusted_tools'] as List).cast<String>();
      expect(tools, containsAll(['read_file', 'write_file']));
    });

    test(
        'preserves existing on-disk trusted_tools entries when adding '
        'a new one', () {
      // Pre-populate a raw config file with a prior trust entry that is
      // NOT passed in via initialTrustedTools — simulates a restart case
      // where disk has state the in-memory set doesn't yet know about.
      File(environment.configPath).writeAsStringSync(jsonEncode({
        'trusted_tools': ['list_directory'],
      }));

      final config = makeConfig();
      config.trustTool('grep');

      final data = jsonDecode(File(environment.configPath).readAsStringSync())
          as Map<String, dynamic>;
      final tools = (data['trusted_tools'] as List).cast<String>();
      expect(tools, containsAll(['list_directory', 'grep']));
    });

    test('swallows persistence errors without throwing', () {
      // Point the environment at a non-writable path (a file where a
      // directory is expected). The in-memory add should still succeed.
      final badDir = File('${tempDir.path}/not_a_dir');
      badDir.writeAsStringSync('blocker');
      final bustedEnv = Environment.test(
        home: tempDir.path,
        cwd: tempDir.path,
        vars: {'GLUE_HOME': badDir.path},
      );
      final config = Config(
        read: () => null,
        write: (_) {},
        environment: bustedEnv,
      );

      expect(() => config.trustTool('danger'), returnsNormally);
      expect(config.trustedTools, contains('danger'));
    });

    test('initialTrustedTools populates the set without touching disk', () {
      final config = makeConfig(initial: {'read_file', 'bash'});
      expect(config.trustedTools, containsAll(['read_file', 'bash']));
      expect(File(environment.configPath).existsSync(), isFalse);
    });

    test(
        'trustedTools exposes a live view — external mutation from '
        'trustTool is visible through the getter', () {
      // Matches the contract PermissionGate relies on: it holds a
      // reference and queries mid-turn.
      final config = makeConfig();
      final liveSet = config.trustedTools;
      expect(liveSet, isEmpty);

      config.trustTool('new_tool');

      expect(liveSet, contains('new_tool'));
    });
  });
}
