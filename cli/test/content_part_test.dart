import 'package:glue/src/agent/content_part.dart';
import 'package:test/test.dart';

void main() {
  group('ContentPart', () {
    test('TextPart stores text', () {
      const part = TextPart('hello');
      expect(part.text, 'hello');
    });

    test('ImagePart stores bytes and mimeType', () {
      const part = ImagePart(bytes: [1, 2, 3], mimeType: 'image/png');
      expect(part.bytes, [1, 2, 3]);
      expect(part.mimeType, 'image/png');
    });

    test('ImagePart.toBase64 encodes correctly', () {
      const part =
          ImagePart(bytes: [72, 101, 108, 108, 111], mimeType: 'image/png');
      expect(part.toBase64(), 'SGVsbG8=');
    });

    test('ContentPart.textOnly concatenates text parts', () {
      final parts = <ContentPart>[
        const TextPart('hello '),
        const ImagePart(bytes: [1], mimeType: 'image/png'),
        const TextPart('world'),
      ];
      expect(ContentPart.textOnly(parts), 'hello world');
    });

    test('ContentPart.textOnly returns empty for no text parts', () {
      final parts = <ContentPart>[
        const ImagePart(bytes: [1], mimeType: 'image/png'),
      ];
      expect(ContentPart.textOnly(parts), '');
    });

    test('ContentPart.hasImages detects image parts', () {
      expect(ContentPart.hasImages([const TextPart('x')]), isFalse);
      expect(
          ContentPart.hasImages([
            const ImagePart(bytes: [1], mimeType: 'image/png')
          ]),
          isTrue);
    });

    test('ContentPart.hasImages returns false for empty list', () {
      expect(ContentPart.hasImages([]), isFalse);
    });
  });
}
