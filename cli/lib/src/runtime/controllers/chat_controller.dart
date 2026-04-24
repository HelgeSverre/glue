import 'package:glue/src/agent/tools.dart' as tool_contract;
import 'package:glue/src/config/approval_mode.dart';
import 'package:glue/src/runtime/commands/command_host.dart';
import 'package:glue/src/terminal/layout.dart';
import 'package:glue/src/terminal/terminal.dart';

class ChatController implements ChatCommandController {
  const ChatController({
    required this.terminal,
    required this.layout,
    required this.clearConversationState,
    required this.render,
    required this.tools,
    required this.getApprovalMode,
    required this.setApprovalMode,
  });

  final Terminal terminal;
  final Layout layout;
  final void Function() clearConversationState;
  final void Function() render;
  final Iterable<tool_contract.Tool> Function() tools;
  final ApprovalMode Function() getApprovalMode;
  final void Function(ApprovalMode mode) setApprovalMode;

  @override
  String clearConversation() {
    clearConversationState();
    terminal.clearScreen();
    layout.apply();
    return 'Cleared.';
  }

  @override
  String listTools() {
    final buf = StringBuffer('Available tools:\n');
    for (final tool in tools()) {
      buf.writeln('  ${tool.name} — ${tool.description}');
    }
    return buf.toString();
  }

  @override
  String toggleApproval() {
    final next = getApprovalMode().toggle;
    setApprovalMode(next);
    render();
    return 'Approval: ${next.label}';
  }
}
