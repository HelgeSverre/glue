import 'package:glue/src/web/fetch/truncation.dart';
import 'package:test/test.dart';

void main() {
  group('TokenTruncation', () {
    test('does not truncate short content', () {
      final result = TokenTruncation.truncate('Hello world.', maxTokens: 1000);
      expect(result, 'Hello world.');
    });

    test('truncates long content at paragraph boundary', () {
      final paragraphs = List.generate(100, (i) => 'Paragraph $i content.');
      final content = paragraphs.join('\n\n');
      final result = TokenTruncation.truncate(content, maxTokens: 50);
      expect(result.length, lessThan(content.length));
      expect(result, contains('(truncated'));
    });

    test('estimates tokens from char count', () {
      expect(TokenTruncation.estimateTokens(''), 0);
      expect(TokenTruncation.estimateTokens('four'), 1);
      expect(TokenTruncation.estimateTokens('a' * 400), 100);
    });

    test('preserves content within budget', () {
      const content = 'First paragraph.\n\nSecond paragraph.';
      final result = TokenTruncation.truncate(content, maxTokens: 100);
      expect(result, content);
    });
  });
}
