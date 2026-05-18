import 'package:glue_runtimes/daytona.dart';
import 'package:test/test.dart';

void main() {
  group('DaytonaConfig', () {
    test('defaults to US control plane + no toolbox override', () {
      const c = DaytonaConfig(apiKey: 'sk-test');
      expect(c.apiKey, 'sk-test');
      expect(c.apiBaseUrl, 'https://app.daytona.io/api');
      expect(c.toolboxBaseUrlOverride, isNull);
      expect(c.snapshot, isNull);
    });

    test('copyWith overrides selectively', () {
      const original = DaytonaConfig(apiKey: 'a');
      final next = original.copyWith(
        apiBaseUrl: 'https://app-eu.daytona.io/api',
        snapshot: 'glue-base:1',
      );
      expect(next.apiKey, 'a');
      expect(next.apiBaseUrl, 'https://app-eu.daytona.io/api');
      expect(next.snapshot, 'glue-base:1');
    });
  });

  group('daytonaConfigFromOptions', () {
    test('prefers explicit options over env', () {
      final c = daytonaConfigFromOptions(
        {
          'api_key': 'from-opts',
          'api_base_url': 'https://app-eu.daytona.io/api',
          'snapshot': 'snap-1',
        },
        env: {
          'DAYTONA_API_KEY': 'from-env',
          'DAYTONA_API_BASE_URL': 'https://app.daytona.io/api',
          'DAYTONA_SNAPSHOT': 'snap-env',
        },
      );
      expect(c.apiKey, 'from-opts');
      expect(c.apiBaseUrl, 'https://app-eu.daytona.io/api');
      expect(c.snapshot, 'snap-1');
    });

    test('falls back to env when options omit a field', () {
      final c = daytonaConfigFromOptions(
        const {},
        env: const {'DAYTONA_API_KEY': 'env-key'},
      );
      expect(c.apiKey, 'env-key');
      expect(c.apiBaseUrl, 'https://app.daytona.io/api');
    });

    test('returns empty api key when neither options nor env provide one',
        () {
      final c = daytonaConfigFromOptions(const {}, env: const {});
      expect(c.apiKey, '');
    });

    test('honours toolbox override from options', () {
      final c = daytonaConfigFromOptions(
        const {'toolbox_base_url': 'https://proxy.staging/'},
        env: const {},
      );
      expect(c.toolboxBaseUrlOverride, 'https://proxy.staging/');
    });
  });
}
