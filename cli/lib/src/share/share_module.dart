import 'package:glue/src/commands/arg_completers.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/runtime/commands/command_host.dart';
import 'package:glue/src/runtime/commands/command_module.dart';

/// Registers the `/share` slash command. Lives in `share/` alongside the
/// controller and export pipeline so the whole feature is one directory.
class ShareCommandModule implements SlashCommandModule {
  const ShareCommandModule();

  @override
  void register(SlashCommandRegistry registry, SlashCommandContext context) {
    registry.register(SlashCommand(
      name: 'share',
      description: 'Export the current session as html, markdown, or gist',
      execute: context.share.shareAction,
    ));
  }

  @override
  void attachArgCompleters(
    SlashCommandRegistry registry,
    SlashCommandContext context,
  ) {
    registry.attachArgCompleter('share', shareArgCompleter());
  }
}
