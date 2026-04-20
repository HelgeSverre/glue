import 'package:glue/src/config/build_info.dart';
import 'package:test/test.dart';

void main() {
  group('BuildInfo', () {
    // Compile-time constants are populated from `dart compile --define`.
    // Under `dart test` (no defines), all values are empty and the formatter
    // falls back to a dev build. We assert that contract here and verify
    // shape only; the populated path is covered indirectly by smoke-running
    // the compiled binary in CI.
    test('falls back to dev when no metadata is injected', () {
      expect(BuildInfo.buildTime, isEmpty);
      expect(BuildInfo.gitSha, isEmpty);
      expect(BuildInfo.isReleaseBuild, isFalse);
      expect(BuildInfo.summary, equals('dev'));
    });

    test('details include version header and dev marker', () {
      final out = BuildInfo.details(appVersion: '9.9.9');
      expect(out, contains('glue v9.9.9'));
      expect(out, contains('dev'));
    });

    test('details omit version header when null', () {
      final out = BuildInfo.details();
      expect(out, isNot(contains('glue v')));
      expect(out, contains('dev'));
    });
  });
}
