import 'package:glue_harness/glue_harness.dart';

import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';

/// `/rename` — set a manual title for the current session.
class RenameCommand extends SlashCommand {
  RenameCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'rename';

  @override
  String get description => 'Rename the current session';

  @override
  String execute(List<String> args) {
    final normalized = TitleGenerator.sanitize(args.join(' '))?.trim();
    if (normalized == null || normalized.isEmpty) {
      return 'Usage: /rename <new title>';
    }
    ctx.ensureSession();
    ctx.session.markManuallyRenamed();
    ctx.session.renameTitle(normalized);
    return 'Renamed session to "$normalized".';
  }
}
