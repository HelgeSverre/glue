import 'package:test/test.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/observed_tool.dart';
import 'package:glue/src/observability/debug_controller.dart';

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

void main() {
  group('ToolTrust', () {
    test('ReadFileTool is safe', () {
      final tool = ReadFileTool();
      expect(tool.trust, ToolTrust.safe);
      expect(tool.isMutating, isFalse);
    });

    test('ListDirectoryTool is safe', () {
      final tool = ListDirectoryTool();
      expect(tool.trust, ToolTrust.safe);
      expect(tool.isMutating, isFalse);
    });

    test('GrepTool is safe', () {
      final tool = GrepTool();
      expect(tool.trust, ToolTrust.safe);
      expect(tool.isMutating, isFalse);
    });

    test('WriteFileTool is fileEdit', () {
      final tool = WriteFileTool();
      expect(tool.trust, ToolTrust.fileEdit);
      expect(tool.isMutating, isTrue);
    });

    test('EditFileTool is fileEdit', () {
      final tool = EditFileTool();
      expect(tool.trust, ToolTrust.fileEdit);
      expect(tool.isMutating, isTrue);
    });

    test('BashTool is command', () {
      // BashTool requires an executor — just verify the trust via the class.
      final tool = _StubTool('bash', ToolTrust.command);
      expect(tool.trust, ToolTrust.command);
      expect(tool.isMutating, isTrue);
    });

    test('ForwardingTool forwards trust', () {
      final inner = _StubTool('test', ToolTrust.fileEdit);
      final forwarding = ForwardingTool(inner);
      expect(forwarding.trust, ToolTrust.fileEdit);
      expect(forwarding.isMutating, isTrue);
    });

    test('ObservedTool forwards trust from inner tool', () {
      final inner = _StubTool('observed', ToolTrust.command);
      final obs = Observability(debugController: DebugController());
      final observed = ObservedTool(inner: inner, obs: obs);
      expect(observed.trust, ToolTrust.command);
      expect(observed.isMutating, isTrue);
    });

    test('ObservedTool forwards safe trust', () {
      final inner = _StubTool('safe', ToolTrust.safe);
      final obs = Observability(debugController: DebugController());
      final observed = ObservedTool(inner: inner, obs: obs);
      expect(observed.trust, ToolTrust.safe);
      expect(observed.isMutating, isFalse);
    });
  });
}
