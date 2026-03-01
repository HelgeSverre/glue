enum ShellMode {
  /// Default. No extra flags — fastest startup, no rc/profile sourcing.
  nonInteractive,

  /// Passes `-i` to the shell, which loads the user's rc file (e.g. `.bashrc`).
  /// Useful when commands depend on aliases or environment set up in rc files.
  interactive,

  /// Passes `-l` (or `--login` for fish) to the shell, which sources the
  /// full login profile (e.g. `.bash_profile`). Use when PATH or other
  /// login-time variables are needed.
  login;

  /// Parses a mode string from config. Returns [nonInteractive] for any
  /// unrecognized value, so typos fail safe rather than loud.
  static ShellMode fromString(String s) => switch (s) {
        'interactive' => ShellMode.interactive,
        'login' => ShellMode.login,
        _ => ShellMode.nonInteractive,
      };
}

/// Configuration for the shell used to execute commands.
///
/// Different shells need different flags — for example, fish uses `--login`
/// instead of `-l`, and PowerShell uses `-Command` instead of `-c`. This
/// class normalizes those differences so the rest of the codebase doesn't
/// need to care which shell is in use.
class ShellConfig {
  final String executable;
  final ShellMode mode;

  const ShellConfig({
    this.executable = 'sh',
    this.mode = ShellMode.nonInteractive,
  });

  factory ShellConfig.detect({
    String? explicit,
    String? shellEnv,
    ShellMode mode = ShellMode.nonInteractive,
  }) {
    final exe = explicit ?? shellEnv ?? 'sh';
    return ShellConfig(executable: exe, mode: mode);
  }

  String get _baseName {
    final name = executable.split('/').last;
    if (name == 'powershell' || name == 'powershell.exe') return 'pwsh';
    if (name.endsWith('.exe')) return name.replaceAll('.exe', '');
    return name;
  }

  bool get _isPowerShell => _baseName == 'pwsh';

  List<String> buildArgs(String command) {
    if (_isPowerShell) {
      return [
        executable,
        if (mode == ShellMode.nonInteractive) '-NoProfile',
        '-Command',
        command,
      ];
    }

    final isFish = _baseName == 'fish';
    return [
      executable,
      if (mode == ShellMode.interactive) '-i',
      if (mode == ShellMode.login) ...[if (isFish) '--login' else '-l'],
      '-c',
      command,
    ];
  }
}
