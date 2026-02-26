import 'package:test/test.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/llm/tool_schema.dart';

void main() {
  final tool = ReadFileTool();

  group('AnthropicToolEncoder', () {
    test('produces Anthropic-native schema', () {
      final encoder = AnthropicToolEncoder();
      final schemas = encoder.encodeAll([tool]);

      expect(schemas, hasLength(1));
      final s = schemas.first;
      expect(s['name'], 'read_file');
      expect(s['description'], isNotEmpty);
      expect(s, contains('input_schema'));
      expect(s['input_schema']['type'], 'object');
      expect(s['input_schema']['properties'], contains('path'));
    });
  });

  group('OpenAiToolEncoder', () {
    test('produces OpenAI function-calling schema', () {
      final encoder = OpenAiToolEncoder();
      final schemas = encoder.encodeAll([tool]);

      expect(schemas, hasLength(1));
      final s = schemas.first;
      expect(s['type'], 'function');
      expect(s['function']['name'], 'read_file');
      expect(s['function']['description'], isNotEmpty);
      expect(s['function']['parameters']['type'], 'object');
      expect(s['function']['parameters']['properties'], contains('path'));
    });
  });
}
