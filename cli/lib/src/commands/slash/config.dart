import 'dart:io';

import 'package:glue/src/commands/config_command.dart' as config_init;
import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';

/// `/config` — open `config.yaml` in `$EDITOR` or initialize it.
class ConfigCommand extends SlashCommand {
  ConfigCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'config';

  @override
  String get description =>
      r'Open config.yaml in $EDITOR, or initialize it with /config init';

  @override
  String execute(List<String> args) {
    final subcommand = args.isEmpty ? '' : args.first.toLowerCase();
    switch (subcommand) {
      case '':
        return _openInEditor();
      case 'init':
        return _initConfig(args.skip(1).toList());
      default:
        return 'Unknown subcommand "$subcommand". Try: /config or /config init';
    }
  }

  String _openInEditor() {
    final editor = ctx.environment.vars['EDITOR']?.trim();
    if (editor == null || editor.isEmpty) {
      return r'EDITOR is not set. Set $EDITOR to use /config.';
    }
    final path = ctx.environment.configYamlPath;
    if (!File(path).existsSync()) {
      try {
        config_init.initUserConfig(ctx.environment);
      } on FileSystemException catch (e) {
        return 'Failed to write config: ${e.message}';
      }
    }
    Process.start(editor, [path], runInShell: true);
    return 'Opening $path in $editor';
  }

  String _initConfig(List<String> rest) {
    final force = rest.contains('--force');
    final unknown = rest.where((arg) => arg != '--force').toList();
    if (unknown.isNotEmpty) return 'Usage: /config init [--force]';
    try {
      return config_init.initUserConfig(ctx.environment, force: force).message;
    } on FileSystemException catch (e) {
      return 'Failed to write config: ${e.message}';
    }
  }
}
