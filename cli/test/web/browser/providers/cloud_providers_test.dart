import 'package:test/test.dart';
import 'package:glue/src/web/browser/providers/steel_provider.dart';
import 'package:glue/src/web/browser/providers/browserbase_provider.dart';
import 'package:glue/src/web/browser/providers/browserless_provider.dart';

void main() {
  group('SteelProvider', () {
    test('has correct name', () {
      final provider = SteelProvider(apiKey: 'test-key');
      expect(provider.name, 'steel');
    });

    test('is available when API key is set', () {
      final provider = SteelProvider(apiKey: 'test-key');
      expect(provider.isAvailable, isTrue);
    });

    test('is not available without API key', () {
      final provider = SteelProvider(apiKey: null);
      expect(provider.isAvailable, isFalse);
    });
  });

  group('BrowserbaseProvider', () {
    test('has correct name', () {
      final provider = BrowserbaseProvider(
        apiKey: 'key',
        projectId: 'proj',
      );
      expect(provider.name, 'browserbase');
    });

    test('requires both API key and project ID', () {
      expect(
        BrowserbaseProvider(apiKey: 'key', projectId: null).isAvailable,
        isFalse,
      );
      expect(
        BrowserbaseProvider(apiKey: null, projectId: 'proj').isAvailable,
        isFalse,
      );
      expect(
        BrowserbaseProvider(apiKey: 'key', projectId: 'proj').isAvailable,
        isTrue,
      );
    });
  });

  group('BrowserlessProvider', () {
    test('has correct name', () {
      final provider = BrowserlessProvider(
        apiKey: 'key',
        baseUrl: 'https://chrome.example.com',
      );
      expect(provider.name, 'browserless');
    });

    test('is available with API key', () {
      final provider = BrowserlessProvider(
        apiKey: 'key',
        baseUrl: 'https://chrome.example.com',
      );
      expect(provider.isAvailable, isTrue);
    });

    test('builds WebSocket URL from base URL', () {
      final provider = BrowserlessProvider(
        apiKey: 'my-key',
        baseUrl: 'https://chrome.browserless.io',
      );
      final wsUrl = provider.buildWsUrl();
      expect(wsUrl, contains('wss://'));
      expect(wsUrl, contains('my-key'));
    });
  });
}
