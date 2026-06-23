/// Unified driver for the MCP OAuth login state machine.
///
/// Three surfaces run the exact same flow — the `glue mcp auth login` CLI
/// command, the `/mcp auth login` slash command, and the TUI's automatic
/// re-auth prompt. Each used to copy-paste the `McpAuthFlowRunner` states
/// listener, the `McpConfigWriter.updateAuth` write-back, and the reconnect.
///
/// [runMcpAuthLogin] owns that machinery. Call sites collapse to building
/// the runner inputs and passing a message sink (e.g. `stdout.writeln`,
/// `ctx.conversation.notify`, or `_addSystemMessage`). The write-back uses
/// the slash variant's soft-warning-on-failure behaviour everywhere: tokens
/// are already stored, so a failed config update is non-fatal.
library;

import 'dart:async';

import 'package:glue_harness/glue_harness.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue/src/commands/config_command.dart' show userConfigPath;

/// Drives an [McpAuthFlowRunner] to completion, routing progress through
/// [onMessage], persisting the resolved auth metadata to config on success,
/// and invoking [onReconnect] (when supplied) so a live pool can pick up the
/// freshly stored tokens.
///
/// Returns the runner's terminal [McpAuthFlowState]. CLI callers can `await`
/// it to derive an exit code; interactive callers can `unawaited(...)` it and
/// let [onMessage] surface every outcome.
///
/// [onMessage] receives one line per state transition. [onReconnect] is only
/// called after a successful sign-in, and only when non-null. [environment]
/// locates the user config for write-back.
Future<McpAuthFlowState> runMcpAuthLogin({
  required String serverId,
  required Uri serverUrl,
  required CredentialStore credentials,
  required Environment environment,
  required void Function(String message) onMessage,
  Uri? cachedResourceMetadataUrl,
  String? wwwAuthenticate,
  void Function(String serverId)? onReconnect,
}) {
  final runner = McpAuthFlowRunner(
    serverId: serverId,
    serverUrl: serverUrl,
    credentials: credentials,
    wwwAuthenticate: wwwAuthenticate,
    cachedResourceMetadataUrl: cachedResourceMetadataUrl,
    openBrowser: openInBrowser,
  );

  runner.states.listen((state) {
    switch (state) {
      case McpAuthFlowDiscovering():
        onMessage('Discovering OAuth metadata for "$serverId"…');
      case McpAuthFlowRegistering():
        onMessage('Registering OAuth client (DCR)…');
      case McpAuthFlowAwaitingCallback(:final authUrl):
        onMessage('Open this URL to sign in: $authUrl');
      case McpAuthFlowSuccess(
        :final resourceMetadataUrl,
        :final authorizationServer,
      ):
        onMessage('Signed in to "$serverId". Reconnecting…');
        _writeBackAuth(
          serverId: serverId,
          environment: environment,
          resourceMetadataUrl: resourceMetadataUrl,
          authorizationServer: authorizationServer,
          onMessage: onMessage,
        );
        onReconnect?.call(serverId);
      case McpAuthFlowError(:final message):
        onMessage('OAuth login failed for "$serverId": $message');
      case McpAuthFlowCancelled():
        onMessage('OAuth cancelled for "$serverId".');
    }
  });

  return runner.run();
}

/// Persists the resolved OAuth metadata to the user config. Soft-fails: the
/// tokens are already stored in the credential store, so a write-back failure
/// only means the auth state may not survive between sessions. We surface a
/// warning through [onMessage] rather than throwing.
void _writeBackAuth({
  required String serverId,
  required Environment environment,
  required Uri? resourceMetadataUrl,
  required Uri? authorizationServer,
  required void Function(String message) onMessage,
}) {
  try {
    McpConfigWriter(userConfigPath(environment)).updateAuth(
      serverId,
      auth: const McpOAuthAuth(),
      resourceMetadataUrl: resourceMetadataUrl,
      authorizationServer: authorizationServer,
    );
  } catch (_) {
    onMessage(
      'Tokens stored, but could not update config.yaml '
      '(auth state may not persist between sessions).',
    );
  }
}
