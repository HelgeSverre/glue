import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/permission_mode.dart';
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

/// Simulates the _resolveApproval logic from App (private, so reproduced here).
///
/// This mirrors app.dart's _resolveApproval so we can test the approval
/// decision matrix without constructing a full App instance.
enum _Approval { allow, deny, ask }

// ignore: library_private_types_in_public_api
_Approval resolveApproval({
  required PermissionMode mode,
  required String toolName,
  required ToolTrust trust,
  required Set<String> autoApproved,
}) {
  switch (mode) {
    case PermissionMode.ignorePermissions:
      return _Approval.allow;
    case PermissionMode.readOnly:
      if (trust != ToolTrust.safe) return _Approval.deny;
      return _Approval.allow;
    case PermissionMode.acceptEdits:
      if (autoApproved.contains(toolName)) return _Approval.allow;
      if (trust == ToolTrust.fileEdit) return _Approval.allow;
      return _Approval.ask;
    case PermissionMode.confirm:
      if (autoApproved.contains(toolName)) return _Approval.allow;
      return _Approval.ask;
  }
}

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
      final onDisk =
          jsonDecode(File(configPath).readAsStringSync()) as Map<String, dynamic>;
      expect(onDisk.containsKey('trusted_tools'), isFalse);
    });

    test('new session after clearing gets only default auto-approved', () {
      final store = ConfigStore(configPath);

      // Old session had extra tools.
      store.save({'trusted_tools': ['bash', 'write_file']});

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

    test('readOnly: only safe tools sent to LLM', () async {
      // Simulate _syncToolFilter in readOnly.
      agent.toolFilter = (tool) => !tool.isMutating;
      await agent.run('hello').toList();

      expect(llm.receivedToolNames.last,
          unorderedEquals(['read_file', 'grep']));
    });

    test('YOLO: all tools sent to LLM', () async {
      // Simulate _syncToolFilter in ignorePermissions.
      agent.toolFilter = null;
      await agent.run('hello').toList();

      expect(llm.receivedToolNames.last,
          unorderedEquals(['read_file', 'grep', 'write_file', 'edit_file', 'bash']));
    });

    test('readOnly → YOLO toggle restores all tools', () async {
      // Start in readOnly.
      agent.toolFilter = (tool) => !tool.isMutating;
      await agent.run('hello').toList();
      expect(llm.receivedToolNames.last,
          unorderedEquals(['read_file', 'grep']));

      // Toggle to YOLO (ignorePermissions).
      agent.toolFilter = null;
      await agent.run('hello again').toList();
      expect(llm.receivedToolNames.last,
          unorderedEquals(['read_file', 'grep', 'write_file', 'edit_file', 'bash']));
    });

    test('YOLO → readOnly toggle restricts tools again', () async {
      // Start in YOLO.
      agent.toolFilter = null;
      await agent.run('hello').toList();
      expect(llm.receivedToolNames.last, hasLength(5));

      // Toggle to readOnly.
      agent.toolFilter = (tool) => !tool.isMutating;
      await agent.run('hello again').toList();
      expect(llm.receivedToolNames.last,
          unorderedEquals(['read_file', 'grep']));
    });
  });

  group('Approval decisions: mode toggle does not leak auto-approved tools', () {
    test('readOnly denies mutating tools even if they are auto-approved', () {
      final autoApproved = Set<String>.from(_defaultAutoApproved)
        ..add('bash');

      // bash is in auto-approved but readOnly should still deny it.
      expect(
        resolveApproval(
          mode: PermissionMode.readOnly,
          toolName: 'bash',
          trust: ToolTrust.command,
          autoApproved: autoApproved,
        ),
        _Approval.deny,
      );

      // read_file (safe) is allowed.
      expect(
        resolveApproval(
          mode: PermissionMode.readOnly,
          toolName: 'read_file',
          trust: ToolTrust.safe,
          autoApproved: autoApproved,
        ),
        _Approval.allow,
      );
    });

    test('YOLO approves all tools regardless of auto-approved set', () {
      // Empty auto-approved: YOLO still allows everything.
      final empty = <String>{};

      expect(
        resolveApproval(
          mode: PermissionMode.ignorePermissions,
          toolName: 'bash',
          trust: ToolTrust.command,
          autoApproved: empty,
        ),
        _Approval.allow,
      );

      expect(
        resolveApproval(
          mode: PermissionMode.ignorePermissions,
          toolName: 'write_file',
          trust: ToolTrust.fileEdit,
          autoApproved: empty,
        ),
        _Approval.allow,
      );
    });

    test('YOLO mode does not grow auto-approved set', () {
      final autoApproved = Set<String>.from(_defaultAutoApproved);
      final before = Set<String>.from(autoApproved);

      // Simulate multiple YOLO approvals — the resolveApproval function
      // never mutates autoApproved (it just returns allow).
      for (final tool in ['bash', 'write_file', 'edit_file']) {
        resolveApproval(
          mode: PermissionMode.ignorePermissions,
          toolName: tool,
          trust: ToolTrust.command,
          autoApproved: autoApproved,
        );
      }

      // Auto-approved set is unchanged.
      expect(autoApproved, before);
    });

    test('after clearing config: confirm mode asks for non-default tools', () {
      // Fresh session, no extra trusted tools from config.
      final autoApproved = Set<String>.from(_defaultAutoApproved);

      // Default tools are auto-approved.
      expect(
        resolveApproval(
          mode: PermissionMode.confirm,
          toolName: 'read_file',
          trust: ToolTrust.safe,
          autoApproved: autoApproved,
        ),
        _Approval.allow,
      );

      // Non-default tools require confirmation.
      expect(
        resolveApproval(
          mode: PermissionMode.confirm,
          toolName: 'bash',
          trust: ToolTrust.command,
          autoApproved: autoApproved,
        ),
        _Approval.ask,
      );

      expect(
        resolveApproval(
          mode: PermissionMode.confirm,
          toolName: 'write_file',
          trust: ToolTrust.fileEdit,
          autoApproved: autoApproved,
        ),
        _Approval.ask,
      );
    });

    test('full cycle: readOnly → YOLO → confirm, stale tools not leaked', () {
      // Old session had bash as trusted, then config was cleared.
      // New session starts fresh.
      final autoApproved = Set<String>.from(_defaultAutoApproved);

      // Step 1: readOnly mode — bash denied.
      expect(
        resolveApproval(
          mode: PermissionMode.readOnly,
          toolName: 'bash',
          trust: ToolTrust.command,
          autoApproved: autoApproved,
        ),
        _Approval.deny,
      );

      // Step 2: toggle to YOLO — bash allowed (everything is).
      expect(
        resolveApproval(
          mode: PermissionMode.ignorePermissions,
          toolName: 'bash',
          trust: ToolTrust.command,
          autoApproved: autoApproved,
        ),
        _Approval.allow,
      );

      // Verify YOLO didn't sneak bash into auto-approved.
      expect(autoApproved.contains('bash'), isFalse);

      // Step 3: toggle to confirm — bash requires confirmation.
      expect(
        resolveApproval(
          mode: PermissionMode.confirm,
          toolName: 'bash',
          trust: ToolTrust.command,
          autoApproved: autoApproved,
        ),
        _Approval.ask,
      );
    });
  });
}
