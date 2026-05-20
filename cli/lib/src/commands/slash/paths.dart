import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/terminal/where_report.dart';

/// `/paths` — show Glue's data directories.
class PathsCommand extends SlashCommand {
  PathsCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'paths';

  @override
  String get description =>
      'Show Glue data paths (config, sessions, logs, skills, plans, cache)';

  @override
  List<String> get hiddenAliases => const ['where'];

  @override
  String execute(List<String> args) => buildWhereReport(ctx.environment);
}
