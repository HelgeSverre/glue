import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/agent/content_part.dart';

class _StubTool extends Tool {
  final String _name;
  final ToolTrust _trust;
  _StubTool(this._name, this._trust);

  @override
  String get name => _name;
  @override
  String get description => 'stub';
  @override
  List<ToolParameter> get parameters => const [];
  @override
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async =>
      [TextPart('ok')];
  @override
  ToolTrust get trust => _trust;
}

/// LLM that records the tools it receives in each stream() call.
class _RecordingLlm implements LlmClient {
  final List<List<String>> receivedToolNames = [];

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    receivedToolNames.add(tools?.map((t) => t.name).toList() ?? []);
    yield TextDelta('done');
    yield UsageInfo(inputTokens: 1, outputTokens: 1);
  }
}

void main() {
  group('AgentCore.toolFilter', () {
    late _RecordingLlm llm;
    late AgentCore agent;

    setUp(() {
      llm = _RecordingLlm();
      agent = AgentCore(
        llm: llm,
        tools: {
          'read_file': _StubTool('read_file', ToolTrust.safe),
          'write_file': _StubTool('write_file', ToolTrust.fileEdit),
          'bash': _StubTool('bash', ToolTrust.command),
          'grep': _StubTool('grep', ToolTrust.safe),
        },
      );
    });

    test('no filter sends all tools', () async {
      await agent.run('hello').toList();
      expect(llm.receivedToolNames, [
        unorderedEquals(['read_file', 'write_file', 'bash', 'grep']),
      ]);
    });

    test('readOnly filter excludes mutating tools', () async {
      agent.toolFilter = (tool) => !tool.isMutating;
      await agent.run('hello').toList();
      expect(llm.receivedToolNames, [
        unorderedEquals(['read_file', 'grep']),
      ]);
    });

    test('custom filter works', () async {
      agent.toolFilter = (tool) => tool.name == 'grep';
      await agent.run('hello').toList();
      expect(llm.receivedToolNames, [
        ['grep'],
      ]);
    });

    test('allowedTools reflects filter', () {
      agent.toolFilter = (tool) => tool.trust == ToolTrust.safe;
      final names = agent.allowedTools.map((t) => t.name).toSet();
      expect(names, {'read_file', 'grep'});
    });

    test('allowedTools with null filter returns all', () {
      agent.toolFilter = null;
      expect(agent.allowedTools.length, 4);
    });
  });
}
