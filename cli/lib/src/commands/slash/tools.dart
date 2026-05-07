import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue_harness/glue_harness.dart';

/// `/tools` — list registered tools and their descriptions.
class ToolsCommand extends SlashCommand {
  ToolsCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'tools';

  @override
  String get description => 'List available tools';

  @override
  String execute(List<String> args) {
    final tools = ctx.agent.tools.values.toList()..sortBy((t) => t.name);
    return [
      'Registered tools (${tools.length}):',
      for (final t in tools) '  ${t.name} — ${t.description}',
    ].join('\n');
  }
}
