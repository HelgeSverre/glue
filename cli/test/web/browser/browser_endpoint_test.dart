import 'package:glue/src/web/browser/browser_endpoint.dart';
import 'package:test/test.dart';

void main() {
  group('BrowserEndpoint', () {
    test('holds CDP WebSocket URL', () {
      final endpoint = BrowserEndpoint(
        cdpWsUrl: 'ws://localhost:9222/devtools/browser/abc',
        backendName: 'local',
      );
      expect(endpoint.cdpWsUrl, 'ws://localhost:9222/devtools/browser/abc');
      expect(endpoint.backendName, 'local');
      expect(endpoint.viewUrl, isNull);
    });

    test('holds debug info for cloud providers', () {
      final endpoint = BrowserEndpoint(
        cdpWsUrl: 'wss://cloud.example.com/ws',
        backendName: 'steel',
        viewUrl: 'https://app.steel.dev/sessions/123',
        headed: false,
      );
      expect(endpoint.viewUrl, isNotNull);
    });

    test('debugFooter formats correctly', () {
      final endpoint = BrowserEndpoint(
        cdpWsUrl: 'ws://localhost:9222/devtools/browser/abc',
        backendName: 'local',
        headed: true,
      );
      final footer = endpoint.debugFooter;
      expect(footer, contains('local'));
      expect(footer, contains('headed'));
    });

    test('debugFooter includes view URL when present', () {
      final endpoint = BrowserEndpoint(
        cdpWsUrl: 'wss://cloud.example.com/ws',
        backendName: 'steel',
        viewUrl: 'https://app.steel.dev/sessions/123',
      );
      final footer = endpoint.debugFooter;
      expect(footer, contains('https://app.steel.dev/sessions/123'));
    });
  });
}
