import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('RuntimeDiagnosticContext.optionOrEnv', () {
    test('prefers the typed option over env', () {
      const ctx = RuntimeDiagnosticContext(
        options: {'cli': 'from-opt'},
        env: _emptyEnv,
      );
      expect(ctx.optionOrEnv('cli', 'CLI_ENV'), 'from-opt');
    });

    test('honours a present-but-empty option string', () {
      final ctx = RuntimeDiagnosticContext(
        options: const {'cli': ''},
        env: (k) => 'env-val',
      );
      expect(ctx.optionOrEnv('cli', 'CLI_ENV'), '');
    });

    test('falls back to env when the option is absent', () {
      final ctx = RuntimeDiagnosticContext(
        options: const {},
        env: (k) => k == 'CLI_ENV' ? 'env-val' : null,
      );
      expect(ctx.optionOrEnv('cli', 'CLI_ENV'), 'env-val');
    });

    test('null when neither option nor env provide a value', () {
      const ctx = RuntimeDiagnosticContext(options: {}, env: _emptyEnv);
      expect(ctx.optionOrEnv('cli', 'CLI_ENV'), isNull);
    });
  });

  group('RuntimeFactory diagnostics registry', () {
    test('diagnose runs the registered diagnoser for a runtime', () {
      RuntimeFactory.registerDiagnostics(
        '_diag_test',
        (ctx) => [
          RuntimeDiagnostic.ok('opt=${ctx.options['k']}'),
          const RuntimeDiagnostic.warn('warned'),
        ],
      );
      const ctx = RuntimeDiagnosticContext(options: {'k': 'v'}, env: _emptyEnv);
      final out = RuntimeFactory.diagnose('_diag_test', ctx).toList();
      expect(out, hasLength(2));
      expect(out.first.message, 'opt=v');
      expect(out[1].level, RuntimeDiagnosticLevel.warn);
    });

    test('diagnose returns nothing for an unregistered runtime', () {
      const ctx = RuntimeDiagnosticContext(options: {}, env: _emptyEnv);
      expect(RuntimeFactory.diagnose('_no_such_runtime', ctx), isEmpty);
    });
  });
}

String? _emptyEnv(String key) => null;
