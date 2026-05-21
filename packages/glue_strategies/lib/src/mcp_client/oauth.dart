/// OAuth 2.1 Authorization Code Flow + PKCE + Dynamic Client
/// Registration for MCP servers.
///
/// Used by `glue mcp auth login <server>` (and `/mcp auth login`).
///
/// Flow:
///   1. Discover the authorization-server metadata at
///      `<base>/.well-known/oauth-authorization-server` (RFC 8414).
///   2. (Optional) Dynamically register a client (RFC 7591) and persist
///      the issued `client_id` so we don't re-register on subsequent
///      logins for the same server.
///   3. Open the user's browser to `authorization_endpoint?...` with a
///      PKCE challenge + a fresh `state` parameter.
///   4. Bind a one-shot loopback HTTP server on `127.0.0.1:0` that the
///      browser will redirect to. Capture `code` + verify `state`.
///   5. Exchange the code at `token_endpoint` for an access token (+
///      optional refresh token).
///   6. Persist the tokens to [CredentialStore] under
///      `mcp:<server-id>` with the field names declared in
///      [McpOAuthFields].
///
/// No secrets are logged. The browser URL itself is shown to the user
/// (it contains the state + challenge but no token).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'package:glue_strategies/src/credentials/credential_store.dart';

// ─── Discovery ─────────────────────────────────────────────────────────────

class OAuthEndpoints {
  const OAuthEndpoints({
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    this.registrationEndpoint,
    this.scopesSupported = const [],
  });

  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final Uri? registrationEndpoint;
  final List<String> scopesSupported;

  factory OAuthEndpoints.fromMetadata(Map<String, dynamic> json) {
    final auth = json['authorization_endpoint'] as String?;
    final token = json['token_endpoint'] as String?;
    if (auth == null || token == null) {
      throw const FormatException(
        'authorization_endpoint and token_endpoint are required',
      );
    }
    final reg = json['registration_endpoint'] as String?;
    final scopes =
        (json['scopes_supported'] as List?)?.cast<String>().toList() ??
        const <String>[];
    return OAuthEndpoints(
      authorizationEndpoint: Uri.parse(auth),
      tokenEndpoint: Uri.parse(token),
      registrationEndpoint: reg != null ? Uri.parse(reg) : null,
      scopesSupported: scopes,
    );
  }
}

/// Discovers the OAuth metadata for an MCP server. Tries the canonical
/// RFC 8414 path (`/.well-known/oauth-authorization-server`); falls back
/// to the OIDC discovery path (`/.well-known/openid-configuration`).
Future<OAuthEndpoints> discoverOAuthEndpoints(
  Uri serverBaseUrl, {
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  final ownsClient = httpClient == null;
  try {
    final paths = [
      '/.well-known/oauth-authorization-server',
      '/.well-known/openid-configuration',
    ];
    for (final path in paths) {
      final url = serverBaseUrl.replace(path: path);
      final res = await client.get(
        url,
        headers: const {'Accept': 'application/json'},
      );
      if (res.statusCode != 200) continue;
      try {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        return OAuthEndpoints.fromMetadata(json);
      } catch (_) {
        continue;
      }
    }
    throw OAuthDiscoveryException(
      'no oauth metadata at ${serverBaseUrl.replace(path: "/.well-known/oauth-authorization-server")} '
      'or the OIDC fallback',
    );
  } finally {
    if (ownsClient) client.close();
  }
}

class OAuthDiscoveryException implements Exception {
  const OAuthDiscoveryException(this.message);
  final String message;
  @override
  String toString() => 'OAuthDiscoveryException: $message';
}

// ─── Dynamic Client Registration (RFC 7591) ────────────────────────────────

class OAuthClient {
  const OAuthClient({required this.clientId, this.clientSecret});
  final String clientId;
  final String? clientSecret;
}

Future<OAuthClient> registerOAuthClient({
  required Uri registrationEndpoint,
  required Uri redirectUri,
  required String clientName,
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  final ownsClient = httpClient == null;
  try {
    final res = await client.post(
      registrationEndpoint,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'redirect_uris': [redirectUri.toString()],
        'client_name': clientName,
        'token_endpoint_auth_method': 'none', // public client
        'grant_types': ['authorization_code', 'refresh_token'],
        'response_types': ['code'],
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw OAuthRegistrationException(
        'DCR failed (${res.statusCode}): ${res.body}',
      );
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final clientId = json['client_id'] as String?;
    if (clientId == null) {
      throw const OAuthRegistrationException('DCR response missing client_id');
    }
    return OAuthClient(
      clientId: clientId,
      clientSecret: json['client_secret'] as String?,
    );
  } finally {
    if (ownsClient) client.close();
  }
}

class OAuthRegistrationException implements Exception {
  const OAuthRegistrationException(this.message);
  final String message;
  @override
  String toString() => 'OAuthRegistrationException: $message';
}

// ─── Tokens ────────────────────────────────────────────────────────────────

class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.scope,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final String? scope;
}

/// Runs the full Authorization Code + PKCE flow. Returns the tokens.
///
/// [onAuthUrl] is invoked once with the URL the user should open in
/// their browser. The CLI runs `xdg-open` / `open` etc.; the slash
/// command surfaces it as a system message.
///
/// [redirectPort] = 0 binds a random port.
Future<OAuthTokens> runOAuthAuthorizationCodeFlow({
  required OAuthEndpoints endpoints,
  required OAuthClient client,
  List<String> scopes = const [],
  Duration timeout = const Duration(minutes: 5),
  int redirectPort = 0,
  required void Function(String authUrl) onAuthUrl,
  http.Client? httpClient,
}) async {
  final pkce = _generatePkce();
  final state = _generateState();

  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    redirectPort,
  );
  final redirectUri = Uri.parse('http://127.0.0.1:${server.port}/callback');

  // Build authorization URL.
  final authUri = endpoints.authorizationEndpoint.replace(
    queryParameters: {
      'response_type': 'code',
      'client_id': client.clientId,
      'redirect_uri': redirectUri.toString(),
      'state': state,
      'code_challenge': pkce.challenge,
      'code_challenge_method': 'S256',
      if (scopes.isNotEmpty) 'scope': scopes.join(' '),
    },
  );

  onAuthUrl(authUri.toString());

  String? code;
  String? error;
  final codeCompleter = Completer<void>();

  late StreamSubscription<HttpRequest> sub;
  sub = server.listen((req) async {
    final params = req.uri.queryParameters;
    if (req.uri.path != '/callback') {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    final receivedState = params['state'];
    final receivedCode = params['code'];
    final receivedError = params['error'];

    if (receivedError != null) {
      error = receivedError;
    } else if (receivedState != state) {
      error = 'state_mismatch';
    } else if (receivedCode == null) {
      error = 'missing_code';
    } else {
      code = receivedCode;
    }

    req.response.headers.contentType = ContentType.html;
    final ok = code != null;
    final heading = ok ? 'Authorization complete' : 'Authorization failed';
    final body = ok
        ? 'You can close this window and return to Glue.'
        : 'Reason: ${error ?? "unknown"}';
    req.response.write(
      '<!doctype html><html><body><h2>$heading</h2><p>$body</p></body></html>',
    );
    await req.response.close();
    if (!codeCompleter.isCompleted) codeCompleter.complete();
  });

  try {
    await codeCompleter.future.timeout(timeout);
  } on TimeoutException {
    error = 'timeout';
  } finally {
    await sub.cancel();
    await server.close(force: true);
  }

  if (error != null || code == null) {
    throw OAuthFlowException('authorization failed: ${error ?? 'unknown'}');
  }

  // Exchange code for tokens.
  final http_ = httpClient ?? http.Client();
  final ownsClient = httpClient == null;
  try {
    final res = await http_.post(
      endpoints.tokenEndpoint,
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: {
        'grant_type': 'authorization_code',
        'code': code!,
        'redirect_uri': redirectUri.toString(),
        'client_id': client.clientId,
        'code_verifier': pkce.verifier,
        if (client.clientSecret != null) 'client_secret': client.clientSecret!,
      },
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw OAuthFlowException(
        'token exchange failed (${res.statusCode}): ${res.body}',
      );
    }
    return _parseTokenResponse(res.body);
  } finally {
    if (ownsClient) http_.close();
  }
}

/// Refresh-token grant. Returns new tokens; the refresh token may rotate.
Future<OAuthTokens> refreshOAuthTokens({
  required OAuthEndpoints endpoints,
  required OAuthClient client,
  required String refreshToken,
  http.Client? httpClient,
}) async {
  final http_ = httpClient ?? http.Client();
  final ownsClient = httpClient == null;
  try {
    final res = await http_.post(
      endpoints.tokenEndpoint,
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': client.clientId,
        if (client.clientSecret != null) 'client_secret': client.clientSecret!,
      },
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw OAuthFlowException(
        'token refresh failed (${res.statusCode}): ${res.body}',
      );
    }
    return _parseTokenResponse(res.body);
  } finally {
    if (ownsClient) http_.close();
  }
}

OAuthTokens _parseTokenResponse(String body) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  final accessToken = json['access_token'] as String?;
  if (accessToken == null) {
    throw const OAuthFlowException('token response missing access_token');
  }
  final expiresIn = json['expires_in'];
  DateTime? expiresAt;
  if (expiresIn is int) {
    expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
  }
  return OAuthTokens(
    accessToken: accessToken,
    refreshToken: json['refresh_token'] as String?,
    expiresAt: expiresAt,
    scope: json['scope'] as String?,
  );
}

class OAuthFlowException implements Exception {
  const OAuthFlowException(this.message);
  final String message;
  @override
  String toString() => 'OAuthFlowException: $message';
}

// ─── PKCE + state helpers ──────────────────────────────────────────────────

class _Pkce {
  const _Pkce(this.verifier, this.challenge);
  final String verifier;
  final String challenge;
}

_Pkce _generatePkce() {
  final rng = Random.secure();
  // 32 random bytes → 43 chars after base64url no-pad.
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  final verifier = base64UrlEncode(bytes).replaceAll('=', '');
  final challenge = base64UrlEncode(
    sha256.convert(utf8.encode(verifier)).bytes,
  ).replaceAll('=', '');
  return _Pkce(verifier, challenge);
}

String _generateState() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

// ─── CredentialStore conventions ───────────────────────────────────────────

/// Field names used under `CredentialStore`'s `mcp:<server-id>` namespace
/// for OAuth-style auth. Bearer-token-only servers use the parallel
/// `bearer` field; the two flows are orthogonal.
abstract final class McpOAuthFields {
  static const String accessToken = 'oauth_access';
  static const String refreshToken = 'oauth_refresh';
  static const String expiresAtIso = 'oauth_expires_at';
  static const String clientId = 'oauth_client_id';
  static const String clientSecret = 'oauth_client_secret';
  static const String scope = 'oauth_scope';
}

/// Persists [tokens] + [client] into the credential store under
/// `mcp:<serverId>`. Idempotent — re-running the login flow overwrites.
void storeMcpOAuthTokens({
  required String serverId,
  required OAuthClient client,
  required OAuthTokens tokens,
  required CredentialStore credentials,
}) {
  final providerId = 'mcp:$serverId';
  final existing = credentials.getFields(providerId);
  final fields = <String, String>{
    ...existing,
    McpOAuthFields.accessToken: tokens.accessToken,
    if (tokens.refreshToken != null)
      McpOAuthFields.refreshToken: tokens.refreshToken!,
    if (tokens.expiresAt != null)
      McpOAuthFields.expiresAtIso: tokens.expiresAt!.toIso8601String(),
    if (tokens.scope != null) McpOAuthFields.scope: tokens.scope!,
    McpOAuthFields.clientId: client.clientId,
    if (client.clientSecret != null)
      McpOAuthFields.clientSecret: client.clientSecret!,
  };
  credentials.setFields(providerId, fields);
}

/// Clears all OAuth fields for [serverId] from the credential store.
/// Leaves the bearer field (if any) intact.
void clearMcpOAuthTokens({
  required String serverId,
  required CredentialStore credentials,
}) {
  final providerId = 'mcp:$serverId';
  final existing = credentials.getFields(providerId);
  final keys = {
    McpOAuthFields.accessToken,
    McpOAuthFields.refreshToken,
    McpOAuthFields.expiresAtIso,
    McpOAuthFields.scope,
    McpOAuthFields.clientId,
    McpOAuthFields.clientSecret,
  };
  final next = <String, String>{
    for (final e in existing.entries)
      if (!keys.contains(e.key)) e.key: e.value,
  };
  credentials.setFields(providerId, next);
}

/// Reads the current OAuth access token for [serverId]. Returns `null`
/// when nothing is stored. Does not refresh — callers handle expiry
/// elsewhere.
String? readMcpOAuthAccessToken({
  required String serverId,
  required CredentialStore credentials,
}) {
  return credentials.getField('mcp:$serverId', McpOAuthFields.accessToken);
}
