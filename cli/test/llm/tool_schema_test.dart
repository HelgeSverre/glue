import 'package:test/test.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/llm/tool_schema.dart';

void main() {
  final tool = ReadFileTool();

  group('AnthropicToolEncoder', () {
    test('produces Anthropic-native schema', () {
      const encoder = AnthropicToolEncoder();
      final schemas = encoder.encodeAll([tool]);

      expect(schemas, hasLength(1));
      final s = schemas.first;
      expect(s['name'], 'read_file');
      expect(s['description'], isNotEmpty);
      expect(s, contains('input_schema'));
      final inputSchema = s['input_schema'] as Map<String, dynamic>;
      expect(inputSchema['type'], 'object');
      expect(inputSchema['properties'], contains('path'));
    });
  });

  group('OpenAiToolEncoder', () {
    test('produces OpenAI function-calling schema', () {
      const encoder = OpenAiToolEncoder();
      final schemas = encoder.encodeAll([tool]);

      expect(schemas, hasLength(1));
      final s = schemas.first;
      expect(s['type'], 'function');
      final fn = s['function'] as Map<String, dynamic>;
      expect(fn['name'], 'read_file');
      expect(fn['description'], isNotEmpty);
      final params = fn['parameters'] as Map<String, dynamic>;
      expect(params['type'], 'object');
      expect(params['properties'], contains('path'));
    });
  });
}
