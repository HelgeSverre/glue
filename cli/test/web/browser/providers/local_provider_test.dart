import 'package:glue/src/web/browser/browser_config.dart';
import 'package:glue/src/web/browser/providers/local_provider.dart';
import 'package:test/test.dart';

void main() {
  group('LocalProvider', () {
    test('has correct name', () {
      final provider = LocalProvider(const BrowserConfig());
      expect(provider.name, 'local');
    });

    test('is always configured', () {
      final provider = LocalProvider(const BrowserConfig());
      expect(provider.isConfigured, isTrue);
    });

    test('respects headed config', () {
      final provider = LocalProvider(
        const BrowserConfig(headed: true),
      );
      expect(provider.headed, isTrue);
    });
  });
}
