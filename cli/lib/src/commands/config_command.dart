import 'dart:io';

import 'package:glue/src/config/config_template.dart';
import 'package:glue/src/core/environment.dart';

enum ConfigInitStatus {
  created,
  overwritten,
  exists,
}

class ConfigInitResult {
  const ConfigInitResult({
    required this.status,
    required this.path,
  });

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

ConfigInitResult initUserConfig(
  Environment environment, {
  bool force = false,
}) {
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
