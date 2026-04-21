import 'package:glue/src/web/browser/browser_config.dart';
import 'package:test/test.dart';

void main() {
  group('BrowserConfig', () {
    test('defaults to local backend', () {
      const config = BrowserConfig();
      expect(config.backend, BrowserBackend.local);
      expect(config.headed, isFalse);
    });

    test('local is always configured', () {
      const config = BrowserConfig(backend: BrowserBackend.local);
      expect(config.isConfigured, isTrue);
    });

    test('docker is always configured', () {
      const config = BrowserConfig(backend: BrowserBackend.docker);
      expect(config.isConfigured, isTrue);
    });

    test('steel requires API key', () {
      const config = BrowserConfig(backend: BrowserBackend.steel);
      expect(config.isConfigured, isFalse);

      const configured = BrowserConfig(
        backend: BrowserBackend.steel,
        steelApiKey: 'key',
      );
      expect(configured.isConfigured, isTrue);
    });

    test('browserbase requires API key and project ID', () {
      const noKey = BrowserConfig(backend: BrowserBackend.browserbase);
      expect(noKey.isConfigured, isFalse);

      const onlyKey = BrowserConfig(
        backend: BrowserBackend.browserbase,
        browserbaseApiKey: 'key',
      );
      expect(onlyKey.isConfigured, isFalse);

      const both = BrowserConfig(
        backend: BrowserBackend.browserbase,
        browserbaseApiKey: 'key',
        browserbaseProjectId: 'proj',
      );
      expect(both.isConfigured, isTrue);
    });

    test('browserless requires API key', () {
      const config = BrowserConfig(backend: BrowserBackend.browserless);
      expect(config.isConfigured, isFalse);

      const configured = BrowserConfig(
        backend: BrowserBackend.browserless,
        browserlessApiKey: 'key',
      );
      expect(configured.isConfigured, isTrue);
    });

    test('anchor requires API key', () {
      const config = BrowserConfig(backend: BrowserBackend.anchor);
      expect(config.isConfigured, isFalse);

      const configured = BrowserConfig(
        backend: BrowserBackend.anchor,
        anchorApiKey: 'key',
      );
      expect(configured.isConfigured, isTrue);
    });

    test('hyperbrowser requires API key', () {
      const config = BrowserConfig(backend: BrowserBackend.hyperbrowser);
      expect(config.isConfigured, isFalse);

      const configured = BrowserConfig(
        backend: BrowserBackend.hyperbrowser,
        hyperbrowserApiKey: 'key',
      );
      expect(configured.isConfigured, isTrue);
    });

    test('empty string key is treated as not configured', () {
      const config = BrowserConfig(
        backend: BrowserBackend.steel,
        steelApiKey: '',
      );
      expect(config.isConfigured, isFalse);
    });
  });
}
