import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glue_harness/glue_harness.dart';

enum ConfigInitStatus { created, overwritten, exists }

class ConfigInitResult {
  const ConfigInitResult({required this.status, required this.path});

  final ConfigInitStatus status;
  final String path;

  bool get wroteFile =>
      status == ConfigInitStatus.created ||
      status == ConfigInitStatus.overwritten;

  String get message => switch (status) {
    ConfigInitStatus.created => 'Created config template: $path',
    ConfigInitStatus.overwritten => 'Overwrote config template: $path',
    ConfigInitStatus.exists =>
      'Config already exists: $path\nUse --force to overwrite it.',
  };
}

ConfigInitResult initUserConfig(Environment environment, {bool force = false}) {
  final path = environment.configYamlPath;
  final file = File(path);
  final existed = file.existsSync();
  if (existed && !force) {
    return ConfigInitResult(status: ConfigInitStatus.exists, path: path);
  }
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(buildConfigTemplate());
  return ConfigInitResult(
    status: existed ? ConfigInitStatus.overwritten : ConfigInitStatus.created,
    path: path,
  );
}

class ConfigValidationResult {
  const ConfigValidationResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

String userConfigPath(Environment environment) => environment.configYamlPath;

ConfigValidationResult validateUserConfig(Environment environment) {
  try {
    final config = GlueConfig.load(environment: environment);
    config.validate();
    return ConfigValidationResult(
      ok: true,
      message: 'Config OK: ${environment.configYamlPath}',
    );
  } on ConfigError catch (e) {
    return ConfigValidationResult(ok: false, message: e.message);
  } on FormatException catch (e) {
    return ConfigValidationResult(ok: false, message: e.message);
  } on FileSystemException catch (e) {
    return ConfigValidationResult(ok: false, message: e.message);
  } on Object catch (e) {
    return ConfigValidationResult(ok: false, message: e.toString());
  }
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
