library;

import 'package:glue/src/terminal/brand.dart';
import 'package:glue/src/terminal/tty_style.dart';

String formatSetupCheck({required String home, bool? ansiEnabled}) {
  final ansi = ansiEnabled ?? stdoutSupportsAnsi();
  final dot = ansi ? '$brandDot ' : '';
  final ok = ansi ? '$markerOk ' : '';
  final info = ansi ? '$markerInfo ' : '';
  return [
    '$dot${styledOrPlain('Glue setup', (s) => s.bold, ansiEnabled: ansi)}',
    '  ${styledOrPlain('Configuration home:', (s) => s.gray, ansiEnabled: ansi)} $home',
    '',
    '  ${ok}Run ${styledOrPlain('glue config init', (s) => s.bold, ansiEnabled: ansi)}',
    '  ${ok}Run ${styledOrPlain('glue doctor', (s) => s.bold, ansiEnabled: ansi)}',
    '',
    '  $info${styledOrPlain('Set one model provider credential before using `glue acp`.', (s) => s.gray, ansiEnabled: ansi)}',
    '    export ANTHROPIC_API_KEY=...',
    '    export OPENAI_API_KEY=...',
    '    or choose GitHub Copilot in the interactive UI.',
  ].join('\n');
}
