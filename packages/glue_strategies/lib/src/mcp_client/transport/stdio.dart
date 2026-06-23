/// Subprocess-backed JSON-RPC transport for MCP stdio servers.
///
/// Wraps `Process.start` with:
///   • env hygiene — scrub the parent environment to a small allowlist
///     so user secrets (OPENAI_API_KEY, AWS creds, .netrc) don't leak
///     into every MCP server they install. Explicitly listed `env:`
///     entries from the server config are added back.
///   • clean shutdown — `close()` sends SIGTERM, waits 2s, then SIGKILL.
///   • exposes the underlying [JsonRpcTransport] surface for [McpClient].
///
/// Orphan-prevention (PR_SET_PDEATHSIG on Linux, kqueue watchdog on
/// macOS) is a deferred follow-up — for now we rely on the SIGTERM
/// path during normal Glue shutdown.
library;

import 'dart:async';
import 'dart:io';

import 'package:glue_server/glue_server.dart';
import 'package:glue_strategies/src/fs/path_utils.dart';

/// Subset of the parent env that's always forwarded to stdio servers.
/// Other keys must be opted in via the server config's `env:` block.
const _alwaysForwardedEnvKeys = {
  'PATH',
  'HOME',
  'LANG',
  'LC_ALL',
  'LC_CTYPE',
  'TERM',
  'USER',
  'SHELL',
  // Windows / cross-platform conveniences
  'USERPROFILE',
  'APPDATA',
  'LOCALAPPDATA',
  'TMP',
  'TEMP',
};

class McpStdioTransportSpawnError implements Exception {
  const McpStdioTransportSpawnError(this.command, this.cause);
  final String command;
  final Object cause;
  @override
  String toString() => 'McpStdioTransportSpawnError($command): $cause';
}

class McpStdioTransport implements JsonRpcTransport {
  McpStdioTransport._(this._process, this._inner);

  /// Spawn a subprocess. The child receives only [_alwaysForwardedEnvKeys]
  /// plus any keys in [extraEnv] (which is the server config's `env:`
  /// block resolved through env-var interpolation).
  ///
  /// Pass [inheritFullEnv] = true to opt out of scrubbing (matches
  /// Claude Desktop's behaviour) — should be rare and explicit.
  static Future<McpStdioTransport> spawn({
    required String command,
    List<String> args = const [],
    Map<String, String> extraEnv = const {},
    String? workingDirectory,
    bool inheritFullEnv = false,
  }) async {
    final env = inheritFullEnv
        ? null
        : buildMcpStdioEnv(Platform.environment, extraEnv);
    try {
      final process = await Process.start(
        command,
        args,
        environment: env,
        // `Process.start` does not expand `~`; do it here so a server's
        // `working_directory: ~/foo` (config or `mcp add --cwd`) resolves.
        workingDirectory: workingDirectory == null
            ? null
            : expandUserPath(workingDirectory),
        // includeParentEnvironment must be false when we pass a scrubbed
        // map — otherwise Dart will merge the parent env back in.
        includeParentEnvironment: inheritFullEnv,
        mode: ProcessStartMode.normal,
      );
      final inner = LineDelimitedTransport(
        input: process.stdout,
        output: process.stdin,
      );
      // Drain stderr to a sink so the OS pipe doesn't fill and block
      // the child. The server's structured log lives in MCP
      // notifications; stderr is unstructured/diagnostic only.
      process.stderr.drain<void>();
      return McpStdioTransport._(process, inner);
    } catch (e) {
      throw McpStdioTransportSpawnError(command, e);
    }
  }

  final Process _process;
  final LineDelimitedTransport _inner;
  bool _closed = false;

  @override
  Stream<JsonRpcMessage> get incoming => _inner.incoming;

  @override
  void send(JsonRpcMessage message) => _inner.send(message);

  /// The OS PID of the spawned server. Useful for tests and diagnostics.
  int get pid => _process.pid;

  /// Resolves to the child's exit code. Lets callers detect "the server
  /// died on its own" vs. "we shut it down".
  Future<int> get exitCode => _process.exitCode;

  /// SIGTERM the child; if it hasn't exited after 2s, SIGKILL.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _process.kill();
    } catch (_) {
      // Already exited.
    }
    try {
      await _process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      try {
        _process.kill(ProcessSignal.sigkill);
      } catch (_) {
        // Already exited.
      }
    }
    await _inner.close();
  }
}

/// Builds the env the child subprocess sees: the always-forwarded
/// allowlist from [parent] plus any [extra] keys from the server config.
/// `extra` wins on conflict (the config is the authority).
///
/// Public for testing. Production code uses it via [McpStdioTransport.spawn].
Map<String, String> buildMcpStdioEnv(
  Map<String, String> parent,
  Map<String, String> extra,
) {
  final out = <String, String>{};
  for (final key in _alwaysForwardedEnvKeys) {
    final v = parent[key];
    if (v != null) out[key] = v;
  }
  out.addAll(extra);
  return out;
}
