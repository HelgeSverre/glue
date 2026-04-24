import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:test/test.dart';

void main() {
  group('ToolResult contentParts', () {
    test('stores contentParts when provided', () {
      final parts = [
        const TextPart('hello'),
        const ImagePart(bytes: [1, 2, 3], mimeType: 'image/png'),
      ];
      final result = ToolResult(
        callId: 'c1',
        content: 'hello',
        contentParts: parts,
      );
      expect(result.contentParts, equals(parts));
      expect(result.contentParts, hasLength(2));
    });

    test('has null contentParts when not provided', () {
      final result = ToolResult(callId: 'c2', content: 'text');
      expect(result.contentParts, isNull);
    });

    test('denied has null contentParts', () {
      final result = ToolResult.denied('c3');
      expect(result.contentParts, isNull);
      expect(result.success, isFalse);
    });
  });

  group('Message.toolResult contentParts', () {
    test('stores contentParts when provided', () {
      final parts = [
        const TextPart('output'),
        const ImagePart(bytes: [4, 5], mimeType: 'image/jpeg'),
      ];
      final msg = Message.toolResult(
        callId: 'c4',
        content: 'output',
        toolName: 'screenshot',
        contentParts: parts,
      );
      expect(msg.contentParts, equals(parts));
      expect(msg.contentParts, hasLength(2));
      expect(msg.text, equals('output'));
    });

    test('has null contentParts when not provided', () {
      final msg = Message.toolResult(
        callId: 'c5',
        content: 'plain text',
      );
      expect(msg.contentParts, isNull);
      expect(msg.text, equals('plain text'));
    });
  });
}
