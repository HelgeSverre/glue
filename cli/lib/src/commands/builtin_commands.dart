import 'package:glue/src/commands/slash_commands.dart';

/// Registration point for built-in slash commands.
class BuiltinCommands {
  static SlashCommandRegistry create({
    required void Function() openHelpPanel,
    required String Function() clearConversation,
    required void Function() requestExit,
    required void Function() openModelPanel,
    required String Function(String query) switchModelByQuery,
    required String Function() sessionInfo,
    required String Function() listTools,
    required void Function() openHistoryPanel,
    required void Function() openResumePanel,
    required String Function() openDevTools,
    required String Function() toggleDebug,
    required void Function() openSkillsPanel,
    required String Function(String skillName) activateSkillByName,
    required void Function() openPlansPanel,
  }) {
    final commands = SlashCommandRegistry();

    commands.register(SlashCommand(
      name: 'help',
      description: 'Show available commands and keybindings',
      execute: (_) {
        openHelpPanel();
        return '';
      },
    ));

    commands.register(SlashCommand(
      name: 'clear',
      description: 'Clear conversation history',
      execute: (_) => clearConversation(),
    ));

    commands.register(SlashCommand(
      name: 'exit',
      description: 'Exit Glue',
      aliases: ['quit'],
      hiddenAliases: ['q'],
      execute: (_) {
        requestExit();
        return '';
      },
    ));

    commands.register(SlashCommand(
      name: 'model',
      description: 'Switch model',
      execute: (args) {
        if (args.isEmpty) {
          openModelPanel();
          return '';
        }
        return switchModelByQuery(args.join(' '));
      },
    ));

    commands.register(SlashCommand(
      name: 'models',
      description: 'Browse and switch models across all providers',
      execute: (_) {
        openModelPanel();
        return '';
      },
    ));

    commands.register(SlashCommand(
      name: 'info',
      description: 'Show session info',
      aliases: ['status'],
      execute: (_) => sessionInfo(),
    ));

    commands.register(SlashCommand(
      name: 'tools',
      description: 'List available tools',
      execute: (_) => listTools(),
    ));

    commands.register(SlashCommand(
      name: 'history',
      description: 'Browse conversation history',
      execute: (_) {
        openHistoryPanel();
        return '';
      },
    ));

    commands.register(SlashCommand(
      name: 'resume',
      description: 'Resume a previous session',
      execute: (_) {
        openResumePanel();
        return '';
      },
    ));

    commands.register(SlashCommand(
      name: 'devtools',
      description: 'Open Dart DevTools in browser',
      execute: (_) => openDevTools(),
    ));

    commands.register(SlashCommand(
      name: 'debug',
      description: 'Toggle debug mode (verbose logging)',
      execute: (_) => toggleDebug(),
    ));

    commands.register(SlashCommand(
      name: 'skills',
      description: 'Browse available skills',
      execute: (args) {
        if (args.isEmpty) {
          openSkillsPanel();
          return '';
        }
        return activateSkillByName(args.join(' '));
      },
    ));

    commands.register(SlashCommand(
      name: 'plans',
      description: 'Browse plan files',
      execute: (_) {
        openPlansPanel();
        return '';
      },
    ));

    return commands;
  }
}
