import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';

/// `/exit` — request app shutdown.
class ExitCommand extends SlashCommand {
  ExitCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'exit';

  @override
  String get description => 'Exit Glue';

  @override
  List<String> get aliases => const ['quit'];

  @override
  List<String> get hiddenAliases => const ['q'];

  @override
  String execute(List<String> args) {
    ctx.lifecycle.requestExit();
    return '';
  }
}
