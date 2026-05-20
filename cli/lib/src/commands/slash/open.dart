import 'dart:io';

import 'package:glue_harness/glue_harness.dart';

import 'package:glue/src/commands/arg_completers.dart' as arg_completers;
import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';

const _openTargets = <String>[
  'home',
  'session',
  'sessions',
  'logs',
  'skills',
  'cache',
];

/// `/open <target>` — open one of Glue's data directories in the OS file
/// manager.
class OpenCommand extends SlashCommand {
  OpenCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'open';

  @override
  String get description => 'Open a Glue directory in your file manager '
      '(${_openTargets.join(', ')})';

  @override
  SlashArgCompleter? get argCompleter => arg_completers.openArgCandidates;

  @override
  String execute(List<String> args) {
    if (args.isEmpty) {
      return 'Usage: /open <target>\n'
          'Targets: ${_openTargets.join(', ')}';
    }

    final target = args.first.toLowerCase();
    final env = ctx.environment;
    final String path;
    switch (target) {
      case 'home':
        path = env.glueDir;
      case 'session':
        final id = ctx.session.currentSessionId;
        if (id == null) return 'No active session yet — nothing to open.';
        path = env.sessionDir(id);
      case 'sessions':
        path = env.sessionsDir;
      case 'logs':
        path = env.logsDir;
      case 'skills':
        path = env.skillsDir;
      case 'cache':
        path = env.cacheDir;
      default:
        return 'Unknown target "$target". Try: ${_openTargets.join(', ')}';
    }

    if (!Directory(path).existsSync()) {
      return '$path\n(not yet created — open skipped)';
    }
    openInFileManager(path);
    return 'Opening $path';
  }
}
