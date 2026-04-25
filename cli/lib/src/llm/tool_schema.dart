import 'package:glue/src/agent/tools.dart';

/// Encodes [Tool] definitions into provider-specific JSON schemas.
sealed class ToolSchemaEncoder {
  const ToolSchemaEncoder();

  List<Map<String, dynamic>> encodeAll(List<Tool> tools);
}

/// Anthropic Messages API tool format.
///
/// Uses the existing `Tool.toSchema()` which already produces
/// `{name, description, input_schema: {type, properties, required}}`.
class AnthropicToolEncoder extends ToolSchemaEncoder {
  const AnthropicToolEncoder();

  @override
  List<Map<String, dynamic>> encodeAll(List<Tool> tools) =>
      [for (final t in tools) t.toSchema()];
}

/// Gemini Developer API tool format.
///
/// Wraps every declaration in a single `{functionDeclarations: [...]}` entry
/// and uppercases JSON-Schema `type` values (Gemini expects `OBJECT`, `STRING`,
/// `ARRAY`, etc.). Per-parameter `items` schemas are also walked so array
/// element types stay valid.
class GeminiToolEncoder extends ToolSchemaEncoder {
  const GeminiToolEncoder();

  @override
  List<Map<String, dynamic>> encodeAll(List<Tool> tools) {
    return [
      {
        'functionDeclarations': [
          for (final t in tools)
            {
              'name': t.name,
              'description': t.description,
              'parameters': {
                'type': 'OBJECT',
                'properties': {
                  for (final p in t.parameters)
                    p.name: _upperType(p.toSchema()),
                },
                'required': [
                  for (final p in t.parameters)
                    if (p.required) p.name,
                ],
              },
            }
        ],
      }
    ];
  }

  static Map<String, dynamic> _upperType(Map<String, dynamic> schema) {
    final out = <String, dynamic>{...schema};
    final type = out['type'];
    if (type is String) {
      out['type'] = type.toUpperCase();
    }
    final items = out['items'];
    if (items is Map<String, dynamic>) {
      out['items'] = _upperType(items);
    }
    return out;
  }
}

/// OpenAI Chat Completions function-calling format.
///
/// Wraps each tool in `{type: "function", function: {name, description, parameters}}`.
class OpenAiToolEncoder extends ToolSchemaEncoder {
  const OpenAiToolEncoder();

  @override
  List<Map<String, dynamic>> encodeAll(List<Tool> tools) => [
        for (final t in tools)
          {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.description,
              'parameters': {
                'type': 'object',
                'properties': {
                  for (final p in t.parameters) p.name: p.toSchema(),
                },
                'required': [
                  for (final p in t.parameters)
                    if (p.required) p.name,
                ],
              },
            },
          }
      ];
}
