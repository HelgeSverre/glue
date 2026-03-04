import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/permission_mode.dart';
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
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async =>
      [const TextPart('ok')];

  @override
  ToolTrust get trust => _trust;
}

void main() {
  final tools = <String, Tool>{
    'read_file': _StubTool('read_file', ToolTrust.safe),
    'write_file': _StubTool('write_file', ToolTrust.fileEdit),
    'bash': _StubTool('bash', ToolTrust.command),
  };

  test('readOnly denies mutating tools and allows safe tools', () {
    final gate = PermissionGate(
      permissionMode: PermissionMode.readOnly,
      trustedTools: const {'read_file'},
      tools: tools,
      cwd: '/tmp/project',
    );

    final safeCall = ToolCall(
        id: '1', name: 'read_file', arguments: const {'path': 'a.txt'});
    final mutatingCall = ToolCall(
        id: '2', name: 'bash', arguments: const {'command': 'echo hi'});

    expect(gate.resolve(safeCall), PermissionDecision.allow);
    expect(gate.resolve(mutatingCall), PermissionDecision.deny);
  });

  test('confirm mode allows trusted tools and asks for others', () {
    final gate = PermissionGate(
      permissionMode: PermissionMode.confirm,
      trustedTools: const {'read_file'},
      tools: tools,
      cwd: '/tmp/project',
    );

    final trusted = ToolCall(
        id: '1', name: 'read_file', arguments: const {'path': 'a.txt'});
    final untrusted =
        ToolCall(id: '2', name: 'bash', arguments: const {'command': 'ls'});

    expect(gate.resolve(trusted), PermissionDecision.allow);
    expect(gate.resolve(untrusted), PermissionDecision.ask);
  });

  test('acceptEdits asks when file edit targets outside cwd', () {
    final gate = PermissionGate(
      permissionMode: PermissionMode.acceptEdits,
      trustedTools: const {},
      tools: tools,
      cwd: '/tmp/project',
    );

    final inside = ToolCall(
      id: '1',
      name: 'write_file',
      arguments: const {'path': '/tmp/project/notes.txt'},
    );
    final outside = ToolCall(
      id: '2',
      name: 'write_file',
      arguments: const {'path': '/tmp/other/notes.txt'},
    );

    expect(gate.resolve(inside), PermissionDecision.allow);
    expect(gate.resolve(outside), PermissionDecision.ask);
  });

  test('needsEarlyConfirmation follows mode + trust rules', () {
    final gate = PermissionGate(
      permissionMode: PermissionMode.acceptEdits,
      trustedTools: const {'read_file'},
      tools: tools,
      cwd: '/tmp/project',
    );

    expect(gate.needsEarlyConfirmation('read_file'), isFalse);
    expect(gate.needsEarlyConfirmation('write_file'), isFalse);
    expect(gate.needsEarlyConfirmation('bash'), isTrue);
  });
}
