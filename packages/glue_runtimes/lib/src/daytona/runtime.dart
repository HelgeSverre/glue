import 'package:http/http.dart' as http;

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue_runtimes/src/daytona/bootstrap.dart';
import 'package:glue_runtimes/src/daytona/client.dart';
import 'package:glue_runtimes/src/daytona/config.dart';
import 'package:glue_runtimes/src/daytona/executor.dart';
import 'package:glue_runtimes/src/daytona/workspace.dart';

/// The top-level Daytona runtime — owns one sandbox for the lifetime
/// of a Glue session.
class DaytonaRuntime implements RuntimeSession {
  final DaytonaClient _client;
  final DaytonaSandbox sandbox;

  @override
  final CommandExecutor executor;

  @override
  final Workspace workspace;

  /// Commit SHA the sandbox was bootstrapped from. `null` when the
  /// sandbox was resumed and already had `/workspace/.git`.
  @override
  final String? bootstrapSha;

  @override
  final bool resumed;

  DaytonaRuntime._({
    required DaytonaClient client,
    required this.sandbox,
    required this.executor,
    required this.workspace,
    required this.bootstrapSha,
    required this.resumed,
  }) : _client = client;

  @override
  String get id => 'daytona';

  @override
  String get sandboxId => sandbox.id;

  /// Spins up a new Daytona sandbox and returns a fully-wired runtime.
  ///
  /// On failure (sandbox-create error, bootstrap failure) any
  /// partially-created sandbox is stopped before rethrowing, so we
  /// don't leak resources.
  static Future<DaytonaRuntime> start({
    required DaytonaConfig config,
    required String hostCwd,
    String runtimeCwd = '/workspace',
    http.Client? httpClient,
  }) async {
    if (config.apiKey.isEmpty) {
      throw StateError(
        'Daytona runtime requires an API key. Set DAYTONA_API_KEY or '
        'put daytona.api_key in your config.',
      );
    }

    final client = DaytonaClient(config: config, httpClient: httpClient);
    DaytonaSandbox? sandbox;
    try {
      sandbox = await client.createSandbox();

      final bootstrap = DaytonaBootstrap(client: client, sandbox: sandbox);
      final bootstrapResult = await bootstrap.bootstrap(
        hostCwd: hostCwd,
        runtimeCwd: runtimeCwd,
      );

      final mapping = WorkspaceMapping(
        hostCwd: hostCwd,
        runtimeCwd: runtimeCwd,
      );
      final executor = DaytonaExecutor(client: client, sandbox: sandbox);
      final workspace = TransportWorkspace(
        fs: DaytonaFsTransport(client: client, sandbox: sandbox),
        mapping: mapping,
      );

      return DaytonaRuntime._(
        client: client,
        sandbox: sandbox,
        executor: executor,
        workspace: workspace,
        bootstrapSha: bootstrapResult.bootstrapSha,
        resumed: bootstrapResult.resumed,
      );
    } catch (e) {
      // Clean up any half-created sandbox so we don't leak a paid
      // resource on the user's account.
      if (sandbox != null) {
        try {
          await client.stopSandbox(sandbox.id);
        } catch (_) {}
      }
      client.close();
      rethrow;
    }
  }

  /// Stops the sandbox and releases the HTTP client.
  @override
  Future<void> close() async {
    try {
      await _client.stopSandbox(sandbox.id);
    } finally {
      _client.close();
    }
  }
}
