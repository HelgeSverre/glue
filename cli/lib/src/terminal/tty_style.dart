/// TTY/NO_COLOR-aware adapter on top of `Styled`. Use for any CLI output
/// the user might pipe (grep, redirect, capture) — falls back to plain
/// text when stdout is not a terminal or `NO_COLOR` is set.
///
/// Terminal-rendering code (markdown renderer, TUI components) should keep
/// using the raw `.styled` API; it always wants ANSI because it's writing
/// directly to a real terminal screen.
library;

import 'dart:io';

import 'package:glue/src/terminal/styled.dart';

/// `true` when stdout is a real terminal and the user has not opted out via
/// `NO_COLOR` (https://no-color.org/).
bool stdoutSupportsAnsi() {
  if (Platform.environment.containsKey('NO_COLOR')) return false;
  try {
    return stdout.hasTerminal;
  } on Object {
    return false;
  }
}

/// Apply [decorate] to [text].styled and stringify it, but only when ANSI
/// is enabled. Otherwise return [text] unchanged so piped output stays
/// grep-friendly.
String styledOrPlain(
  String text,
  Styled Function(Styled) decorate, {
  bool? ansiEnabled,
}) {
  final enabled = ansiEnabled ?? stdoutSupportsAnsi();
  return enabled ? decorate(text.styled).toString() : text;
}
