import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/runtime/commands/command_host.dart';

abstract interface class SlashCommandModule {
  void register(SlashCommandRegistry registry, SlashCommandContext context);

  void attachArgCompleters(
    SlashCommandRegistry registry,
    SlashCommandContext context,
  );
}
