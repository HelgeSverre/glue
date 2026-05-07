import 'package:glue/src/commands/slash/approve.dart';
import 'package:glue/src/commands/slash/clear.dart';
import 'package:glue/src/commands/slash/config.dart';
import 'package:glue/src/commands/slash/copy.dart';
import 'package:glue/src/commands/slash/debug.dart';
import 'package:glue/src/commands/slash/exit.dart';
import 'package:glue/src/commands/slash/help.dart';
import 'package:glue/src/commands/slash/history.dart';
import 'package:glue/src/commands/slash/model.dart';
import 'package:glue/src/commands/slash/open.dart';
import 'package:glue/src/commands/slash/paths.dart';
import 'package:glue/src/commands/slash/provider.dart';
import 'package:glue/src/commands/slash/recap.dart';
import 'package:glue/src/commands/slash/rename.dart';
import 'package:glue/src/commands/slash/resume.dart';
import 'package:glue/src/commands/slash/session.dart';
import 'package:glue/src/commands/slash/share.dart';
import 'package:glue/src/commands/slash/skills.dart';
import 'package:glue/src/commands/slash/tools.dart';
import 'package:glue/src/commands/slash/usage.dart';
import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';

/// Registration point for the built-in slash commands.
///
/// Every command is class-based and depends only on [SlashCommandContext].
/// Adding a command means writing a new class and one line here.
class BuiltinCommands {
  static SlashCommandRegistry create(SlashCommandContext ctx) {
    return SlashCommandRegistry()
      ..registerAll([
        HelpCommand(ctx),
        ClearCommand(ctx),
        CopyCommand(ctx),
        ExitCommand(ctx),
        ToolsCommand(ctx),
        UsageCommand(ctx),
        DebugCommand(ctx),
        ApproveCommand(ctx),
        PathsCommand(ctx),
        RecapCommand(ctx),
        ShareCommand(ctx),
        SkillsCommand(ctx),
        ConfigCommand(ctx),
        OpenCommand(ctx),
        HistoryCommand(ctx),
        ResumeCommand(ctx),
        SessionCommand(ctx),
        RenameCommand(ctx),
        ModelCommand(ctx),
        ProviderCommand(ctx),
      ]);
  }
}
