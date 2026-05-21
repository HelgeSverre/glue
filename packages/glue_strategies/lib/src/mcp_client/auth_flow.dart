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
import 'dart:io';

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
      HttpServer? preboundServer,
      Uri? preboundRedirectUri,
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
    HttpServer? loopback;
    try {
      _emit(const McpAuthFlowDiscovering());
      final discovery = await discoverMcpAuth(
        serverUrl: serverUrl,
        wwwAuthenticate: wwwAuthenticate,
        cachedResourceMetadataUrl: cachedResourceMetadataUrl,
        httpClient: _httpClient,
      );
      if (_cancelled) return await _terminal(const McpAuthFlowCancelled());

      // Bind the loopback server BEFORE DCR so we can register the exact
      // redirect_uri the flow will use. Many auth servers (incl.
      // SmartBear) require an exact match between the registered URI and
      // the one sent at authorize/token time, even though RFC 8252 §7.3
      // says they shouldn't.
      loopback = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirectUri = Uri.parse(
        'http://127.0.0.1:${loopback.port}/callback',
      );

      OAuthClient client;
      final existingClientId = credentials.getField(
        'mcp:$serverId',
        McpOAuthFields.clientId,
      );
      if (discovery.endpoints.registrationEndpoint != null) {
        // Re-register every time DCR is available. The bound port
        // changes between sessions, so a cached client_id from a
        // different port would fail validation on strict servers. DCR
        // is cheap.
        _emit(const McpAuthFlowRegistering());
        client = await registerOAuthClient(
          registrationEndpoint: discovery.endpoints.registrationEndpoint!,
          redirectUri: redirectUri,
          clientName: 'glue',
          httpClient: _httpClient,
        );
      } else if (existingClientId != null) {
        // No DCR endpoint — must use a pre-registered client. Hope the
        // operator registered http://127.0.0.1:* or the exact port we
        // got.
        client = OAuthClient(
          clientId: existingClientId,
          clientSecret: credentials.getField(
            'mcp:$serverId',
            McpOAuthFields.clientSecret,
          ),
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
        preboundServer: loopback,
        preboundRedirectUri: redirectUri,
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
    } finally {
      // The code flow normally closes the server, but if we errored
      // before entering it (e.g. DCR failure), close it ourselves.
      // Double-close on an already-closed HttpServer is safe but we
      // wrap defensively.
      if (loopback != null) {
        try {
          await loopback.close(force: true);
        } catch (_) {}
      }
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
  HttpServer? preboundServer,
  Uri? preboundRedirectUri,
}) {
  return runOAuthAuthorizationCodeFlow(
    endpoints: endpoints,
    client: client,
    scopes: scopes,
    onAuthUrl: onAuthUrl,
    httpClient: httpClient,
    preboundServer: preboundServer,
    preboundRedirectUri: preboundRedirectUri,
  );
}
