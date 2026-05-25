import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glue/src/commands/setup_command_format.dart';

class SetupCheckResult {
  const SetupCheckResult({required this.exitCode, required this.stdout});

  final int exitCode;
  final String stdout;
}

Future<SetupCheckResult> runGlueSetupCheckForTest({
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  final home = env['GLUE_HOME'] ?? '${env['HOME'] ?? '~'}/.glue';
  return SetupCheckResult(
    exitCode: 0,
    stdout: formatSetupCheck(home: home, ansiEnabled: false),
  );
}

class SetupCommand extends Command<int> {
  SetupCommand() {
    argParser.addFlag(
      'check',
      defaultsTo: true,
      negatable: false,
      help: 'Print setup guidance for terminal-based ACP registry auth.',
    );
  }

  @override
  String get name => 'setup';

  @override
  String get description => 'Show terminal setup steps for Glue.';

  @override
  Future<int> run() async {
    final result = await runGlueSetupCheckForTest();
    stdout.writeln(result.stdout);
    return result.exitCode;
  }
}
