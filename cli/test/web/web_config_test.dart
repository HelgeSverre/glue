import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('WebFetchConfig', () {
    test('defaults are sensible', () {
      const config = WebFetchConfig();
      expect(config.timeoutSeconds, 30);
      expect(config.maxBytes, 5 * 1024 * 1024);
      expect(config.defaultMaxTokens, 50000);
      expect(config.allowJinaFallback, isTrue);
    });
  });

  group('PdfConfig', () {
    test('defaults are sensible', () {
      const config = PdfConfig();
      expect(config.maxBytes, 20 * 1024 * 1024);
      expect(config.timeoutSeconds, 60);
      expect(config.enableOcrFallback, isTrue);
      expect(config.ocrProvider, OcrProviderType.mistral);
    });

    test('hasOcrCredentials returns false when no keys set', () {
      const config = PdfConfig();
      expect(config.hasOcrCredentials, isFalse);
    });

    test('hasOcrCredentials returns true with mistral key', () {
      const config = PdfConfig(mistralApiKey: 'key');
      expect(config.hasOcrCredentials, isTrue);
    });

    test('hasOcrCredentials checks openai key when provider is openai', () {
      const config = PdfConfig(
        ocrProvider: OcrProviderType.openai,
        openaiApiKey: 'key',
      );
      expect(config.hasOcrCredentials, isTrue);
    });

    test('hasOcrCredentials false for empty string key', () {
      const config = PdfConfig(mistralApiKey: '');
      expect(config.hasOcrCredentials, isFalse);
    });
  });
}
