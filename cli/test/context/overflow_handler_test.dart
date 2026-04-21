import 'package:glue/src/context/overflow_handler.dart';
import 'package:test/test.dart';

void main() {
  group('OverflowClassifier', () {
    test('classifies Anthropic prompt-too-long error', () {
      final err = Exception('Anthropic API error 400: prompt is too long');
      expect(OverflowClassifier.classify(err), isA<ContextOverflowException>());
    });

    test('classifies OpenAI context_length_exceeded', () {
      final err = Exception(
        'OpenAI API error 400: This model\'s maximum context length is '
        '16385 tokens. context length exceeded',
      );
      expect(OverflowClassifier.classify(err), isA<ContextOverflowException>());
    });

    test('classifies Ollama context length exceeded', () {
      final err = Exception('context length exceeded');
      expect(OverflowClassifier.classify(err), isA<ContextOverflowException>());
    });

    test('classifies too many tokens error', () {
      final err = Exception('too many tokens in input');
      expect(OverflowClassifier.classify(err), isA<ContextOverflowException>());
    });

    test('classifies context window exceeded', () {
      final err = Exception('context window exceeded for model gpt-4o');
      expect(OverflowClassifier.classify(err), isA<ContextOverflowException>());
    });

    test('returns null for unrelated errors', () {
      final err = Exception('network timeout');
      expect(OverflowClassifier.classify(err), isNull);
    });

    test('returns null for auth errors', () {
      final err = Exception('401 unauthorized');
      expect(OverflowClassifier.classify(err), isNull);
    });

    test('returns null for rate limit errors', () {
      final err = Exception('429 too many requests');
      expect(OverflowClassifier.classify(err), isNull);
    });

    test('ContextOverflowException toString contains provider and message', () {
      const ex = ContextOverflowException(
        provider: 'anthropic',
        rawMessage: 'prompt is too long',
      );
      expect(ex.toString(), contains('anthropic'));
      expect(ex.toString(), contains('context window exceeded'));
    });
  });
}
