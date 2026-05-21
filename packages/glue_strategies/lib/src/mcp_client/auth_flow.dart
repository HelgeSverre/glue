/// `McpAuthFlowRunner` — runs an MCP OAuth flow from discovery through
/// token persistence, emitting state changes for UI consumers.
///
/// Used by:
///   • `glue mcp auth login <id>` (CLI surface — plain stdout)
///   • `/mcp auth login <id>` (slash command — status panel)
///   • Auto-triggered flow from `McpPoolServerAuthRequiredEvent`
///
/// The runner is platform-neutral. UI surfaces subscribe to [states]
/// and react to each [McpAuthFlowState] variant — including printing
/// the URL, opening a browser, and dismissing on success.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import 'package:glue_strategies/src/credentials/credential_store.dart';
import 'package:glue_strategies/src/mcp_client/oauth.dart';

sealed class McpAuthFlowState {
  const McpAuthFlowState();
}

class McpAuthFlowDiscovering extends McpAuthFlowState {
  const McpAuthFlowDiscovering();
}

class McpAuthFlowRegistering extends McpAuthFlowState {
  const McpAuthFlowRegistering();
}

class McpAuthFlowAwaitingCallback extends McpAuthFlowState {
  const McpAuthFlowAwaitingCallback({required this.authUrl});
  final Uri authUrl;
}

class McpAuthFlowSuccess extends McpAuthFlowState {
  const McpAuthFlowSuccess({
    required this.resourceMetadataUrl,
    required this.authorizationServer,
  });
  final Uri? resourceMetadataUrl;
  final Uri? authorizationServer;
}

class McpAuthFlowError extends McpAuthFlowState {
  const McpAuthFlowError(this.message);
  final String message;
}

class McpAuthFlowCancelled extends McpAuthFlowState {
  const McpAuthFlowCancelled();
}

/// Pluggable Authorization-Code+PKCE flow. Default is the real
/// `runOAuthAuthorizationCodeFlow`. Tests inject a stub that emits the
/// auth URL via [onAuthUrl] and returns synthesized tokens.
typedef OAuthCodeFlow =
    Future<OAuthTokens> Function({
      required OAuthEndpoints endpoints,
      required OAuthClient client,
      required List<String> scopes,
      required void Function(String authUrl) onAuthUrl,
      http.Client? httpClient,
    });

class McpAuthFlowRunner {
  McpAuthFlowRunner({
    required this.serverId,
    required this.serverUrl,
    required this.credentials,
    this.wwwAuthenticate,
    this.cachedResourceMetadataUrl,
    this.cachedAuthorizationServer,
    http.Client? httpClient,
    Future<void> Function(String url)? openBrowser,
    OAuthCodeFlow? codeFlow,
    // ignore: prefer_initializing_formals
  }) : _httpClient = httpClient,
       _openBrowser = openBrowser ?? _noopOpen,
       _codeFlow = codeFlow ?? _defaultCodeFlow;

  final String serverId;
  final Uri serverUrl;
  final CredentialStore credentials;
  final String? wwwAuthenticate;
  final Uri? cachedResourceMetadataUrl;
  final Uri? cachedAuthorizationServer;
  final http.Client? _httpClient;
  final Future<void> Function(String url) _openBrowser;
  final OAuthCodeFlow _codeFlow;

  final _states = StreamController<McpAuthFlowState>.broadcast();
  bool _cancelled = false;

  Stream<McpAuthFlowState> get states => _states.stream;

  void cancel() {
    _cancelled = true;
  }

  /// Runs the flow end-to-end. Resolves with the terminal state.
  Future<McpAuthFlowState> run() async {
    try {
      _emit(const McpAuthFlowDiscovering());
      final discovery = await discoverMcpAuth(
        serverUrl: serverUrl,
        wwwAuthenticate: wwwAuthenticate,
        cachedResourceMetadataUrl: cachedResourceMetadataUrl,
        httpClient: _httpClient,
      );
      if (_cancelled) return await _terminal(const McpAuthFlowCancelled());

      OAuthClient client;
      final existingClientId = credentials.getField(
        'mcp:$serverId',
        McpOAuthFields.clientId,
      );
      if (existingClientId != null) {
        client = OAuthClient(
          clientId: existingClientId,
          clientSecret: credentials.getField(
            'mcp:$serverId',
            McpOAuthFields.clientSecret,
          ),
        );
      } else if (discovery.endpoints.registrationEndpoint != null) {
        _emit(const McpAuthFlowRegistering());
        client = await registerOAuthClient(
          registrationEndpoint: discovery.endpoints.registrationEndpoint!,
          redirectUri: Uri.parse('http://127.0.0.1/callback'),
          clientName: 'glue',
          httpClient: _httpClient,
        );
      } else {
        return await _terminal(
          const McpAuthFlowError(
            'No registration_endpoint advertised and no client_id stored.',
          ),
        );
      }
      if (_cancelled) return await _terminal(const McpAuthFlowCancelled());

      final tokens = await _codeFlow(
        endpoints: discovery.endpoints,
        client: client,
        scopes: discovery.scopes,
        onAuthUrl: (url) {
          _emit(McpAuthFlowAwaitingCallback(authUrl: Uri.parse(url)));
          unawaited(_openBrowser(url));
        },
        httpClient: _httpClient,
      );
      if (_cancelled) return await _terminal(const McpAuthFlowCancelled());

      storeMcpOAuthTokens(
        serverId: serverId,
        client: client,
        tokens: tokens,
        credentials: credentials,
      );
      return await _terminal(
        McpAuthFlowSuccess(
          resourceMetadataUrl: discovery.resourceMetadataUrl,
          authorizationServer: discovery.authorizationServer,
        ),
      );
    } catch (e) {
      return _terminal(McpAuthFlowError(e.toString()));
    }
  }

  void _emit(McpAuthFlowState state) {
    if (_states.isClosed) return;
    _states.add(state);
  }

  Future<McpAuthFlowState> _terminal(McpAuthFlowState state) async {
    _emit(state);
    // Let listeners drain queued microtasks before we resolve.
    await _states.close();
    return state;
  }
}

Future<void> _noopOpen(String url) async {}

Future<OAuthTokens> _defaultCodeFlow({
  required OAuthEndpoints endpoints,
  required OAuthClient client,
  required List<String> scopes,
  required void Function(String authUrl) onAuthUrl,
  http.Client? httpClient,
}) {
  return runOAuthAuthorizationCodeFlow(
    endpoints: endpoints,
    client: client,
    scopes: scopes,
    onAuthUrl: onAuthUrl,
    httpClient: httpClient,
  );
}
