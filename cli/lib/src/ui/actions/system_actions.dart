import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'package:glue/src/commands/config_command.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/core/path_opener.dart';
import 'package:glue/src/core/where_report.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/ui/components/panel.dart';
import 'package:glue/src/ui/services/panels.dart';

/// Build the lines shown in the `/help` panel at a given content width.
///
/// The key column scales with the terminal — `clamp(contentWidth / 3, 10, 18)`.
@visibleForTesting
List<String> buildHelpLines(List<SlashCommand> commands, int contentWidth) {
  final keyColWidth = math.max(10, math.min(18, contentWidth ~/ 3));

  final lines = <String>[];
  lines.add('${'■ COMMANDS'.styled.cyan}');
  lines.add('');
  for (final cmd in commands) {
    final aliases = cmd.aliases.isNotEmpty
        ? ' ${'(${cmd.aliases.map((a) => '/$a').join(', ')})'.styled.gray}'
        : '';
    final name = '/${cmd.name}'.padRight(keyColWidth);
    lines.add('  ${name.styled.cyan}${cmd.description}$aliases');
  }

  lines.add('');
  lines.add('${'■ KEYBINDINGS'.styled.cyan}');
  lines.add('');
  for (final b in const [
    ('Ctrl+C', 'Cancel / Exit'),
    ('Escape', 'Cancel generation'),
    ('Up / Down', 'History navigation'),
    ('Ctrl+U', 'Clear line'),
    ('Ctrl+W', 'Delete word'),
    ('Ctrl+A / E', 'Start / End of line'),
    ('PageUp / Dn', 'Scroll output'),
    ('Tab', 'Accept completion'),
  ]) {
    lines.add('  ${b.$1.padRight(keyColWidth)}${b.$2}');
  }

  lines.add('');
  lines.add('${'■ PERMISSIONS'.styled.cyan}');
  lines.add('');
  for (final b in const [
    ('Shift+Tab', 'Cycle tool approval mode'),
    ('/session', 'View current session info'),
  ]) {
    lines.add('  ${b.$1.padRight(keyColWidth)}${b.$2}');
  }

  lines.add('');
  lines.add('${'■ FILE REFERENCES'.styled.cyan}');
  lines.add('');
  for (final b in const [
    ('@path/to/file', 'Attach file to message'),
    ('@dir/', 'Browse directory'),
  ]) {
    lines.add('  ${b.$1.padRight(keyColWidth)}${b.$2}');
  }

  return lines;
}

class SystemActions {
  SystemActions({
    required this.environment,
    required void Function() requestExit,
    required this.panels,
    required this.commands,
    required this.render,
    required this.currentSessionId,
    this.debugController,
  }) : _requestExit = requestExit;

  final Environment environment;
  final void Function() _requestExit;
  final Panels panels;
  final List<SlashCommand> Function() commands;
  final void Function() render;
  final String? Function() currentSessionId;
  final DebugController? debugController;

  static const _openTargets = <String>[
    'home',
    'session',
    'sessions',
    'logs',
    'skills',
    'plans',
    'cache',
  ];

  void requestExit() => _requestExit();

  void openHelpPanel() {
    final slashCommands = commands();
    final panel = Panel.responsive(
      title: 'HELP',
      linesBuilder: (w) => buildHelpLines(slashCommands, w),
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.6, 10),
    );
    panels.push(panel);
    panel.result.then((_) => panels.remove(panel));
  }

  String toggleDebug() {
    final controller = debugController;
    if (controller == null) return 'Debug mode: unavailable';
    controller.toggle();
    return 'Debug mode: ${controller.enabled}';
  }

  String pathsReport() => buildWhereReport(environment);

  String configAction(List<String> args) {
    final subcommand = args.isEmpty ? '' : args.first.toLowerCase();
    switch (subcommand) {
      case '':
        return _openConfigInEditor();
      case 'init':
        return _initUserConfig(args.skip(1).toList());
      default:
        return 'Unknown subcommand "$subcommand". Try: /config or /config init';
    }
  }

  String _openConfigInEditor() {
    final editor = environment.vars['EDITOR']?.trim();
    if (editor == null || editor.isEmpty) {
      return r'EDITOR is not set. Set $EDITOR to use /config.';
    }

    final path = environment.configYamlPath;
    final file = File(path);
    if (!file.existsSync()) {
      try {
        initUserConfig(environment);
      } on FileSystemException catch (e) {
        return 'Failed to write config: ${e.message}';
      }
    }

    unawaited(Process.start(editor, [path], runInShell: true));
    return 'Opening $path in $editor';
  }

  String _initUserConfig(List<String> args) {
    final force = args.contains('--force');
    final unknown = args.where((arg) => arg != '--force').toList();
    if (unknown.isNotEmpty) {
      return 'Usage: /config init [--force]';
    }
    try {
      return initUserConfig(environment, force: force).message;
    } on FileSystemException catch (e) {
      return 'Failed to write config: ${e.message}';
    }
  }

  String openGlueTarget(List<String> args) {
    if (args.isEmpty) {
      return 'Usage: /open <target>\nTargets: ${_openTargets.join(', ')}';
    }

    final target = args.first.toLowerCase();
    String path;
    switch (target) {
      case 'home':
        path = environment.glueDir;
      case 'session':
        final id = currentSessionId();
        if (id == null) return 'No active session yet — nothing to open.';
        path = environment.sessionDir(id);
      case 'sessions':
        path = environment.sessionsDir;
      case 'logs':
        path = environment.logsDir;
      case 'skills':
        path = environment.skillsDir;
      case 'plans':
        path = environment.plansDir;
      case 'cache':
        path = environment.cacheDir;
      default:
        return 'Unknown target "$target". Try: ${_openTargets.join(', ')}';
    }

    if (!Directory(path).existsSync()) {
      return '$path\n(not yet created — open skipped)';
    }

    unawaited(openInFileManager(path));
    return 'Opening $path';
  }
}
