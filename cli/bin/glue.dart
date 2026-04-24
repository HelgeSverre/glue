import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:cli_completion/installer.dart';
import 'package:cli_completion/parser.dart';
import 'package:glue/glue.dart';
import 'package:path/path.dart' as p;

const appDescription = 'The coding agent that holds it all together.';

List<String> normalizeCliArgs(List<String> args) {
  final normalized = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--resume=')) {
      normalized.add('--resume-id=${arg.substring('--resume='.length)}');
      continue;
    }
    if (arg == '--resume' || arg == '-r') {
      final next = i + 1 < args.length ? args[i + 1] : null;
      if (next != null && !_looksLikeOption(next)) {
        normalized.add('--resume-id=$next');
        i++;
        continue;
      }
    }
    normalized.add(arg);
  }
  return normalized;
}

bool _looksLikeOption(String arg) => arg.startsWith('-');

void main(List<String> args) async {
  final runner = GlueCommandRunner();
  try {
    final exitCode = await runner.run(normalizeCliArgs(args)) ?? 0;
    exit(exitCode);
  } on UsageException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln();
    stderr.writeln(e.usage);
    exit(64);
  } on ConfigError catch (e) {
    // Thrown from GlueConfig.load when --model / GLUE_MODEL / config.yaml
    // can't be resolved against the catalog. Surface the message cleanly;
    // suppress the Dart stack trace, which carries no user value here.
    stderr.writeln('Error: ${e.message}');
    exit(78); // EX_CONFIG
  } on ModelRefParseException catch (e) {
    stderr.writeln('Error: ${e.message}');
    exit(78);
  }
}

class GlueCommandRunner extends CompletionCommandRunner<int> {
  GlueCommandRunner()
      : super(
          'glue',
          '\x1b[38;2;250;204;21m\u25cf\x1b[0m \x1b[1mglue\x1b[0m'
              ' v${AppConstants.version} — $appDescription',
        ) {
    argParser
      ..addFlag('version', abbr: 'v', negatable: false, help: 'Print version.')
      ..addFlag('where',
          negatable: false,
          help: 'Print the GLUE_HOME directory and resolved paths for config, '
              'credentials, sessions, logs, and cache.')
      ..addFlag('print',
          abbr: 'p',
          negatable: false,
          help: 'Print response to stdout without interactive mode.')
      ..addFlag('json',
          negatable: false,
          help: 'Output session conversation as JSON (implies --print).')
      ..addOption('model', abbr: 'm', help: 'LLM model to use.')
      ..addFlag(
        'resume',
        abbr: 'r',
        negatable: false,
        help: 'Resume a session by ID/query, or open the resume panel when '
            'omitted.',
      )
      ..addOption('resume-id', hide: true)
      ..addFlag('continue',
          negatable: false, help: 'Resume most recent session.')
      ..addFlag('debug',
          abbr: 'd',
          negatable: false,
          help: 'Enable debug mode (verbose logging).');
    addCommand(CompletionsCommand());
    addCommand(ConfigCommand());
    addCommand(DoctorCommand());
  }

  @override
  String get invocation => '$executableName [options] [prompt]';

  @override
  bool get enableAutoInstall => false;

  @override
  void renderCompletionResult(CompletionResult completionResult) {
    final shell = systemShell;
    for (final entry in completionResult.completions.entries) {
      if (shell == SystemShell.zsh) {
        final suggestion = entry.key.replaceAll(':', r'\:');
        final description = entry.value?.replaceAll(':', r'\:');
        completionLogger.info(
          '$suggestion${description != null ? ':$description' : ''}',
        );
      } else {
        completionLogger.info(entry.key);
      }
    }
  }

  @override
  void printUsage() {
    stdout.writeln(usage);
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.flag('version')) {
      if (topLevelResults.flag('debug')) {
        stdout.writeln(BuildInfo.details(appVersion: AppConstants.version));
      } else {
        stdout.writeln(
          'glue v${AppConstants.version} (${BuildInfo.summary})',
        );
      }
      return 0;
    }

    if (topLevelResults.flag('where')) {
      _printWhere();
      return 0;
    }

    if (topLevelResults.command == null) {
      if (topLevelResults.flag('help')) {
        printUsage();
        return 0;
      }

      await _runApp(topLevelResults);
      return 0;
    }

    return super.runCommand(topLevelResults);
  }

  void _printWhere() {
    stdout.write(buildWhereReport(Environment.detect()));
  }

  Future<void> _runApp(ArgResults topLevelResults) async {
    final model = topLevelResults.option('model');
    final jsonMode = topLevelResults.flag('json');
    final printMode = topLevelResults.flag('print') || jsonMode;
    final resumeSessionId = topLevelResults.option('resume-id');
    final openResumePanel = topLevelResults.flag('resume');
    final debug = topLevelResults.flag('debug');

    if (debug && !jsonMode) {
      stderr.writeln(
        '[glue] v${AppConstants.version} (${BuildInfo.summary})',
      );
    }

    // Positional args form the prompt.
    final prompt =
        topLevelResults.rest.isNotEmpty ? topLevelResults.rest.join(' ') : null;

    final app = await AppShell.create(
      model: model,
      prompt: prompt,
      printMode: printMode,
      jsonMode: jsonMode,
      resumeSessionId: openResumePanel ? '' : resumeSessionId,
      startupContinue: topLevelResults.flag('continue'),
      debug: debug,
    );
    await app.run();
  }
}

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

class ConfigCommand extends Command<int> {
  ConfigCommand() {
    addSubcommand(ConfigInitCommand());
    addSubcommand(ConfigPathCommand());
    addSubcommand(ConfigValidateCommand());
  }

  @override
  String get name => 'config';

  @override
  String get description => 'Manage user configuration.';
}

class ConfigInitCommand extends Command<int> {
  ConfigInitCommand() {
    argParser.addFlag(
      'force',
      negatable: false,
      help: 'Overwrite an existing config.yaml.',
    );
  }

  @override
  String get name => 'init';

  @override
  String get description => 'Create an annotated config.yaml template.';

  @override
  Future<int> run() async {
    final ConfigInitResult result;
    try {
      result = initUserConfig(
        Environment.detect(),
        force: argResults!.flag('force'),
      );
    } on FileSystemException catch (e) {
      stderr.writeln('Failed to write config: ${e.message}');
      if (e.path != null) {
        stderr.writeln(e.path);
      }
      return 1;
    }
    if (result.status == ConfigInitStatus.exists) {
      stderr.writeln(result.message);
      return 1;
    }
    stdout.writeln(result.message);
    return 0;
  }
}

class ConfigPathCommand extends Command<int> {
  @override
  String get name => 'path';

  @override
  String get description => 'Print the resolved config.yaml path.';

  @override
  Future<int> run() async {
    stdout.writeln(userConfigPath(Environment.detect()));
    return 0;
  }
}

class ConfigValidateCommand extends Command<int> {
  @override
  String get name => 'validate';

  @override
  String get description => 'Validate config.yaml and active provider setup.';

  @override
  Future<int> run() async {
    final result = validateUserConfig(Environment.detect());
    if (result.ok) {
      stdout.writeln(result.message);
      return 0;
    }
    stderr.writeln(result.message);
    return 1;
  }
}

class DoctorCommand extends Command<int> {
  DoctorCommand() {
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Include informational findings (e.g., empty session directories).',
    );
  }

  @override
  String get name => 'doctor';

  @override
  String get description => 'Inspect Glue installation and config health.';

  @override
  Future<int> run() async {
    final report = runDoctor(Environment.detect());
    stdout.write(renderDoctorReport(
      report,
      verbose: argResults!.flag('verbose'),
    ));
    return report.hasErrors ? 1 : 0;
  }
}

enum CompletionShell {
  bash,
  zsh,
  fish,
  powershell,
  sh,
}

const _supportedShellValues = [
  'bash',
  'zsh',
  'fish',
  'powershell',
  'pwsh',
  'sh'
];

abstract class _CompletionsLeafCommand extends Command<int> {
  _CompletionsLeafCommand() {
    argParser.addOption(
      'shell',
      allowed: _supportedShellValues,
      help:
          'Shell to target (defaults to auto-detected shell). Use powershell for both pwsh and Windows PowerShell.',
    );
  }

  GlueCommandRunner get glueRunner => runner! as GlueCommandRunner;

  CompletionShell resolveShell() {
    final shellValue = argResults!.option('shell');
    final shell = shellValue == null
        ? _detectShell(Platform.environment)
        : _parseShell(shellValue);
    if (shell == null) {
      usageException(
        'Could not detect shell. Pass --shell one of: ${_supportedShellValues.join(', ')}.',
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
      _installCompletions(glueRunner, shell);
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
      _uninstallCompletions(glueRunner, shell);
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

void _installCompletions(GlueCommandRunner runner, CompletionShell shell) {
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

void _uninstallCompletions(GlueCommandRunner runner, CompletionShell shell) {
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

void _installCliCompletion(GlueCommandRunner runner, SystemShell systemShell) {
  final completionInstallation = CompletionInstallation.fromSystemShell(
    systemShell: systemShell,
    logger: runner.completionInstallationLogger,
    environmentOverride: Platform.environment,
  );
  completionInstallation.install(runner.executableName, force: true);
}

void _uninstallCliCompletion(
  GlueCommandRunner runner,
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
        home, 'Documents', 'PowerShell', 'Microsoft.PowerShell_profile.ps1');
  }
  return p.join(
      home, '.config', 'powershell', 'Microsoft.PowerShell_profile.ps1');
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
    String content, String startMarker, String endMarker) {
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
