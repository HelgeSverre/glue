import 'package:test/test.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/interaction_mode.dart';

void main() {
  group('ToolGroup', () {
    test('all groups are defined', () {
      expect(ToolGroup.values, hasLength(4));
      expect(
          ToolGroup.values,
          containsAll([
            ToolGroup.read,
            ToolGroup.edit,
            ToolGroup.command,
            ToolGroup.mcp,
          ]));
    });
  });

  group('InteractionMode', () {
    test('label returns expected strings', () {
      expect(InteractionMode.code.label, 'code');
      expect(InteractionMode.architect.label, 'architect');
      expect(InteractionMode.ask.label, 'ask');
    });

    test('next cycles through all modes', () {
      expect(InteractionMode.code.next, InteractionMode.architect);
      expect(InteractionMode.architect.next, InteractionMode.ask);
      expect(InteractionMode.ask.next, InteractionMode.code);
    });

    test('full cycle returns to start', () {
      var mode = InteractionMode.code;
      for (var i = 0; i < 3; i++) {
        mode = mode.next;
      }
      expect(mode, InteractionMode.code);
    });

    test('code allows all groups', () {
      expect(InteractionMode.code.allowsGroup(ToolGroup.read), isTrue);
      expect(InteractionMode.code.allowsGroup(ToolGroup.edit), isTrue);
      expect(InteractionMode.code.allowsGroup(ToolGroup.command), isTrue);
      expect(InteractionMode.code.allowsGroup(ToolGroup.mcp), isTrue);
    });

    test('architect allows read, mcp, and edit', () {
      expect(InteractionMode.architect.allowsGroup(ToolGroup.read), isTrue);
      expect(InteractionMode.architect.allowsGroup(ToolGroup.edit), isTrue);
      expect(InteractionMode.architect.allowsGroup(ToolGroup.mcp), isTrue);
      expect(InteractionMode.architect.allowsGroup(ToolGroup.command), isFalse);
    });

    test('ask allows read and mcp only', () {
      expect(InteractionMode.ask.allowsGroup(ToolGroup.read), isTrue);
      expect(InteractionMode.ask.allowsGroup(ToolGroup.mcp), isTrue);
      expect(InteractionMode.ask.allowsGroup(ToolGroup.edit), isFalse);
      expect(InteractionMode.ask.allowsGroup(ToolGroup.command), isFalse);
    });
  });

  group('ApprovalMode', () {
    test('label returns expected strings', () {
      expect(ApprovalMode.confirm.label, 'confirm');
      expect(ApprovalMode.auto.label, 'auto');
    });

    test('toggle switches between modes', () {
      expect(ApprovalMode.confirm.toggle, ApprovalMode.auto);
      expect(ApprovalMode.auto.toggle, ApprovalMode.confirm);
    });
  });
}
