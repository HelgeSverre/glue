import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';

import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/commands/usage_report.dart';

/// `/usage` — show token usage for the current session, broken down by role.
class UsageCommand extends SlashCommand {
  UsageCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'usage';

  @override
  String get description =>
      'Show token usage for this session (per role: main, subagent, title)';

  @override
  String execute(List<String> args) {
    final store = ctx.session.currentStore;
    if (store == null) return 'No active session yet — nothing to report.';
    final report = buildUsageReport(
      usageEvents: SessionStore.loadConversation(store.sessionDir),
      modelLabel: store.meta.modelRef,
      sessionId: store.meta.id.value,
    );
    return formatUsageReport(report);
  }
}
