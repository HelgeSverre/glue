import 'dart:io';

import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/shell/docker_config.dart';
import 'package:glue/src/shell/docker_executor.dart';
import 'package:glue/src/shell/host_executor.dart';
import 'package:glue/src/shell/shell_config.dart';

class ExecutorFactory {
  /// Returns a [DockerExecutor] when Docker is enabled and available,
  /// otherwise a [HostExecutor]. Throws if Docker is required but missing.
  static Future<CommandExecutor> create({
    required ShellConfig shellConfig,
    required DockerConfig dockerConfig,
    required String cwd,
    List<MountEntry> sessionMounts = const [],
    bool? dockerAvailable,
  }) async {
    if (!dockerConfig.enabled) {
      return HostExecutor(shellConfig);
    }

    final available = dockerAvailable ?? await _checkDocker();
    if (!available) {
      if (dockerConfig.fallbackToHost) {
        return HostExecutor(shellConfig);
      }
      throw StateError('Docker is required but not available');
    }

    final allMounts = [...dockerConfig.mounts, ...sessionMounts];
    
    return DockerExecutor(
      config: dockerConfig,
      cwd: cwd,
      mounts: allMounts,
    );
  }

  static Future<bool> _checkDocker() async {
    try {
      final result = await Process.run('docker', ['--version']);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    } catch (e) {
      stderr.writeln('Unexpected error checking Docker availability: $e');
      return false;
    }
  }
}
