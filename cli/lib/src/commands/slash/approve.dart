import 'package:glue_harness/glue_harness.dart';

import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';

/// `/approve` — toggle approval mode (confirm ↔ auto).
class ApproveCommand extends SlashCommand {
  ApproveCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'approve';

  @override
  String get description => 'Toggle approval mode (confirm ↔ auto)';

  @override
  String execute(List<String> args) {
    final next = ctx.approval.toggle();
    return 'Approval mode: ${next.label}';
  }
}
