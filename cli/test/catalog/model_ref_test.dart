import 'package:glue/src/catalog/model_ref.dart';
import 'package:test/test.dart';

void main() {
  group('ModelRef.parse', () {
    test('splits provider and model on the first slash', () {
      final ref = ModelRef.parse('anthropic/claude-sonnet-4.6');
      expect(ref.providerId, 'anthropic');
      expect(ref.modelId, 'claude-sonnet-4.6');
    });

    test('splits only on the first slash so model ids can contain slashes', () {
      final ref = ModelRef.parse('openrouter/anthropic/claude-sonnet-4.6');
      expect(ref.providerId, 'openrouter');
      expect(ref.modelId, 'anthropic/claude-sonnet-4.6');
    });

    test('handles ollama tags containing colons', () {
      final ref = ModelRef.parse('ollama/qwen2.5-coder:32b');
      expect(ref.providerId, 'ollama');
      expect(ref.modelId, 'qwen2.5-coder:32b');
    });

    test('throws on empty string', () {
      expect(() => ModelRef.parse(''), throwsA(isA<ModelRefParseException>()));
    });

    test('throws on no slash', () {
      expect(
        () => ModelRef.parse('claude-sonnet'),
        throwsA(isA<ModelRefParseException>()),
      );
    });

    test('throws on missing provider', () {
      expect(
        () => ModelRef.parse('/claude-sonnet'),
        throwsA(isA<ModelRefParseException>()),
      );
    });

    test('throws on missing model', () {
      expect(
        () => ModelRef.parse('anthropic/'),
        throwsA(isA<ModelRefParseException>()),
      );
    });

    test('toString round-trips', () {
      const input = 'openrouter/anthropic/claude-sonnet-4.6';
      expect(ModelRef.parse(input).toString(), input);
    });

    test('equality is structural', () {
      expect(
        ModelRef.parse('anthropic/claude'),
        equals(ModelRef.parse('anthropic/claude')),
      );
      expect(
        ModelRef.parse('anthropic/claude'),
        isNot(equals(ModelRef.parse('openai/claude'))),
      );
    });
  });

  group('ModelRef.tryParse', () {
    test('returns null on malformed input', () {
      expect(ModelRef.tryParse('no-slash'), isNull);
      expect(ModelRef.tryParse(''), isNull);
      expect(ModelRef.tryParse('anthropic/'), isNull);
    });

    test('returns a ref on well-formed input', () {
      final ref = ModelRef.tryParse('anthropic/claude')!;
      expect(ref.providerId, 'anthropic');
      expect(ref.modelId, 'claude');
    });
  });
}
