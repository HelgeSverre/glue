import 'package:test/test.dart';
import 'package:glue/src/web/browser/browser_manager.dart';
import 'package:glue/src/web/browser/browser_endpoint.dart';

class _MockProvider implements BrowserEndpointProvider {
  bool provisioned = false;
  bool closed = false;
  int provisionCount = 0;
  Duration provisionDelay = Duration.zero;

  @override
  String get name => 'mock';

  @override
  bool get isConfigured => true;

  @override
  @Deprecated('Use isConfigured instead.')
  bool get isAvailable => isConfigured;

  @override
  Future<BrowserEndpoint> provision() async {
    if (provisionDelay > Duration.zero) {
      await Future.delayed(provisionDelay);
    }
    provisioned = true;
    provisionCount++;
    return BrowserEndpoint(
      cdpWsUrl: 'ws://localhost:9222/devtools/browser/mock',
      backendName: 'mock',
      onClose: () async {
        closed = true;
      },
    );
  }
}

void main() {
  group('BrowserManager', () {
    late BrowserManager manager;
    late _MockProvider provider;

    setUp(() {
      provider = _MockProvider();
      manager = BrowserManager(provider: provider);
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('is not connected initially', () {
      expect(manager.isConnected, isFalse);
    });

    test('provisions on first getEndpoint call', () async {
      final endpoint = await manager.getEndpoint();
      expect(endpoint, isNotNull);
      expect(provider.provisioned, isTrue);
      expect(manager.isConnected, isTrue);
    });

    test('reuses endpoint on subsequent calls', () async {
      final first = await manager.getEndpoint();
      final second = await manager.getEndpoint();
      expect(identical(first, second), isTrue);
      expect(provider.provisionCount, 1);
    });

    test('dispose closes endpoint', () async {
      await manager.getEndpoint();
      await manager.dispose();
      expect(provider.closed, isTrue);
      expect(manager.isConnected, isFalse);
    });

    test('can reconnect after dispose', () async {
      await manager.getEndpoint();
      await manager.dispose();
      expect(manager.isConnected, isFalse);

      final endpoint = await manager.getEndpoint();
      expect(endpoint, isNotNull);
      expect(provider.provisionCount, 2);
    });

    test('dispose during provision closes the new endpoint', () async {
      provider.provisionDelay = const Duration(milliseconds: 50);

      // Start provisioning but don't await it.
      final future = manager.getEndpoint();

      // Dispose while provision is in-flight.
      await manager.dispose();

      // The endpoint should still be returned from the future...
      final endpoint = await future;
      expect(endpoint, isNotNull);

      // ...but the manager should have cleaned it up.
      expect(provider.closed, isTrue);
    });

    test('getEndpoint after dispose-during-provision re-provisions', () async {
      provider.provisionDelay = const Duration(milliseconds: 50);

      final future = manager.getEndpoint();
      await manager.dispose();
      await future;

      // A new call should provision again.
      provider.provisionDelay = Duration.zero;
      final ep = await manager.getEndpoint();
      expect(ep, isNotNull);
      expect(provider.provisionCount, 2);
    });
  });
}
