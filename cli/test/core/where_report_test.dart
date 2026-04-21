import 'package:glue/src/core/environment.dart';
import 'package:glue/src/core/where_report.dart';
import 'package:test/test.dart';

void main() {
  group('buildWhereReport', () {
    test('lists every expected path row under GLUE_HOME', () {
      final env = Environment.test(home: '/tmp/home');
      final report = buildWhereReport(
        env,
        existsCheck: (_, {required isDir}) => false,
      );

      expect(report, contains('GLUE_HOME'));
      expect(report, contains('/tmp/home/.glue'));
      expect(report, contains('config.yaml'));
      expect(report, contains('preferences.json'));
      expect(report, contains('credentials.json'));
      expect(report, contains('models.yaml'));
      expect(report, contains('sessions/'));
      expect(report, contains('logs/'));
      expect(report, contains('cache/'));
      expect(report, contains('skills/'));
      expect(report, contains('plans/'));
      expect(report, contains('Legend:'));
    });

    test('notes GLUE_HOME override when set', () {
      final env = Environment.test(
        home: '/tmp/home',
        vars: {'GLUE_HOME': '/custom/glue'},
      );
      final report = buildWhereReport(
        env,
        existsCheck: (_, {required isDir}) => false,
      );

      expect(report, contains('/custom/glue'));
      expect(report, contains(r'(via $GLUE_HOME)'));
    });

    test('marks existing paths with ✓ and missing paths with -', () {
      final env = Environment.test(home: '/tmp/home');
      // Only report the config file as existing.
      final report = buildWhereReport(
        env,
        existsCheck: (path, {required isDir}) => path == env.configYamlPath,
      );

      // The line containing config.yaml should have ✓; sessions/ should show -.
      final configLine =
          report.split('\n').firstWhere((line) => line.contains('config.yaml'));
      final sessionsLine =
          report.split('\n').firstWhere((line) => line.contains('sessions/'));
      expect(configLine, contains('✓'));
      expect(sessionsLine, isNot(contains('✓')));
      expect(sessionsLine, endsWith('-\x1b[0m'));
    });

    test('ends with a trailing newline so callers can stdout.write it', () {
      final env = Environment.test(home: '/tmp/home');
      final report = buildWhereReport(
        env,
        existsCheck: (_, {required isDir}) => true,
      );
      expect(report.endsWith('\n'), isTrue);
    });
  });
}
