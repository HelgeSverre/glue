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
    required String Function(List<String> args) sessionAction,
    required String Function() listTools,
    required void Function() openHistoryPanel,
    required String Function(String query) historyActionByQuery,
    required void Function() openResumePanel,
    required String Function(String query) resumeSessionByQuery,
    required String Function() toggleDebug,
    required void Function() openSkillsPanel,
    required String Function(String skillName) activateSkillByName,
    required String Function() toggleApproval,
    required String Function(List<String> args) runProviderCommand,
    required String Function() pathsReport,
    required String Function(List<String> args) openGlueTarget,
    required String Function(List<String> args) configAction,
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
      hiddenAliases: ['status'],
      execute: (_) => sessionInfo(),
    ));

    commands.register(SlashCommand(
      name: 'session',
      description: 'Show current session info, or /session copy to copy ID',
      execute: sessionAction,
    ));

    commands.register(SlashCommand(
      name: 'tools',
      description: 'List available tools',
      execute: (_) => listTools(),
    ));

    commands.register(SlashCommand(
      name: 'history',
      description: 'Browse history or fork by index/query',
      execute: (args) {
        if (args.isEmpty) {
          openHistoryPanel();
          return '';
        }
        return historyActionByQuery(args.join(' '));
      },
    ));

    commands.register(SlashCommand(
      name: 'resume',
      description: 'Resume a session (panel or by ID/query)',
      execute: (args) {
        if (args.isEmpty) {
          openResumePanel();
          return '';
        }
        return resumeSessionByQuery(args.join(' '));
      },
    ));

    commands.register(SlashCommand(
      name: 'debug',
      description: 'Toggle debug mode (verbose logging)',
      execute: (_) => toggleDebug(),
    ));

    commands.register(SlashCommand(
      name: 'skills',
      description: 'Browse skills or activate one by name',
      execute: (args) {
        if (args.isEmpty) {
          openSkillsPanel();
          return '';
        }
        return activateSkillByName(args.join(' '));
      },
    ));

    commands.register(SlashCommand(
      name: 'approve',
      description: 'Toggle approval mode (confirm ↔ auto)',
      execute: (_) => toggleApproval(),
    ));

    commands.register(SlashCommand(
      name: 'provider',
      description: 'Manage providers (list, add, remove, test)',
      execute: runProviderCommand,
    ));

    commands.register(SlashCommand(
      name: 'paths',
      description:
          'Show Glue data paths (config, sessions, logs, skills, plans, cache)',
      hiddenAliases: ['where'],
      execute: (_) => pathsReport(),
    ));

    commands.register(SlashCommand(
      name: 'config',
      description: 'Open config.yaml in \$EDITOR, or /config init in cwd',
      execute: configAction,
    ));

    commands.register(SlashCommand(
      name: 'open',
      description: 'Open a Glue directory in your file manager '
          '(home, session, sessions, logs, skills, plans, cache)',
      execute: openGlueTarget,
    ));

    return commands;
  }
}
