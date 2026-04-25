import 'dart:async';

import 'package:glue/src/commands/arg_completers.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/ui/actions/app_actions.dart';

class AppCommands {
  final SlashCommandRegistry registry = SlashCommandRegistry();

  void register(SlashCommand command) => registry.register(command);

  String? execute(String input) => registry.execute(input);

  List<SlashCommand> get all => registry.commands;
}

void registerCoreSlashCommands(AppCommands commands, AppActions actions) {
  final c = actions;

  commands.register(SlashCommand(
    name: 'help',
    description: 'Show available commands and keybindings',
    execute: (_) {
      c.system.openHelpPanel();
      return null;
    },
  ));

  commands.register(SlashCommand(
    name: 'clear',
    description: 'Clear conversation history',
    execute: (_) => c.chat.clearConversation(),
  ));

  commands.register(SlashCommand(
    name: 'compact',
    description: 'Summarize older turns to free context-window space',
    execute: (_) {
      unawaited(c.chat.compactContext());
      return null;
    },
  ));

  commands.register(SlashCommand(
    name: 'exit',
    description: 'Exit Glue',
    aliases: const ['quit'],
    hiddenAliases: const ['q'],
    execute: (_) {
      c.system.requestExit();
      return null;
    },
  ));

  commands.register(SlashCommand(
    name: 'tools',
    description: 'List available tools',
    execute: (_) => c.chat.listTools(),
  ));

  commands.register(SlashCommand(
    name: 'copy',
    description: 'Copy last response to clipboard',
    execute: (_) {
      c.chat.copyLastResponse();
      return null;
    },
  ));

  commands.register(SlashCommand(
    name: 'debug',
    description: 'Toggle debug mode (verbose logging)',
    execute: (_) => c.system.toggleDebug(),
  ));

  commands.register(SlashCommand(
    name: 'approve',
    description: 'Toggle approval mode (confirm <-> auto)',
    execute: (_) => c.chat.toggleApproval(),
  ));

  commands.register(SlashCommand(
    name: 'model',
    description: 'Switch model',
    completeArg: modelArgCompleter(c.config),
    execute: (args) {
      if (args.isEmpty) {
        c.models.openModelPanel();
        return null;
      } else {
        return c.models.switchModelByQuery(args.join(' '));
      }
    },
  ));

  commands.register(SlashCommand(
    name: 'session',
    description: 'Show current session info, or /session copy to copy ID',
    completeArg: sessionArgCompleter(),
    execute: c.sessions.sessionAction,
  ));

  commands.register(SlashCommand(
    name: 'history',
    description: 'Browse history or fork by index/query',
    execute: (args) {
      if (args.isEmpty) {
        c.sessions.openHistoryPanel();
        return null;
      } else {
        return c.sessions.historyActionByQuery(args.join(' '));
      }
    },
  ));

  commands.register(SlashCommand(
    name: 'resume',
    description: 'Resume a session (panel or by ID/query)',
    execute: (args) {
      if (args.isEmpty) {
        c.sessions.openResumePanel();
        return null;
      } else {
        return c.sessions.resumeSessionByQuery(args.join(' '));
      }
    },
  ));

  commands.register(SlashCommand(
    name: 'rename',
    description: 'Rename the current session',
    execute: (args) => c.sessions.renameSession(args.join(' ')),
  ));

  commands.register(SlashCommand(
    name: 'skills',
    description: 'Browse skills or activate one by name',
    completeArg: skillsArgCompleter(c.skillRuntime),
    execute: (args) {
      if (args.isEmpty) {
        c.skills.openSkillsPanel();
        return null;
      } else {
        return c.skills.activateSkillByName(args.join(' '));
      }
    },
  ));

  commands.register(SlashCommand(
    name: 'share',
    description: 'Export the current session as html, markdown, or gist',
    completeArg: shareArgCompleter(),
    execute: c.share.shareAction,
  ));

  commands.register(SlashCommand(
    name: 'provider',
    description: 'Manage providers (list, add, remove, test)',
    completeArg: providerArgCompleter(c.config),
    execute: c.providers.runProviderCommand,
  ));

  commands.register(SlashCommand(
    name: 'paths',
    description:
        'Show Glue data paths (config, sessions, logs, skills, plans, cache)',
    hiddenAliases: const ['where'],
    execute: (_) => c.system.pathsReport(),
  ));

  commands.register(SlashCommand(
    name: 'config',
    description: 'Open config.yaml in \$EDITOR, or initialize it with '
        '/config init',
    execute: c.system.configAction,
  ));

  commands.register(SlashCommand(
    name: 'open',
    description: 'Open a Glue directory in your file manager '
        '(home, session, sessions, logs, skills, plans, cache)',
    completeArg: openArgCompleter(),
    execute: c.system.openGlueTarget,
  ));
}
