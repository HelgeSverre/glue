import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';

/// `/clear` — clear conversation transcript and screen.
class ClearCommand extends SlashCommand {
  ClearCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'clear';

  @override
  String get description => 'Clear conversation history';

  @override
  String execute(List<String> args) {
    ctx.conversation.clear();
    return 'Cleared.';
  }
}
