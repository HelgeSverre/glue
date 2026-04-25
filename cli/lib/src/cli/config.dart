import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glue/src/commands/config_command.dart';
import 'package:glue/src/core/environment.dart';

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
