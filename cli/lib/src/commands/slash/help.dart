import 'dart:math' as math;

import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/ui/panel_modal.dart';

/// `/help` — open the help panel listing every registered command.
class HelpCommand extends SlashCommand {
  HelpCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'help';

  @override
  String get description => 'Show available commands and keybindings';

  @override
  String execute(List<String> args) {
    final panel = PanelModal.responsive(
      title: 'HELP',
      linesBuilder: (w) => _buildHelpLines(ctx.commands.toList(), w),
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.6, 10),
    );
    ctx.panels.push(panel);
    panel.result.then((_) => ctx.panels.dismiss(panel));
    return '';
  }
}

/// The key column scales with the terminal — `clamp(contentWidth / 3, 10, 18)`
/// — so the panel rebalances as the terminal resizes.
List<String> _buildHelpLines(List<SlashCommand> commands, int contentWidth) {
  // Scale the key column with the terminal; min 10 for tightness, max 18
  // (the original fixed width).
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
