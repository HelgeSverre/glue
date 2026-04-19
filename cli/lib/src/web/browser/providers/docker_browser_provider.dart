import 'dart:async';
import 'dart:io';

import 'package:glue/src/web/browser/browser_endpoint.dart';

/// Docker-based browser provider.
class DockerBrowserProvider implements BrowserEndpointProvider {
  final String image;
  final int port;
  final String sessionId;
  final bool headed;

  String? _containerId;

  DockerBrowserProvider({
    required this.image,
    required this.port,
    required this.sessionId,
    this.headed = false,
  });

  @override
  String get name => 'docker';

  @override
  bool get isConfigured => true;

  String buildWsUrl(int port) => 'ws://localhost:$port';

  /// Parse host port from Docker port output.
  ///
  /// Handles IPv4 (`0.0.0.0:1234`), IPv6 (`[::]:1234`), and
  /// localhost (`127.0.0.1:3000`) formats.
  static int? parseHostPort(String portOutput) {
    final match = RegExp(r':(\d+)$').firstMatch(portOutput);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  List<String> buildDockerRunArgs() {
    return [
      'run',
      '-d',
      '--rm',
      '--label',
      'glue.session=$sessionId',
      '--label',
      'glue.component=browser',
      '-p',
      '0:$port',
      image,
    ];
  }

  @override
  Future<BrowserEndpoint> provision() async {
    try {
      final versionResult = await Process.run(
          'docker', ['version', '--format', '{{.Server.Version}}']);
      if (versionResult.exitCode != 0) {
        throw StateError('Docker is not available');
      }
    } catch (e) {
      throw StateError('Docker is not available: $e');
    }

    final runResult = await Process.run('docker', buildDockerRunArgs());
    if (runResult.exitCode != 0) {
      throw StateError(
        'Failed to start browser container: ${runResult.stderr}',
      );
    }

    _containerId = (runResult.stdout as String).trim();

    final portResult = await Process.run('docker', [
      'port',
      _containerId!,
      '$port/tcp',
    ]);
    if (portResult.exitCode != 0) {
      await _cleanup();
      throw StateError('Failed to get container port mapping');
    }

    final portOutput = (portResult.stdout as String).trim();
    final hostPort = parseHostPort(portOutput);
    if (hostPort == null) {
      await _cleanup();
      throw StateError('Failed to parse port from: $portOutput');
    }

    await _waitForReady(hostPort);

    return BrowserEndpoint(
      cdpWsUrl: buildWsUrl(hostPort),
      backendName: name,
      headed: headed,
      onClose: _cleanup,
    );
  }

  Future<void> _waitForReady(int hostPort, {int maxAttempts = 30}) async {
    final client = HttpClient();
    try {
      for (var i = 0; i < maxAttempts; i++) {
        try {
          final response = await client
              .getUrl(Uri.parse('http://localhost:$hostPort/json/version'))
              .then((req) => req.close())
              .timeout(const Duration(seconds: 1));
          await response.drain<void>();
          if (response.statusCode == 200) return;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      throw StateError('Browser container did not become ready in time');
    } finally {
      client.close();
    }
  }

  Future<void> _cleanup() async {
    if (_containerId == null) return;
    try {
      await Process.run('docker', ['stop', '-t', '5', _containerId!]);
    } catch (_) {}
    _containerId = null;
  }

  /// Cleanup stale containers from previous sessions.
  static Future<void> cleanupStaleContainers() async {
    try {
      final result = await Process.run('docker', [
        'ps',
        '-q',
        '--filter',
        'label=glue.component=browser',
      ]);
      if (result.exitCode != 0) return;

      final ids = (result.stdout as String)
          .trim()
          .split('\n')
          .where((id) => id.isNotEmpty)
          .toList();

      for (final id in ids) {
        await Process.run('docker', ['stop', '-t', '5', id]);
      }
    } catch (_) {}
  }
}
