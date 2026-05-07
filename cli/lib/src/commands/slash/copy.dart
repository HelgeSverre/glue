import 'package:glue_harness/glue_harness.dart';

import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';

/// `/copy` — copy the last assistant response to the clipboard.
class CopyCommand extends SlashCommand {
  CopyCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'copy';

  @override
  String get description => 'Copy the last assistant response to the clipboard';

  @override
  String execute(List<String> args) {
    final partial = ctx.conversation.streamingText.isNotEmpty;
    final text = ctx.conversation.lastAssistantText();
    if (text == null) {
      ctx.conversation.notify('No assistant response to copy yet.');
      return '';
    }
    final qualifier = partial ? 'partial in-flight response' : 'last response';
    copyToClipboard(text).then((ok) {
      ctx.conversation.notify(
        ok
            ? 'Copied $qualifier to clipboard (${text.length} chars).'
            : 'Could not access clipboard.',
      );
    });
    return '';
  }
}
