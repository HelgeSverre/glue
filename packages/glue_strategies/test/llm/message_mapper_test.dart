import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('GeminiMessageMapper user contentParts (M7)', () {
    test('emits inlineData for images and text for text/resource parts', () {
      const mapper = GeminiMessageMapper();
      final messages = [
        Message.user(
          'look at this',
          contentParts: const [
            TextPart('extra text'),
            ImagePart(bytes: [1, 2, 3], mimeType: 'image/png'),
            ResourceLinkPart(uri: 'https://example.com', name: 'Example'),
          ],
        ),
      ];

      final mapped = mapper.mapMessages(messages, systemPrompt: '');
      expect(mapped.messages, hasLength(1));
      final parts = (mapped.messages.single['parts'] as List)
          .cast<Map<String, dynamic>>();

      // Leading message text preserved.
      expect(parts.first, {'text': 'look at this'});
      // TextPart carried through.
      expect(parts.any((p) => p['text'] == 'extra text'), isTrue);
      // ResourceLinkPart rendered as a markdown link.
      expect(
        parts.any((p) => p['text'] == '[Example](https://example.com)'),
        isTrue,
      );
      // ImagePart rendered as inlineData.
      final inline = parts.firstWhere(
        (p) => p.containsKey('inlineData'),
        orElse: () => <String, dynamic>{},
      );
      expect(inline, isNotEmpty);
      final data = (inline['inlineData'] as Map).cast<String, dynamic>();
      expect(data['mimeType'], 'image/png');
      expect(data['data'], isA<String>());
    });

    test('falls back to plain text when no contentParts', () {
      const mapper = GeminiMessageMapper();
      final mapped = mapper.mapMessages([
        Message.user('hello'),
      ], systemPrompt: '');
      final parts = (mapped.messages.single['parts'] as List)
          .cast<Map<String, dynamic>>();
      expect(parts, [
        {'text': 'hello'},
      ]);
    });
  });
}
