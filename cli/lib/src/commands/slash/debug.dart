import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';

/// `/debug` — toggle debug logging.
class DebugCommand extends SlashCommand {
  DebugCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'debug';

  @override
  String get description => 'Toggle debug mode (verbose logging)';

  @override
  String execute(List<String> args) {
    final controller = ctx.debug;
    if (controller == null) return 'Debug mode: unavailable';
    controller.toggle();
    return 'Debug mode: ${controller.enabled}';
  }
}
