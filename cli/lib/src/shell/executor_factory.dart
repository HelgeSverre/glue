import 'dart:io';

import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/shell/docker_config.dart';
import 'package:glue/src/shell/docker_executor.dart';
import 'package:glue/src/shell/host_executor.dart';
import 'package:glue/src/shell/shell_config.dart';

class ExecutorFactory {
  /// Creates the appropriate [CommandExecutor] for the current config.
  ///
  /// When Docker is enabled, checks that the `docker` binary is available
  /// and returns a [DockerExecutor]. If Docker isn't installed and
  /// [DockerConfig.fallbackToHost] is true, falls back to [HostExecutor].
  ///
  /// Throws [StateError] if Docker is required (no fallback) but not found.
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
