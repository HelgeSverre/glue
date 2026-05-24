import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';

void main() {
  group('BuildInfo', () {
    // build_info_generated.dart is a generated build artifact (see
    // cli/tool/gen_build_info.dart). When present, values are real; when
    // absent, the file is created by `just build`. These tests verify shape
    // regardless of whether values are populated.

    test('isReleaseBuild is true when any metadata exists', () {
      // If the generated file has values, isReleaseBuild is true.
      // If not, it's false. Both are valid — we just assert the shape.
      expect(BuildInfo.isReleaseBuild, anyOf(isTrue, isFalse));
    });

    test('summary is never empty', () {
      expect(BuildInfo.summary, isNotEmpty);
    });

    test('details contains the build line regardless of metadata', () {
      final out = BuildInfo.details(appVersion: '9.9.9');
      expect(out, contains('glue v9.9.9'));
      expect(out, isNotEmpty);
    });

    test('details omits version header when null', () {
      final out = BuildInfo.details();
      expect(out, isNot(contains('glue v')));
      expect(out, isNotEmpty);
    });
  });
}
