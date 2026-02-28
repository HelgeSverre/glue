import 'dart:io';

import 'command_executor.dart';
import 'docker_config.dart';
import 'docker_executor.dart';
import 'host_executor.dart';
import 'shell_config.dart';

class ExecutorFactory {
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
