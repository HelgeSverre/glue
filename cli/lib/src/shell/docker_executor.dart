import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/shell/docker_config.dart';

/// Runs shell commands inside a Docker container.
///
/// The project's working directory is bind-mounted at `/workspace`, and any
/// additional [MountEntry]s from config or the session are added as volumes.
/// Container cleanup (CID file removal, `docker stop`) is handled
/// automatically on timeout or kill.
///
/// `/workspace` is the universal convention shared with future cloud runtimes
/// (E2B, Daytona, Sprites, VibeKit-style providers). See
/// `docs/plans/2026-04-19-runtime-boundary-plan.md`.
class DockerExecutor implements CommandExecutor {
  final DockerConfig config;

  /// The host directory to use as the container's working directory.
  ///
  /// Bind-mounted as `/workspace` inside the container — this is where all
  /// commands execute by default.
  final String cwd;

  final List<MountEntry> mounts;

  DockerExecutor({
    required this.config,
    required this.cwd,
    required this.mounts,
  });

  /// Builds the full `docker run` argument list for [command].
  ///
  /// [cidfilePath] is passed to `--cidfile` so Docker writes the container ID
  /// to disk — this lets us `docker stop` the container on timeout or kill
  /// without needing to parse `docker ps`.
  List<String> buildDockerArgs(String command, String cidfilePath) {
    final args = <String>[
      'run',
      '--rm',
      '-i',
      '--cidfile',
      cidfilePath,
      '-w',
      '/workspace',
      '-v',
      '$cwd:/workspace:rw',
    ];

    for (final mount in MountEntry.dedup(mounts)) {
      args.addAll(['-v', mount.toDockerArg()]);
    }

    args.addAll([
      config.image,
      config.shell,
      '-c',
      command,
    ]);

    return args;
  }

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    final cidfile = _tempCidfile();
    try {
      final args = buildDockerArgs(command, cidfile.path);
      final process = await Process.start('docker', args);

      final stdoutFuture =
          process.stdout.transform(const SystemEncoding().decoder).join();
      final stderrFuture =
          process.stderr.transform(const SystemEncoding().decoder).join();

      final int exitCode;
      if (timeout == null) {
        exitCode = await process.exitCode;
      } else {
        exitCode = await process.exitCode.timeout(timeout, onTimeout: () async {
          await _killContainer(cidfile);
          process.kill();
          return -1;
        });
      }

      return CaptureResult(
        exitCode: exitCode,
        stdout: await stdoutFuture,
        stderr: await stderrFuture,
      );
    } finally {
      _cleanupCidfile(cidfile);
    }
  }

  @override
  Future<RunningCommand> startStreaming(String command) async {
    final cidfile = _tempCidfile();
    final args = buildDockerArgs(command, cidfile.path);
    final process = await Process.start('docker', args);
    return DockerRunningCommand(process, cidfile);
  }

  File _tempCidfile() {
    final dir = Directory.systemTemp;
    final name = 'glue-cid-${DateTime.now().microsecondsSinceEpoch}';
    return File(p.join(dir.path, name));
  }

  Future<void> _killContainer(File cidfile) async {
    try {
      final cid = await _readCidWithRetry(cidfile);
      if (cid != null && cid.isNotEmpty) {
        await Process.run('docker', ['stop', '-t', '5', cid]);
      }
    } catch (_) {}
  }

  void _cleanupCidfile(File cidfile) {
    try {
      if (cidfile.existsSync()) cidfile.deleteSync();
    } catch (_) {}
  }
}

Future<String?> _readCidWithRetry(File cidfile) async {
  const attempts = 10;
  const delay = Duration(milliseconds: 50);

  for (var i = 0; i < attempts; i++) {
    try {
      if (cidfile.existsSync()) {
        final cid = (await cidfile.readAsString()).trim();
        if (cid.isNotEmpty) return cid;
      }
    } catch (_) {}
    await Future.delayed(delay);
  }
  return null;
}

/// A [RunningCommand] backed by a Docker container.
///
/// Extends the base kill behavior to `docker stop` the container before
/// sending SIGTERM, and cleans up the CID temp file on process exit.
class DockerRunningCommand extends RunningCommand {
  final File _cidfile;

  DockerRunningCommand(super.process, this._cidfile) {
    process.exitCode.whenComplete(() {
      try {
        if (_cidfile.existsSync()) _cidfile.deleteSync();
      } catch (_) {}
    });
  }

  @override
  Future<void> kill() async {
    try {
      final cid = await _readCidWithRetry(_cidfile);
      if (cid != null && cid.isNotEmpty) {
        await Process.run('docker', ['stop', '-t', '5', cid]);
      }
    } catch (_) {}
    await super.kill();
    try {
      if (_cidfile.existsSync()) _cidfile.deleteSync();
    } catch (_) {}
  }
}
