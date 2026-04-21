import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/llm/tool_schema.dart';
import 'package:test/test.dart';

class _ArrayParamTool extends Tool {
  @override
  String get name => 'array_param_tool';

  @override
  String get description => 'Tool with an array-typed parameter.';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'items_list',
          type: 'array',
          description: 'A list of strings.',
          items: {'type': 'string'},
        ),
      ];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async =>
      ToolResult(content: '');
}

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

    test('includes items on array-typed parameters', () {
      const encoder = AnthropicToolEncoder();
      final schemas = encoder.encodeAll([_ArrayParamTool()]);
      final props = (schemas.first['input_schema']
          as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
      final itemsList = props['items_list'] as Map<String, dynamic>;
      expect(itemsList['type'], 'array');
      expect(itemsList['items'], {'type': 'string'});
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

    test('includes items on array-typed parameters', () {
      const encoder = OpenAiToolEncoder();
      final schemas = encoder.encodeAll([_ArrayParamTool()]);
      final params = (schemas.first['function']
          as Map<String, dynamic>)['parameters'] as Map<String, dynamic>;
      final props = params['properties'] as Map<String, dynamic>;
      final itemsList = props['items_list'] as Map<String, dynamic>;
      expect(itemsList['type'], 'array');
      expect(itemsList['items'], {'type': 'string'},
          reason: 'OpenAI strict validator requires items on array schemas');
    });
  });
}
