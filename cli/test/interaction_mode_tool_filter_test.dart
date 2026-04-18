import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/interaction_mode.dart';
import 'package:glue/src/storage/config_store.dart';

// ---------------------------------------------------------------------------
// Test helpers (same pattern as tool_filter_test.dart)
// ---------------------------------------------------------------------------

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
      [const TextPart('ok')];
  @override
  ToolTrust get trust => _trust;
}

class _RecordingLlm implements LlmClient {
  final List<List<String>> receivedToolNames = [];
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    receivedToolNames.add(tools?.map((t) => t.name).toList() ?? []);
    yield TextDelta('done');
    yield UsageInfo(inputTokens: 1, outputTokens: 1);
  }
}

/// The default auto-approved tool names hardcoded in App.
const _defaultAutoApproved = {
  'read_file',
  'list_directory',
  'grep',
  'spawn_subagent',
  'spawn_parallel_subagents',
  'web_fetch',
  'web_search',
  'web_browser',
  'skill',
};

void main() {
  group('ConfigStore: clearing stale trusted tools from old session', () {
    late Directory tmpDir;
    late String configPath;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('perm_mode_test_');
      configPath = p.join(tmpDir.path, 'config.json');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('old session trusted tools are loaded then clearable', () {
      final store = ConfigStore(configPath);

      // Simulate old session saving trusted tools.
      store.save({
        'trusted_tools': ['bash', 'write_file'],
      });
      expect(store.trustedTools, ['bash', 'write_file']);

      // Clear stale tools for a fresh session.
      store.update((c) => c.remove('trusted_tools'));
      expect(store.trustedTools, isEmpty);

      // Verify on disk.
      final onDisk = jsonDecode(File(configPath).readAsStringSync())
          as Map<String, dynamic>;
      expect(onDisk.containsKey('trusted_tools'), isFalse);
    });

    test('new session after clearing gets only default auto-approved', () {
      final store = ConfigStore(configPath);

      // Old session had extra tools.
      store.save({
        'trusted_tools': ['bash', 'write_file']
      });

      // Clear for new session.
      store.update((c) => c.remove('trusted_tools'));

      // Simulate new App constructor: defaults + configStore.trustedTools.
      final autoApproved = Set<String>.from(_defaultAutoApproved)
        ..addAll(store.trustedTools);

      expect(autoApproved, _defaultAutoApproved);
      expect(autoApproved.contains('bash'), isFalse);
      expect(autoApproved.contains('write_file'), isFalse);
    });
  });

  group('Mode toggle: tool filter and approval behavior', () {
    late _RecordingLlm llm;
    late AgentCore agent;

    setUp(() {
      llm = _RecordingLlm();
      agent = AgentCore(
        llm: llm,
        tools: {
          'read_file': _StubTool('read_file', ToolTrust.safe),
          'grep': _StubTool('grep', ToolTrust.safe),
          'write_file': _StubTool('write_file', ToolTrust.fileEdit),
          'edit_file': _StubTool('edit_file', ToolTrust.fileEdit),
          'bash': _StubTool('bash', ToolTrust.command),
        },
      );
    });

    test('ask mode: only read tools sent to LLM', () async {
      agent.toolFilter = (tool) => InteractionMode.ask.allowsGroup(tool.group);
      await agent.run('hello').toList();

      expect(
          llm.receivedToolNames.last, unorderedEquals(['read_file', 'grep']));
    });

    test('code mode: all tools sent to LLM', () async {
      agent.toolFilter = null;
      await agent.run('hello').toList();

      expect(
          llm.receivedToolNames.last,
          unorderedEquals(
              ['read_file', 'grep', 'write_file', 'edit_file', 'bash']));
    });

    test('architect mode: excludes command tools', () async {
      agent.toolFilter =
          (tool) => InteractionMode.architect.allowsGroup(tool.group);
      await agent.run('hello').toList();

      expect(llm.receivedToolNames.last,
          unorderedEquals(['read_file', 'grep', 'write_file', 'edit_file']));
    });

    test('ask → code toggle restores all tools', () async {
      agent.toolFilter = (tool) => InteractionMode.ask.allowsGroup(tool.group);
      await agent.run('hello').toList();
      expect(
          llm.receivedToolNames.last, unorderedEquals(['read_file', 'grep']));

      agent.toolFilter = null;
      await agent.run('hello again').toList();
      expect(
          llm.receivedToolNames.last,
          unorderedEquals(
              ['read_file', 'grep', 'write_file', 'edit_file', 'bash']));
    });
  });
}
