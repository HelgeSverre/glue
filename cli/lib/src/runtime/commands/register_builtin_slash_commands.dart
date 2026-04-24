import 'package:glue/src/commands/arg_completers.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/runtime/commands/command_host.dart';
import 'package:glue/src/runtime/commands/command_module.dart';
import 'package:glue/src/share/share_module.dart';

SlashCommandRegistry buildBuiltinSlashCommands(SlashCommandContext context) {
  final registry = SlashCommandRegistry();
  for (final module in _builtinCommandModules) {
    module.register(registry, context);
  }
  for (final module in _builtinCommandModules) {
    module.attachArgCompleters(registry, context);
  }
  return registry;
}

const List<SlashCommandModule> _builtinCommandModules = [
  _CoreCommandModule(),
  _ModelCommandModule(),
  _SessionCommandModule(),
  ShareCommandModule(),
  _SkillsCommandModule(),
  _ProviderCommandModule(),
  _SystemCommandModule(),
];

class _CoreCommandModule implements SlashCommandModule {
  const _CoreCommandModule();

  @override
  void register(SlashCommandRegistry registry, SlashCommandContext context) {
    registry.register(SlashCommand(
      name: 'help',
      description: 'Show available commands and keybindings',
      execute: (_) {
        context.system.openHelpPanel();
        return '';
      },
    ));

    registry.register(SlashCommand(
      name: 'clear',
      description: 'Clear conversation history',
      execute: (_) => context.chat.clearConversation(),
    ));

    registry.register(SlashCommand(
      name: 'exit',
      description: 'Exit Glue',
      aliases: ['quit'],
      hiddenAliases: ['q'],
      execute: (_) {
        context.system.requestExit();
        return '';
      },
    ));

    registry.register(SlashCommand(
      name: 'tools',
      description: 'List available tools',
      execute: (_) => context.chat.listTools(),
    ));

    registry.register(SlashCommand(
      name: 'copy',
      description: 'Copy last response to clipboard',
      execute: (_) {
        context.chat.copyLastResponse();
        return '';
      },
    ));

    registry.register(SlashCommand(
      name: 'debug',
      description: 'Toggle debug mode (verbose logging)',
      execute: (_) => context.system.toggleDebug(),
    ));

    registry.register(SlashCommand(
      name: 'approve',
      description: 'Toggle approval mode (confirm ↔ auto)',
      execute: (_) => context.chat.toggleApproval(),
    ));
  }

  @override
  void attachArgCompleters(
    SlashCommandRegistry registry,
    SlashCommandContext context,
  ) {}
}

class _ModelCommandModule implements SlashCommandModule {
  const _ModelCommandModule();

  @override
  void register(SlashCommandRegistry registry, SlashCommandContext context) {
    registry.register(SlashCommand(
      name: 'model',
      description:
          'Switch model (no args = picker, with arg = switch directly)',
      aliases: ['models'],
      execute: (args) {
        if (args.isEmpty) {
          context.models.openModelPanel();
          return '';
        }
        return context.models.switchModelByQuery(args.join(' '));
      },
    ));
  }

  @override
  void attachArgCompleters(
    SlashCommandRegistry registry,
    SlashCommandContext context,
  ) {
    registry.attachArgCompleter('model', modelArgCompleter(context.config));
  }
}

class _SessionCommandModule implements SlashCommandModule {
  const _SessionCommandModule();

  @override
  void register(SlashCommandRegistry registry, SlashCommandContext context) {
    registry.register(SlashCommand(
      name: 'session',
      description: 'Show current session info, or /session copy to copy ID',
      execute: context.sessions.sessionAction,
    ));

    registry.register(SlashCommand(
      name: 'history',
      description: 'Browse history or fork by index/query',
      execute: (args) {
        if (args.isEmpty) {
          context.sessions.openHistoryPanel();
          return '';
        }
        return context.sessions.historyActionByQuery(args.join(' '));
      },
    ));

    registry.register(SlashCommand(
      name: 'resume',
      description: 'Resume a session (panel or by ID/query)',
      execute: (args) {
        if (args.isEmpty) {
          context.sessions.openResumePanel();
          return '';
        }
        return context.sessions.resumeSessionByQuery(args.join(' '));
      },
    ));

    registry.register(SlashCommand(
      name: 'rename',
      description: 'Rename the current session',
      execute: (args) => context.sessions.renameSession(args.join(' ')),
    ));
  }

  @override
  void attachArgCompleters(
    SlashCommandRegistry registry,
    SlashCommandContext context,
  ) {
    registry.attachArgCompleter('session', sessionArgCompleter());
  }
}

class _SkillsCommandModule implements SlashCommandModule {
  const _SkillsCommandModule();

  @override
  void register(SlashCommandRegistry registry, SlashCommandContext context) {
    registry.register(SlashCommand(
      name: 'skills',
      description: 'Browse skills or activate one by name',
      execute: (args) {
        if (args.isEmpty) {
          context.skills.openSkillsPanel();
          return '';
        }
        return context.skills.activateSkillByName(args.join(' '));
      },
    ));
  }

  @override
  void attachArgCompleters(
    SlashCommandRegistry registry,
    SlashCommandContext context,
  ) {
    registry.attachArgCompleter(
      'skills',
      skillsArgCompleter(context.skillRuntime),
    );
  }
}

class _ProviderCommandModule implements SlashCommandModule {
  const _ProviderCommandModule();

  @override
  void register(SlashCommandRegistry registry, SlashCommandContext context) {
    registry.register(SlashCommand(
      name: 'provider',
      description: 'Manage providers (list, add, remove, test)',
      execute: context.providers.runProviderCommand,
    ));
  }

  @override
  void attachArgCompleters(
    SlashCommandRegistry registry,
    SlashCommandContext context,
  ) {
    registry.attachArgCompleter(
      'provider',
      providerArgCompleter(context.config),
    );
  }
}

class _SystemCommandModule implements SlashCommandModule {
  const _SystemCommandModule();

  @override
  void register(SlashCommandRegistry registry, SlashCommandContext context) {
    registry.register(SlashCommand(
      name: 'paths',
      description:
          'Show Glue data paths (config, sessions, logs, skills, plans, cache)',
      hiddenAliases: ['where'],
      execute: (_) => context.system.pathsReport(),
    ));

    registry.register(SlashCommand(
      name: 'config',
      description:
          'Open config.yaml in \$EDITOR, or initialize it with /config init',
      execute: context.system.configAction,
    ));

    registry.register(SlashCommand(
      name: 'open',
      description: 'Open a Glue directory in your file manager '
          '(home, session, sessions, logs, skills, plans, cache)',
      execute: context.system.openGlueTarget,
    ));
  }

  @override
  void attachArgCompleters(
    SlashCommandRegistry registry,
    SlashCommandContext context,
  ) {
    registry.attachArgCompleter('open', openArgCompleter());
  }
}
