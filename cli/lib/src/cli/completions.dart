import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:cli_completion/installer.dart';
import 'package:path/path.dart' as p;

class CompletionsCommand extends Command<int> {
  CompletionsCommand() {
    addSubcommand(CompletionsInstallCommand());
    addSubcommand(CompletionsUninstallCommand());
  }

  @override
  String get name => 'completions';

  @override
  String get description => 'Manage shell completions for glue.';
}

enum CompletionShell { bash, zsh, fish, powershell, sh }

const _supportedShellValues = [
  'bash',
  'zsh',
  'fish',
  'powershell',
  'pwsh',
  'sh',
];

abstract class _CompletionsLeafCommand extends Command<int> {
  _CompletionsLeafCommand() {
    argParser.addOption(
      'shell',
      allowed: _supportedShellValues,
      help: 'Shell to target (defaults to auto-detected shell). Use '
          'powershell for both pwsh and Windows PowerShell.',
    );
  }

  CompletionCommandRunner<int> get completionRunner =>
      runner! as CompletionCommandRunner<int>;

  CompletionShell resolveShell() {
    final shellValue = argResults!.option('shell');
    final shell = shellValue == null
        ? _detectShell(Platform.environment)
        : _parseShell(shellValue);
    if (shell == null) {
      usageException(
        'Could not detect shell. Pass --shell one of: '
        '${_supportedShellValues.join(', ')}.',
      );
    }
    return shell;
  }
}

class CompletionsInstallCommand extends _CompletionsLeafCommand {
  @override
  String get name => 'install';

  @override
  String get description => 'Install shell completion scripts.';

  @override
  Future<int> run() async {
    final shell = resolveShell();
    if (shell == CompletionShell.sh) {
      stderr.writeln(
        'The "sh" shell has no standard programmable completion system. '
        'Use --shell bash, zsh, fish, or powershell.',
      );
      return 2;
    }
    try {
      _installCompletions(completionRunner, shell);
      return 0;
    } on CompletionInstallationException catch (e) {
      stderr.writeln(e);
      return 1;
    } on Exception catch (e) {
      stderr.writeln('Failed to install completions: $e');
      return 1;
    }
  }
}

class CompletionsUninstallCommand extends _CompletionsLeafCommand {
  @override
  String get name => 'uninstall';

  @override
  String get description => 'Uninstall shell completion scripts.';

  @override
  Future<int> run() async {
    final shell = resolveShell();
    if (shell == CompletionShell.sh) {
      stderr.writeln(
        'The "sh" shell has no standard programmable completion system.',
      );
      return 2;
    }
    try {
      _uninstallCompletions(completionRunner, shell);
      return 0;
    } on CompletionUninstallationException catch (e) {
      stderr.writeln(e);
      return 1;
    } on Exception catch (e) {
      stderr.writeln('Failed to uninstall completions: $e');
      return 1;
    }
  }
}

CompletionShell? _parseShell(String value) {
  switch (value.toLowerCase()) {
    case 'bash':
      return CompletionShell.bash;
    case 'zsh':
      return CompletionShell.zsh;
    case 'fish':
      return CompletionShell.fish;
    case 'powershell':
    case 'pwsh':
      return CompletionShell.powershell;
    case 'sh':
      return CompletionShell.sh;
  }
  return null;
}

CompletionShell? _detectShell(Map<String, String> environment) {
  if (environment['ZSH_NAME'] != null) {
    return CompletionShell.zsh;
  }
  if (environment['BASH'] != null) {
    return CompletionShell.bash;
  }
  if (environment['FISH_VERSION'] != null) {
    return CompletionShell.fish;
  }

  final shellPath = environment['SHELL'];
  if (shellPath != null && shellPath.isNotEmpty) {
    final shellName = p.basename(shellPath).toLowerCase();
    final parsed = _parseShell(shellName);
    if (parsed != null) {
      return parsed;
    }
  }

  if (Platform.isWindows) {
    return CompletionShell.powershell;
  }

  return null;
}

void _installCompletions(
  CompletionCommandRunner<int> runner,
  CompletionShell shell,
) {
  switch (shell) {
    case CompletionShell.bash:
      _installCliCompletion(runner, SystemShell.bash);
    case CompletionShell.zsh:
      _installCliCompletion(runner, SystemShell.zsh);
    case CompletionShell.fish:
      _installFishCompletion(runner.executableName);
    case CompletionShell.powershell:
      _installPowerShellCompletion(runner.executableName);
    case CompletionShell.sh:
      throw StateError(
        'The "sh" shell has no standard programmable completion system. '
        'Use bash, zsh, fish, or powershell.',
      );
  }
}

void _uninstallCompletions(
  CompletionCommandRunner<int> runner,
  CompletionShell shell,
) {
  switch (shell) {
    case CompletionShell.bash:
      _uninstallCliCompletion(runner, SystemShell.bash);
    case CompletionShell.zsh:
      _uninstallCliCompletion(runner, SystemShell.zsh);
    case CompletionShell.fish:
      _uninstallFishCompletion(runner.executableName);
    case CompletionShell.powershell:
      _uninstallPowerShellCompletion(runner.executableName);
    case CompletionShell.sh:
      throw StateError(
        'The "sh" shell has no standard programmable completion system. '
        'Nothing to uninstall.',
      );
  }
}

void _installCliCompletion(
  CompletionCommandRunner<int> runner,
  SystemShell systemShell,
) {
  final completionInstallation = CompletionInstallation.fromSystemShell(
    systemShell: systemShell,
    logger: runner.completionInstallationLogger,
    environmentOverride: Platform.environment,
  );
  completionInstallation.install(runner.executableName, force: true);
}

void _uninstallCliCompletion(
  CompletionCommandRunner<int> runner,
  SystemShell systemShell,
) {
  final completionInstallation = CompletionInstallation.fromSystemShell(
    systemShell: systemShell,
    logger: runner.completionInstallationLogger,
    environmentOverride: Platform.environment,
  );
  completionInstallation.uninstall(runner.executableName);
}

void _installFishCompletion(String executableName) {
  final home = _homeDirectory();
  final completionsDir =
      Directory(p.join(home, '.config', 'fish', 'completions'));
  completionsDir.createSync(recursive: true);
  final scriptFile = File(p.join(completionsDir.path, '$executableName.fish'));
  scriptFile.writeAsStringSync(_fishCompletionScript(executableName));
  stdout.writeln('Installed fish completion: ${scriptFile.path}');
}

void _uninstallFishCompletion(String executableName) {
  final home = _homeDirectory();
  final scriptFile = File(
    p.join(home, '.config', 'fish', 'completions', '$executableName.fish'),
  );
  if (scriptFile.existsSync()) {
    scriptFile.deleteSync();
  }
  stdout.writeln('Uninstalled fish completion: ${scriptFile.path}');
}

void _installPowerShellCompletion(String executableName) {
  final home = _homeDirectory();
  final completionDir = Directory(p.join(home, '.glue', 'completions'));
  completionDir.createSync(recursive: true);

  final scriptFile = File(p.join(completionDir.path, '$executableName.ps1'));
  scriptFile.writeAsStringSync(_powerShellCompletionScript(executableName));

  final profileFile = File(_resolvePowerShellProfilePath(home));
  profileFile.parent.createSync(recursive: true);
  if (!profileFile.existsSync()) {
    profileFile.createSync(recursive: true);
  }

  final startMarker = '# >>> $executableName completions (powershell) >>>';
  final endMarker = '# <<< $executableName completions (powershell) <<<';
  final sourceLine =
      'if (Test-Path ${_psSingleQuoted(scriptFile.path)}) { . ${_psSingleQuoted(scriptFile.path)} }';
  _upsertManagedBlock(profileFile, startMarker, endMarker, sourceLine);

  stdout.writeln('Installed PowerShell completion: ${scriptFile.path}');
  stdout.writeln('Updated PowerShell profile: ${profileFile.path}');
}

void _uninstallPowerShellCompletion(String executableName) {
  final home = _homeDirectory();
  final scriptFile =
      File(p.join(home, '.glue', 'completions', '$executableName.ps1'));
  if (scriptFile.existsSync()) {
    scriptFile.deleteSync();
  }

  final profileFile = File(_resolvePowerShellProfilePath(home));
  final startMarker = '# >>> $executableName completions (powershell) >>>';
  final endMarker = '# <<< $executableName completions (powershell) <<<';
  if (profileFile.existsSync()) {
    _removeManagedBlock(profileFile, startMarker, endMarker);
  }

  stdout.writeln('Uninstalled PowerShell completion: ${scriptFile.path}');
}

String _homeDirectory() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) {
    throw StateError('Could not resolve HOME/USERPROFILE.');
  }
  return home;
}

String _resolvePowerShellProfilePath(String home) {
  for (final executable in ['pwsh', 'powershell']) {
    try {
      final result = Process.runSync(
        executable,
        ['-NoProfile', '-Command', r'$PROFILE.CurrentUserAllHosts'],
      );
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        if (path.isNotEmpty) {
          return path;
        }
      }
    } on Object {
      // Fall through to default path.
    }
  }

  if (Platform.isWindows) {
    return p.join(
      home,
      'Documents',
      'PowerShell',
      'Microsoft.PowerShell_profile.ps1',
    );
  }
  return p.join(
    home,
    '.config',
    'powershell',
    'Microsoft.PowerShell_profile.ps1',
  );
}

String _psSingleQuoted(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

void _upsertManagedBlock(
  File file,
  String startMarker,
  String endMarker,
  String body,
) {
  var content = file.readAsStringSync();
  content = _withoutManagedBlock(content, startMarker, endMarker).trimRight();
  final block = StringBuffer()
    ..writeln(startMarker)
    ..writeln(body)
    ..writeln(endMarker);
  if (content.isNotEmpty) {
    content = '$content\n\n${block.toString()}';
  } else {
    content = block.toString();
  }
  file.writeAsStringSync('$content\n');
}

void _removeManagedBlock(File file, String startMarker, String endMarker) {
  final content = file.readAsStringSync();
  final updated =
      _withoutManagedBlock(content, startMarker, endMarker).trimRight();
  if (updated.isEmpty) {
    file.writeAsStringSync('');
  } else {
    file.writeAsStringSync('$updated\n');
  }
}

String _withoutManagedBlock(
  String content,
  String startMarker,
  String endMarker,
) {
  var updated = content;
  while (true) {
    final start = updated.indexOf(startMarker);
    if (start < 0) {
      return updated;
    }
    final end = updated.indexOf(endMarker, start);
    if (end < 0) {
      return updated;
    }
    var removeEnd = end + endMarker.length;
    while (removeEnd < updated.length &&
        (updated[removeEnd] == '\n' || updated[removeEnd] == '\r')) {
      removeEnd++;
    }
    updated = '${updated.substring(0, start)}${updated.substring(removeEnd)}';
  }
}

String _fishCompletionScript(String executableName) {
  return '''
function __${executableName}_completion
  set -l line (commandline -cp)
  set -l words (commandline -opc)
  set -l cword (math (count \$words) - 1)
  if string match -qr '\\s\$' -- \$line
    set cword (count \$words)
  end

  env COMP_CWORD="\$cword" \\
      COMP_LINE="\$line" \\
      COMP_POINT=(string length -- \$line) \\
      $executableName completion -- \$words 2>/dev/null
end

complete -f -c $executableName -a "(__${executableName}_completion)"
''';
}

String _powerShellCompletionScript(String executableName) {
  return '''
Register-ArgumentCompleter -Native -CommandName $executableName -ScriptBlock {
  param(\$wordToComplete, \$commandAst, \$cursorPosition)

  \$line = \$commandAst.ToString()
  \$words = @(\$commandAst.CommandElements | ForEach-Object { \$_.Extent.Text })
  \$cword = [Math]::Max(\$words.Count - 1, 0)
  if (\$line -match '\\s\$') { \$cword = \$words.Count }

  \$oldCompCword = \$env:COMP_CWORD
  \$oldCompLine = \$env:COMP_LINE
  \$oldCompPoint = \$env:COMP_POINT
  try {
    \$env:COMP_CWORD = "\$cword"
    \$env:COMP_LINE = \$line
    \$env:COMP_POINT = "\$cursorPosition"

    & $executableName completion -- @words 2>\$null | ForEach-Object {
      if (\$_.Length -gt 0) {
        [System.Management.Automation.CompletionResult]::new(\$_, \$_, 'ParameterValue', \$_)
      }
    }
  } finally {
    \$env:COMP_CWORD = \$oldCompCword
    \$env:COMP_LINE = \$oldCompLine
    \$env:COMP_POINT = \$oldCompPoint
  }
}
''';
}
