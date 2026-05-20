import 'package:glue/src/terminal/where_report.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';

void main() {
  group('buildWhereReport', () {
    test('renders branded header and lists every expected path row', () {
      final env = Environment.test(home: '/tmp/home');
      final report = buildWhereReport(
        env,
        existsCheck: (_, {required isDir}) => false,
      );

      expect(report, contains('Glue paths'));
      expect(report, contains('/tmp/home/.glue'));
      expect(report, contains('config.yaml'));
      expect(report, contains('preferences.json'));
      expect(report, contains('credentials.json'));
      expect(report, contains('models.yaml'));
      expect(report, contains('sessions/'));
      expect(report, contains('logs/'));
      expect(report, contains('cache/'));
      expect(report, contains('skills/'));
    });

    test('omits the legend footer', () {
      final env = Environment.test(home: '/tmp/home');
      final report = buildWhereReport(
        env,
        existsCheck: (_, {required isDir}) => true,
      );
      expect(report, isNot(contains('Legend')));
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

    test('marks existing paths as present and missing paths as missing', () {
      final env = Environment.test(home: '/tmp/home');
      final report = buildWhereReport(
        env,
        existsCheck: (path, {required isDir}) => path == env.configYamlPath,
      );

      final configLine =
          report.split('\n').firstWhere((line) => line.contains('config.yaml'));
      final sessionsLine =
          report.split('\n').firstWhere((line) => line.contains('sessions/'));
      expect(configLine, contains('present'));
      expect(sessionsLine, contains('missing'));
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
