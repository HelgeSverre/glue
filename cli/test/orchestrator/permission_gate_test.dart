import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/approval_mode.dart';
import 'package:glue/src/orchestrator/permission_gate.dart';
import 'package:test/test.dart';

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
  Future<ToolResult> execute(Map<String, dynamic> args) async =>
      ToolResult(content: 'ok');
  @override
  ToolTrust get trust => _trust;
}

void main() {
  final tools = <String, Tool>{
    'read_file': _StubTool('read_file', ToolTrust.safe),
    'write_file': _StubTool('write_file', ToolTrust.fileEdit),
    'bash': _StubTool('bash', ToolTrust.command),
  };

  group('confirm approval', () {
    final gate = PermissionGate(
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

    test('allows safe untrusted tools', () {
      // read_file is trusted; use a different safe tool to cover the
      // "!isMutating" branch without relying on trust.
      final safeOnly = <String, Tool>{
        'read_file': _StubTool('read_file', ToolTrust.safe),
      };
      final safeGate = PermissionGate(
        approvalMode: ApprovalMode.confirm,
        trustedTools: const {},
        tools: safeOnly,
        cwd: '/tmp/project',
      );
      final call = ToolCall(
          id: '1', name: 'read_file', arguments: const {'path': 'a.txt'});
      expect(safeGate.resolve(call), PermissionDecision.allow);
    });

    test('asks for untrusted mutating tools', () {
      final call =
          ToolCall(id: '2', name: 'bash', arguments: const {'command': 'ls'});
      expect(gate.resolve(call), PermissionDecision.ask);
    });

    test('denies unknown tool', () {
      final call = ToolCall(id: '3', name: 'missing', arguments: const {});
      expect(gate.resolve(call), PermissionDecision.deny);
    });
  });

  group('auto approval', () {
    final gate = PermissionGate(
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

    test('still denies unknown tool', () {
      final call = ToolCall(id: '2', name: 'missing', arguments: const {});
      expect(gate.resolve(call), PermissionDecision.deny);
    });
  });

  group('needsEarlyConfirmation', () {
    test('no confirmation needed in auto mode', () {
      final gate = PermissionGate(
        approvalMode: ApprovalMode.auto,
        trustedTools: const {},
        tools: tools,
        cwd: '/tmp/project',
      );
      expect(gate.needsEarlyConfirmation('bash'), isFalse);
    });

    test('no confirmation for safe tools in confirm mode', () {
      final gate = PermissionGate(
        approvalMode: ApprovalMode.confirm,
        trustedTools: const {},
        tools: tools,
        cwd: '/tmp/project',
      );
      expect(gate.needsEarlyConfirmation('read_file'), isFalse);
    });

    test('no confirmation for trusted tools', () {
      final gate = PermissionGate(
        approvalMode: ApprovalMode.confirm,
        trustedTools: const {'bash'},
        tools: tools,
        cwd: '/tmp/project',
      );
      expect(gate.needsEarlyConfirmation('bash'), isFalse);
    });

    test('confirmation needed for untrusted mutating tools', () {
      final gate = PermissionGate(
        approvalMode: ApprovalMode.confirm,
        trustedTools: const {},
        tools: tools,
        cwd: '/tmp/project',
      );
      expect(gate.needsEarlyConfirmation('bash'), isTrue);
    });

    test('unknown tool requires confirmation', () {
      final gate = PermissionGate(
        approvalMode: ApprovalMode.confirm,
        trustedTools: const {},
        tools: tools,
        cwd: '/tmp/project',
      );
      expect(gate.needsEarlyConfirmation('missing'), isTrue);
    });
  });
}
