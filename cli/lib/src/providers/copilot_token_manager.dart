/// Exchanges long-lived GitHub OAuth tokens for short-lived Copilot tokens,
/// caches the result in [CredentialStore], and refreshes on expiry.
///
/// GitHub Copilot issues a ~30-minute token that authorizes requests against
/// `api.githubcopilot.com`. This module is the single source of truth for
/// "give me a valid Copilot bearer" — every LLM request funnels through it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:glue/src/credentials/credential_store.dart';
import 'package:http/http.dart' as http;

/// Matches OpenCode / VS Code / LiteLLM / copilot-api. It's the public
/// GitHub OAuth app id for the Copilot CLI; everyone uses it.
const String copilotClientId = 'Iv1.b507a08c87ecfe98';

const String _copilotTokenEndpoint =
    'https://api.github.com/copilot_internal/v2/token';

/// Field keys stored under `providers.copilot` in credentials.json.
abstract class CopilotFields {
  static const githubToken = 'github_token';
  static const copilotToken = 'copilot_token';
  static const expiresAt = 'copilot_token_expires_at';
}

class CopilotAuthException implements Exception {
  CopilotAuthException(this.message);
  final String message;

  @override
  String toString() => 'CopilotAuthException: $message';
}

class CopilotTokenExchange {
  const CopilotTokenExchange({required this.token, required this.expiresAt});
  final String token;
  final DateTime expiresAt;
}

/// POST the Copilot token endpoint with the user's GitHub token.
/// Returns the short-lived Copilot bearer plus its expiry timestamp.
Future<CopilotTokenExchange> exchangeGithubTokenForCopilotToken(
  String githubToken, {
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  final shouldClose = client == null;
  try {
    final response = await httpClient.get(
      Uri.parse(_copilotTokenEndpoint),
      headers: {
        'authorization': 'token $githubToken',
        'accept': 'application/json',
        'editor-version': 'Glue/dev',
      },
    );
    if (response.statusCode != 200) {
      throw CopilotAuthException(
        'token exchange failed (HTTP ${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['token'] is! String) {
      throw CopilotAuthException('malformed token response');
    }
    final token = decoded['token'] as String;
    final expiresAt = decoded['expires_at'];
    final DateTime expiry;
    if (expiresAt is int) {
      expiry = DateTime.fromMillisecondsSinceEpoch(
        expiresAt * 1000,
        isUtc: true,
      );
    } else {
      expiry = DateTime.now().toUtc().add(const Duration(minutes: 25));
    }
    return CopilotTokenExchange(token: token, expiresAt: expiry);
  } finally {
    if (shouldClose) httpClient.close();
  }
}

/// Return a valid Copilot bearer. Reads the cached one from [store] when it
/// is safely in the future; otherwise re-exchanges using the stored GitHub
/// token and writes the refreshed pair back.
///
/// Throws [CopilotAuthException] when the user hasn't connected Copilot yet.
Future<String> freshCopilotToken(
  CredentialStore store, {
  http.Client? client,
  Duration skew = const Duration(minutes: 1),
}) async {
  final github = store.getField('copilot', CopilotFields.githubToken);
  if (github == null || github.isEmpty) {
    throw CopilotAuthException(
      'not connected — run `/provider add copilot`',
    );
  }

  final cachedToken = store.getField('copilot', CopilotFields.copilotToken);
  final cachedExpiryStr = store.getField('copilot', CopilotFields.expiresAt);
  final cachedExpiry =
      cachedExpiryStr != null ? DateTime.tryParse(cachedExpiryStr) : null;
  if (cachedToken != null &&
      cachedToken.isNotEmpty &&
      cachedExpiry != null &&
      cachedExpiry.isAfter(DateTime.now().toUtc().add(skew))) {
    return cachedToken;
  }

  final exchange =
      await exchangeGithubTokenForCopilotToken(github, client: client);
  store.setFields('copilot', {
    CopilotFields.githubToken: github,
    CopilotFields.copilotToken: exchange.token,
    CopilotFields.expiresAt: exchange.expiresAt.toIso8601String(),
  });
  return exchange.token;
}
