import 'dart:io';

import 'package:glue/src/commands/setup_command.dart';
import 'package:test/test.dart';

void main() {
  group('SetupCommand', () {
    test('check mode returns guidance without mutating GLUE_HOME', () async {
      final tmp = Directory.systemTemp.createTempSync('glue_setup_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final result = await runGlueSetupCheckForTest(
        environment: {'GLUE_HOME': tmp.path},
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Glue setup'));
      expect(result.stdout, contains('glue config init'));
      expect(result.stdout, contains('glue doctor'));
      expect(File('${tmp.path}/config.yaml').existsSync(), isFalse);
    });
  });
}
