import 'package:glue_runtimes/modal.dart';
import 'package:test/test.dart';

void main() {
  group('ModalConfig', () {
    test('defaults are sane', () {
      const c = ModalConfig();
      expect(c.pythonPath, isNull);
      expect(c.modalCliPath, 'modal');
      expect(c.appName, 'glue');
      expect(c.image, isNull);
      expect(c.sandboxTimeoutSeconds, 1800);
      expect(c.deleteOnClose, isTrue);
    });

    test('copyWith overrides selectively', () {
      const original = ModalConfig();
      final next = original.copyWith(
        appName: 'glue-staging',
        image: 'python:3.12-slim',
        sandboxTimeoutSeconds: 600,
      );
      expect(next.appName, 'glue-staging');
      expect(next.image, 'python:3.12-slim');
      expect(next.sandboxTimeoutSeconds, 600);
      expect(next.deleteOnClose, original.deleteOnClose);
    });
  });

  group('modalConfigFromOptions', () {
    test('prefers explicit options over env', () {
      final c = modalConfigFromOptions(
        {
          'python_path': '/opt/py',
          'app_name': 'opt-app',
          'image': 'opt-image',
        },
        env: {
          'MODAL_PYTHON': '/env/py',
          'MODAL_APP': 'env-app',
          'MODAL_IMAGE': 'env-image',
        },
      );
      expect(c.pythonPath, '/opt/py');
      expect(c.appName, 'opt-app');
      expect(c.image, 'opt-image');
    });

    test('falls back to env when options omit a field', () {
      final c = modalConfigFromOptions(
        const {},
        env: const {'MODAL_PYTHON': '/env/py', 'MODAL_APP': 'env-app'},
      );
      expect(c.pythonPath, '/env/py');
      expect(c.appName, 'env-app');
    });

    test('parses sandbox_timeout_seconds from options + env', () {
      final c = modalConfigFromOptions(
        {'sandbox_timeout_seconds': 120},
        env: const {},
      );
      expect(c.sandboxTimeoutSeconds, 120);

      final c2 = modalConfigFromOptions(
        const {},
        env: const {'MODAL_SANDBOX_TIMEOUT': '60'},
      );
      expect(c2.sandboxTimeoutSeconds, 60);
    });

    test('delete_on_close honours bool option + env flag', () {
      final c = modalConfigFromOptions(
        const {'delete_on_close': false},
        env: const {},
      );
      expect(c.deleteOnClose, isFalse);
      final c2 = modalConfigFromOptions(
        const {},
        env: const {'MODAL_DELETE_ON_CLOSE': 'false'},
      );
      expect(c2.deleteOnClose, isFalse);
    });
  });
}
