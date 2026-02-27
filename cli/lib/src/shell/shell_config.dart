enum ShellMode {
  nonInteractive,
  interactive,
  login;

  static ShellMode fromString(String s) => switch (s) {
        'interactive' => ShellMode.interactive,
        'login' => ShellMode.login,
        _ => ShellMode.nonInteractive,
      };
}

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
