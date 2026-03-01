import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:test/test.dart';

/// A simple tool for testing that returns text.
class _TextTool extends Tool {
  @override
  String get name => 'text_tool';
  @override
  String get description => 'Returns text';
  @override
  List<ToolParameter> get parameters => const [];

  @override
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async =>
      [const TextPart('hello')];
}

/// A tool that returns images alongside text.
class _ImageTool extends Tool {
  @override
  String get name => 'image_tool';
  @override
  String get description => 'Returns an image';
  @override
  List<ToolParameter> get parameters => const [];

  @override
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async {
    return [
      const TextPart('Screenshot captured.'),
      const ImagePart(bytes: [1, 2, 3], mimeType: 'image/png'),
    ];
  }
}

class _StubLlm extends LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {}
}

void main() {
  group('Tool.execute returns ContentParts', () {
    test('text tool returns TextPart list', () async {
      final tool = _TextTool();
      final parts = await tool.execute({});
      expect(parts.length, 1);
      expect(parts[0], isA<TextPart>());
      expect((parts[0] as TextPart).text, 'hello');
    });

    test('image tool returns ImagePart', () async {
      final tool = _ImageTool();
      final parts = await tool.execute({});
      expect(parts.length, 2);
      expect(parts[0], isA<TextPart>());
      expect(parts[1], isA<ImagePart>());
    });
  });

  group('AgentCore.executeTool', () {
    test('text-only tool returns ToolResult without contentParts', () async {
      final core = AgentCore(
        llm: _StubLlm(),
        tools: {'text_tool': _TextTool()},
      );
      final result = await core.executeTool(
        ToolCall(id: 'c1', name: 'text_tool', arguments: {}),
      );
      expect(result.content, 'hello');
      expect(result.contentParts, isNull);
    });

    test('image tool returns ToolResult with contentParts', () async {
      final core = AgentCore(
        llm: _StubLlm(),
        tools: {'image_tool': _ImageTool()},
      );
      final result = await core.executeTool(
        ToolCall(id: 'c1', name: 'image_tool', arguments: {}),
      );
      expect(result.content, 'Screenshot captured.');
      expect(result.contentParts, isNotNull);
      expect(result.contentParts!.length, 2);
      expect(result.contentParts![1], isA<ImagePart>());
    });

    test('unknown tool returns error without contentParts', () async {
      final core = AgentCore(
        llm: _StubLlm(),
        tools: {},
      );
      final result = await core.executeTool(
        ToolCall(id: 'c1', name: 'nope', arguments: {}),
      );
      expect(result.success, isFalse);
      expect(result.contentParts, isNull);
    });
  });
}
