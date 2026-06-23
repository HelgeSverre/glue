import 'package:glue_runtimes/daytona.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

RuntimeDiagnosticContext _ctx(
  Map<String, Object?> options,
  Map<String, String> env,
) => RuntimeDiagnosticContext(options: options, env: (k) => env[k]);

void main() {
  group('daytonaDiagnostics', () {
    test('errors when no api key in options or env', () {
      final out = daytonaDiagnostics(_ctx(const {}, const {})).toList();
      final key = out.first;
      expect(key.level, RuntimeDiagnosticLevel.error);
      expect(key.message, contains('DAYTONA_API_KEY missing'));
    });

    test('ok when api key present via env', () {
      final out = daytonaDiagnostics(
        _ctx(const {}, const {'DAYTONA_API_KEY': 'sk-test'}),
      ).toList();
      expect(out.first.level, RuntimeDiagnosticLevel.ok);
      expect(out.first.message, 'DAYTONA_API_KEY: present');
    });

    test('ok when api key present via options', () {
      final out = daytonaDiagnostics(
        _ctx(const {'api_key': 'sk-opt'}, const {}),
      ).toList();
      expect(out.first.level, RuntimeDiagnosticLevel.ok);
    });

    test('default sandbox shape is info when no snapshot', () {
      final out = daytonaDiagnostics(
        _ctx(const {'api_key': 'k'}, const {}),
      ).toList();
      expect(out[1].level, RuntimeDiagnosticLevel.info);
      expect(out[1].message, contains('default sandbox shape'));
    });

    test('snapshot from options surfaces as info', () {
      final out = daytonaDiagnostics(
        _ctx(const {'api_key': 'k', 'snapshot': 'glue-base:1'}, const {}),
      ).toList();
      expect(out[1].message, 'Daytona snapshot: glue-base:1');
    });
  });
}
