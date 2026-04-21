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
  Future<ToolResult> execute(Map<String, dynamic> args) async =>
      ToolResult(content: 'hello');
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
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    return ToolResult(
      content: 'Screenshot captured.',
      contentParts: const [
        TextPart('Screenshot captured.'),
        ImagePart(bytes: [1, 2, 3], mimeType: 'image/png'),
      ],
    );
  }
}

class _StubLlm extends LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {}
}

void main() {
  group('Tool.execute returns ToolResult', () {
    test('text tool returns a ToolResult with content', () async {
      final tool = _TextTool();
      final result = await tool.execute({});
      expect(result.content, 'hello');
      expect(result.contentParts, isNull);
    });

    test('image tool returns ToolResult with contentParts', () async {
      final tool = _ImageTool();
      final result = await tool.execute({});
      expect(result.content, 'Screenshot captured.');
      expect(result.contentParts, isNotNull);
      expect(result.contentParts!.length, 2);
      expect(result.contentParts![1], isA<ImagePart>());
    });

    test('toContentParts wraps text-only content in a single TextPart', () {
      final result = ToolResult(content: 'just text');
      final parts = result.toContentParts();
      expect(parts, hasLength(1));
      expect(parts[0], isA<TextPart>());
      expect((parts[0] as TextPart).text, 'just text');
    });

    test('toContentParts returns artifacts when present', () {
      final artifacts = [
        const TextPart('caption'),
        const ImagePart(bytes: [1], mimeType: 'image/png'),
      ];
      final result = ToolResult(content: 'caption', contentParts: artifacts);
      expect(result.toContentParts(), same(artifacts));
    });

    test('withCallId copies fields and sets callId', () {
      final result = ToolResult(
        content: 'hi',
        summary: 'one-liner',
        metadata: {'k': 1},
      );
      final stamped = result.withCallId('abc');
      expect(stamped.callId, 'abc');
      expect(stamped.content, 'hi');
      expect(stamped.summary, 'one-liner');
      expect(stamped.metadata, {'k': 1});
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
      expect(result.callId, 'c1');
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
