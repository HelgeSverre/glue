import '../agent/tools.dart';

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
