import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/interaction_mode.dart';
import 'package:glue/src/orchestrator/permission_gate.dart';
import 'package:test/test.dart';

class _StubTool extends Tool {
  final String _name;
  final ToolTrust _trust;
  final ToolGroup? _groupOverride;

  _StubTool(this._name, this._trust, [this._groupOverride]);

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
  @override
  ToolGroup get group => _groupOverride ?? super.group;
}

void main() {
  final tools = <String, Tool>{
    'read_file': _StubTool('read_file', ToolTrust.safe),
    'write_file': _StubTool('write_file', ToolTrust.fileEdit),
    'bash': _StubTool('bash', ToolTrust.command),
    'web_search': _StubTool('web_search', ToolTrust.safe, ToolGroup.mcp),
  };

  group('code mode + confirm approval', () {
    final gate = PermissionGate(
      interactionMode: InteractionMode.code,
      approvalMode: ApprovalMode.confirm,
      trustedTools: const {'read_file'},
      tools: tools,
      cwd: '/tmp/project',
    );

    test('allows trusted tools', () {
      final call = ToolCall(
          id: '1', name: 'read_file', arguments: const {'path': 'a.txt'});
      expect(gate.resolve(call), PermissionDecision.allow);
    });

    test('asks for untrusted mutating tools', () {
      final call =
          ToolCall(id: '2', name: 'bash', arguments: const {'command': 'ls'});
      expect(gate.resolve(call), PermissionDecision.ask);
    });
  });

  group('code mode + auto approval', () {
    final gate = PermissionGate(
      interactionMode: InteractionMode.code,
      approvalMode: ApprovalMode.auto,
      trustedTools: const {},
      tools: tools,
      cwd: '/tmp/project',
    );

    test('allows everything', () {
      final call = ToolCall(
          id: '1', name: 'bash', arguments: const {'command': 'rm -rf /'});
      expect(gate.resolve(call), PermissionDecision.allow);
    });
  });

  group('ask mode', () {
    final gate = PermissionGate(
      interactionMode: InteractionMode.ask,
      approvalMode: ApprovalMode.confirm,
      trustedTools: const {},
      tools: tools,
      cwd: '/tmp/project',
    );

    test('allows read tools', () {
      final call = ToolCall(
          id: '1', name: 'read_file', arguments: const {'path': 'a.txt'});
      expect(gate.resolve(call), PermissionDecision.allow);
    });

    test('denies edit tools', () {
      final call = ToolCall(
          id: '2',
          name: 'write_file',
          arguments: const {'path': 'a.txt', 'content': 'x'});
      expect(gate.resolve(call), PermissionDecision.deny);
    });

    test('denies command tools', () {
      final call =
          ToolCall(id: '3', name: 'bash', arguments: const {'command': 'ls'});
      expect(gate.resolve(call), PermissionDecision.deny);
    });

    test('allows mcp tools', () {
      final call = ToolCall(
          id: '4', name: 'web_search', arguments: const {'query': 'test'});
      expect(gate.resolve(call), PermissionDecision.allow);
    });
  });

  group('architect mode', () {
    final gate = PermissionGate(
      interactionMode: InteractionMode.architect,
      approvalMode: ApprovalMode.confirm,
      trustedTools: const {},
      tools: tools,
      cwd: '/tmp/project',
    );

    test('allows read tools', () {
      final call = ToolCall(
          id: '1', name: 'read_file', arguments: const {'path': 'a.txt'});
      expect(gate.resolve(call), PermissionDecision.allow);
    });

    test('denies command tools', () {
      final call =
          ToolCall(id: '2', name: 'bash', arguments: const {'command': 'ls'});
      expect(gate.resolve(call), PermissionDecision.deny);
    });

    test('asks for edit tools targeting .md files', () {
      final call = ToolCall(
          id: '3',
          name: 'write_file',
          arguments: const {'path': 'plan.md', 'content': '# Plan'});
      expect(gate.resolve(call), PermissionDecision.ask);
    });

    test('denies edit tools targeting non-.md files', () {
      final call = ToolCall(
          id: '4',
          name: 'write_file',
          arguments: const {'path': 'main.dart', 'content': 'void main() {}'});
      expect(gate.resolve(call), PermissionDecision.deny);
    });

    test('allows mcp tools', () {
      final call = ToolCall(
          id: '5', name: 'web_search', arguments: const {'query': 'test'});
      expect(gate.resolve(call), PermissionDecision.allow);
    });
  });

  group('architect mode + auto approval', () {
    final gate = PermissionGate(
      interactionMode: InteractionMode.architect,
      approvalMode: ApprovalMode.auto,
      trustedTools: const {},
      tools: tools,
      cwd: '/tmp/project',
    );

    test('auto-approves .md edits without asking', () {
      final call = ToolCall(
          id: '1',
          name: 'write_file',
          arguments: const {'path': 'plan.md', 'content': '# Plan'});
      expect(gate.resolve(call), PermissionDecision.allow);
    });

    test('still denies non-.md edits even in auto', () {
      final call = ToolCall(
          id: '2',
          name: 'write_file',
          arguments: const {'path': 'main.dart', 'content': 'code'});
      expect(gate.resolve(call), PermissionDecision.deny);
    });
  });

  group('needsEarlyConfirmation', () {
    test('no confirmation needed in auto mode', () {
      final gate = PermissionGate(
        interactionMode: InteractionMode.code,
        approvalMode: ApprovalMode.auto,
        trustedTools: const {},
        tools: tools,
        cwd: '/tmp/project',
      );
      expect(gate.needsEarlyConfirmation('bash'), isFalse);
    });

    test('no confirmation for safe tools in confirm mode', () {
      final gate = PermissionGate(
        interactionMode: InteractionMode.code,
        approvalMode: ApprovalMode.confirm,
        trustedTools: const {},
        tools: tools,
        cwd: '/tmp/project',
      );
      expect(gate.needsEarlyConfirmation('read_file'), isFalse);
    });

    test('confirmation needed for untrusted mutating tools', () {
      final gate = PermissionGate(
        interactionMode: InteractionMode.code,
        approvalMode: ApprovalMode.confirm,
        trustedTools: const {},
        tools: tools,
        cwd: '/tmp/project',
      );
      expect(gate.needsEarlyConfirmation('bash'), isTrue);
    });

    test('no confirmation for disallowed group', () {
      final gate = PermissionGate(
        interactionMode: InteractionMode.ask,
        approvalMode: ApprovalMode.confirm,
        trustedTools: const {},
        tools: tools,
        cwd: '/tmp/project',
      );
      // bash is denied by mode, so no early confirmation needed
      expect(gate.needsEarlyConfirmation('bash'), isFalse);
    });
  });
}
