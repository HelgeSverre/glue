import 'dart:io';

/// Snapshot of how Glue is connected to its terminal at the moment of capture.
///
/// Used at boot time to write a `boot.diagnostics` span, by `glue doctor` to
/// show the user what kind of stdio they have, and by [enableRawMode] crash
/// paths to inline a self-explanatory error message.
class TerminalDiagnostics {
  TerminalDiagnostics({
    required this.stdinHasTerminal,
    required this.stdoutHasTerminal,
    required this.stderrHasTerminal,
    required this.stdoutSupportsAnsiEscapes,
    required this.terminalColumns,
    required this.terminalLines,
    required this.term,
    required this.termProgram,
    required this.termProgramVersion,
    required this.colorterm,
    required this.lcTerminal,
    required this.markers,
    required this.executable,
    required this.executableArgs,
    required this.runningUnderDartDebugger,
    required this.platformOs,
    required this.verdict,
  });

  final bool stdinHasTerminal;
  final bool stdoutHasTerminal;
  final bool stderrHasTerminal;
  final bool stdoutSupportsAnsiEscapes;

  /// `null` when stdout isn't a terminal.
  final int? terminalColumns;
  final int? terminalLines;

  final String? term;
  final String? termProgram;
  final String? termProgramVersion;
  final String? colorterm;
  final String? lcTerminal;

  /// Detected environment markers (e.g. `tmux`, `ssh`, `ghostty`, `kitty`,
  /// `wezterm`, `iterm2`, `vscode`, `intellij`). Empty if none recognised.
  final List<String> markers;

  final String executable;
  final List<String> executableArgs;
  final bool runningUnderDartDebugger;
  final String platformOs;

  /// Short heuristic label like `iTerm2 (full TUI)` /
  /// `IntelliJ debug, no PTY` / `Pipe (no terminal)`.
  final String verdict;

  /// Captures the current process / environment.
  static TerminalDiagnostics collect() {
    final env = Platform.environment;
    final args = Platform.executableArguments;
    final underDebugger =
        args.any((a) => a.startsWith('--enable-vm-service')) ||
            args.contains('--pause_isolates_on_start');

    final markers = <String>[];
    if (env['TMUX'] != null) markers.add('tmux');
    if (env['STY'] != null) markers.add('screen');
    if (env['SSH_TTY'] != null || env['SSH_CONNECTION'] != null) {
      markers.add('ssh');
    }
    final tp = env['TERM_PROGRAM'];
    if (tp == 'iTerm.app') markers.add('iterm2');
    if (tp == 'Apple_Terminal') markers.add('apple-terminal');
    if (tp == 'ghostty' || env['GHOSTTY_RESOURCES_DIR'] != null) {
      markers.add('ghostty');
    }
    if (tp == 'WezTerm' || env['WEZTERM_PANE'] != null) markers.add('wezterm');
    if (env['KITTY_WINDOW_ID'] != null) markers.add('kitty');
    if (tp == 'vscode' || env['VSCODE_PID'] != null) markers.add('vscode');
    if (env['WT_SESSION'] != null) markers.add('windows-terminal');
    if (env['INSIDE_EMACS'] != null) markers.add('emacs');
    if (env['IDEA_INITIAL_DIRECTORY'] != null ||
        env['JETBRAINS_REMOTE_RUN'] != null ||
        env.keys.any((k) => k.startsWith('_INTELLIJ_FORCE_'))) {
      markers.add('intellij');
    }
    if (underDebugger) markers.add('dart-vm-debugger');

    final stdinTty = stdin.hasTerminal;
    final stdoutTty = stdout.hasTerminal;

    final verdict = _verdict(
      stdinTty: stdinTty,
      stdoutTty: stdoutTty,
      markers: markers,
      underDebugger: underDebugger,
      termProgram: tp,
    );

    return TerminalDiagnostics(
      stdinHasTerminal: stdinTty,
      stdoutHasTerminal: stdoutTty,
      stderrHasTerminal: stderr.hasTerminal,
      stdoutSupportsAnsiEscapes: stdout.supportsAnsiEscapes,
      terminalColumns: stdoutTty ? stdout.terminalColumns : null,
      terminalLines: stdoutTty ? stdout.terminalLines : null,
      term: env['TERM'],
      termProgram: tp,
      termProgramVersion: env['TERM_PROGRAM_VERSION'],
      colorterm: env['COLORTERM'],
      lcTerminal: env['LC_TERMINAL'],
      markers: markers,
      executable: Platform.executable,
      executableArgs: args,
      runningUnderDartDebugger: underDebugger,
      platformOs: Platform.operatingSystem,
      verdict: verdict,
    );
  }

  static String _verdict({
    required bool stdinTty,
    required bool stdoutTty,
    required List<String> markers,
    required bool underDebugger,
    required String? termProgram,
  }) {
    if (!stdinTty && !stdoutTty) {
      if (underDebugger && markers.contains('intellij')) {
        return 'IntelliJ/PhpStorm debug console (no PTY) — '
            'enable "Emulate terminal in output console" in the Run Configuration';
      }
      return 'No terminal (pipe / redirected stdio) — interactive TUI not available';
    }
    if (!stdinTty) {
      return 'stdout is a terminal but stdin is not — likely piped input; use --print/-p';
    }
    if (!stdoutTty) {
      return 'stdin is a terminal but stdout is not — output is being captured';
    }
    // Both are TTYs. Pick the most specific marker.
    final friendly = {
      'ghostty': 'Ghostty',
      'iterm2': 'iTerm2',
      'apple-terminal': 'Apple Terminal',
      'wezterm': 'WezTerm',
      'kitty': 'Kitty',
      'vscode': 'VSCode integrated terminal',
      'windows-terminal': 'Windows Terminal',
    };
    String? base;
    for (final entry in friendly.entries) {
      if (markers.contains(entry.key)) {
        base = entry.value;
        break;
      }
    }
    base ??= termProgram ?? 'unknown terminal';
    final muxes = <String>[];
    if (markers.contains('tmux')) muxes.add('tmux');
    if (markers.contains('screen')) muxes.add('screen');
    if (markers.contains('ssh')) muxes.add('ssh');
    final muxSuffix = muxes.isEmpty ? '' : ' (via ${muxes.join(' + ')})';
    final debugSuffix = underDebugger ? ' [under Dart debugger]' : '';
    return '$base$muxSuffix$debugSuffix — full TUI';
  }

  /// Flat key→string attribute map suitable for an observability span.
  Map<String, dynamic> toAttributes() => {
        'stdin.has_terminal': stdinHasTerminal,
        'stdout.has_terminal': stdoutHasTerminal,
        'stderr.has_terminal': stderrHasTerminal,
        'stdout.supports_ansi': stdoutSupportsAnsiEscapes,
        if (terminalColumns != null) 'terminal.columns': terminalColumns,
        if (terminalLines != null) 'terminal.lines': terminalLines,
        if (term != null) 'env.TERM': term,
        if (termProgram != null) 'env.TERM_PROGRAM': termProgram,
        if (termProgramVersion != null)
          'env.TERM_PROGRAM_VERSION': termProgramVersion,
        if (colorterm != null) 'env.COLORTERM': colorterm,
        if (lcTerminal != null) 'env.LC_TERMINAL': lcTerminal,
        'markers': markers,
        'process.executable': executable,
        'process.executable_args': executableArgs,
        'process.under_dart_debugger': runningUnderDartDebugger,
        'platform.os': platformOs,
        'verdict': verdict,
      };

  /// Human-readable lines (one fact per line) for `glue doctor` and the
  /// raw-mode error message.
  List<String> toReportLines() {
    final lines = <String>[
      'Verdict: $verdict',
      'stdin.hasTerminal: $stdinHasTerminal',
      'stdout.hasTerminal: $stdoutHasTerminal${terminalColumns != null ? ' ($terminalColumns × $terminalLines)' : ''}',
      'stderr.hasTerminal: $stderrHasTerminal',
      'stdout.supportsAnsiEscapes: $stdoutSupportsAnsiEscapes',
      'TERM: ${term ?? '(unset)'}',
      'TERM_PROGRAM: ${termProgram ?? '(unset)'}${termProgramVersion != null ? ' v$termProgramVersion' : ''}',
      if (colorterm != null) 'COLORTERM: $colorterm',
      if (lcTerminal != null) 'LC_TERMINAL: $lcTerminal',
      'markers: ${markers.isEmpty ? '(none)' : markers.join(', ')}',
      'platform: $platformOs',
      'executable: $executable',
      if (executableArgs.isNotEmpty)
        'executable args: ${executableArgs.join(' ')}',
    ];
    return lines;
  }
}
