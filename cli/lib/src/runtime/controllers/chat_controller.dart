import 'dart:async';
import 'dart:io';

import 'package:glue/src/agent/tools.dart' as tool_contract;
import 'package:glue/src/config/approval_mode.dart';
import 'package:glue/src/core/clipboard.dart';
import 'package:glue/src/runtime/commands/command_host.dart';
import 'package:glue/src/runtime/transcript.dart';
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
    required this.transcript,
  });

  final Terminal terminal;
  final Layout layout;
  final void Function() clearConversationState;
  final void Function() render;
  final Iterable<tool_contract.Tool> Function() tools;
  final ApprovalMode Function() getApprovalMode;
  final void Function(ApprovalMode mode) setApprovalMode;
  final Transcript transcript;

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

  @override
  void copyLastResponse() {
    ConversationEntry? lastAssistant;
    for (final block in transcript.blocks.reversed) {
      if (block.kind == EntryKind.assistant) {
        lastAssistant = block;
        break;
      }
    }

    if (lastAssistant == null) {
      transcript.system('No assistant response to copy.');
      render();
      return;
    }

    final text = lastAssistant.text;

    unawaited(() async {
      const dir = '/tmp/glue';
      try {
        await Directory(dir).create(recursive: true);
        await File('$dir/copy.md').writeAsString(text);
      } catch (_) {}

      final ok = await copyToClipboard(text);
      final msg = ok
          ? 'Copied to clipboard (also saved to $dir/copy.md).'
          : 'Saved to $dir/copy.md (no clipboard tool available).';
      transcript.system(msg);
      render();
    }());
  }
}
