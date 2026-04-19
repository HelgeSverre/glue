/// Adapter for GitHub Copilot using OAuth 2.0 device authorization + a
/// periodically-refreshed short-lived Copilot bearer token.
///
/// Endpoints (all public; same client id as the Copilot CLI / LiteLLM):
///   - `github.com/login/device/code`            — start device flow
///   - `github.com/login/oauth/access_token`     — poll for user approval
///   - `api.github.com/copilot_internal/v2/token`— exchange → Copilot bearer
///   - `api.githubcopilot.com/chat/completions`  — OpenAI-compatible inference
library;

import 'dart:async';
import 'dart:convert';

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/credentials/credential_store.dart';
import 'package:glue/src/llm/openai_client.dart';
import 'package:glue/src/providers/auth_flow.dart';
import 'package:glue/src/providers/compatibility_profile.dart';
import 'package:glue/src/providers/copilot_token_manager.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';
import 'package:http/http.dart' as http;

const String _deviceCodeUrl = 'https://github.com/login/device/code';
const String _tokenUrl = 'https://github.com/login/oauth/access_token';
const String _deviceGrantType = 'urn:ietf:params:oauth:grant-type:device_code';

class CopilotAdapter extends ProviderAdapter {
  CopilotAdapter({
    http.Client? httpClient,
    CredentialStore? credentialStore,
  })  : _http = httpClient,
        _store = credentialStore;

  final http.Client? _http;
  final CredentialStore? _store;

  @override
  String get adapterId => 'copilot';

  @override
  ProviderHealth validate(ResolvedProvider provider) {
    final github = provider.credentials[CopilotFields.githubToken];
    return (github != null && github.isNotEmpty)
        ? ProviderHealth.ok
        : ProviderHealth.missingCredential;
  }

  @override
  bool isConnected(ProviderDef provider, CredentialStore store) {
    final github = store.getField(provider.id, CopilotFields.githubToken);
    return github != null && github.isNotEmpty;
  }

  @override
  LlmClient createClient({
    required ResolvedProvider provider,
    required ResolvedModel model,
    required String systemPrompt,
  }) {
    final store = _store;
    if (store == null) {
      throw StateError(
        'CopilotAdapter needs a CredentialStore to refresh tokens; '
        'construct it with credentialStore:',
      );
    }
    return _CopilotClient(
      store: store,
      model: model.apiId,
      systemPrompt: systemPrompt,
      baseUrl: provider.baseUrl ?? 'https://api.githubcopilot.com',
      httpClient: _http,
    );
  }

  @override
  Future<AuthFlow?> beginInteractiveAuth({
    required ProviderDef provider,
    required CredentialStore store,
  }) async {
    final httpClient = _http ?? http.Client();
    final ownsClient = _http == null;

    final device = await _requestDeviceCode(httpClient);

    // ignore: close_sinks -- closed inside _runPollingLoop's finally block.
    final progress = StreamController<AuthFlowProgress>();
    unawaited(
      _runPollingLoop(
        device: device,
        httpClient: httpClient,
        store: store,
        progress: progress,
        closeOnDone: ownsClient,
      ),
    );

    return DeviceCodeFlow(
      providerId: provider.id,
      providerName: provider.name,
      verificationUri: device.verificationUri,
      userCode: device.userCode,
      pollInterval: device.interval,
      expiresAt: DateTime.now().toUtc().add(device.expiresIn),
      progress: progress.stream,
    );
  }

  Future<_DeviceCodeResponse> _requestDeviceCode(http.Client client) async {
    final response = await client.post(
      Uri.parse(_deviceCodeUrl),
      headers: {
        'accept': 'application/json',
        'content-type': 'application/x-www-form-urlencoded',
      },
      body: 'client_id=$copilotClientId&scope=read:user',
    );
    if (response.statusCode != 200) {
      throw CopilotAuthException(
        'device code request failed (HTTP ${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw CopilotAuthException('malformed device code response');
    }
    return _DeviceCodeResponse(
      deviceCode: decoded['device_code'] as String,
      userCode: decoded['user_code'] as String,
      verificationUri: decoded['verification_uri'] as String,
      interval: Duration(seconds: (decoded['interval'] as int?) ?? 5),
      expiresIn: Duration(seconds: (decoded['expires_in'] as int?) ?? 900),
    );
  }

  Future<void> _runPollingLoop({
    required _DeviceCodeResponse device,
    required http.Client httpClient,
    required CredentialStore store,
    required StreamController<AuthFlowProgress> progress,
    required bool closeOnDone,
  }) async {
    final deadline = DateTime.now().toUtc().add(device.expiresIn);
    var interval = device.interval;

    try {
      while (true) {
        if (DateTime.now().toUtc().isAfter(deadline)) {
          progress.add(
            const AuthFlowFailed(reason: 'device code expired'),
          );
          return;
        }
        if (interval > Duration.zero) {
          await Future<void>.delayed(interval);
        }
        progress.add(const AuthFlowPolling());

        final pollResponse = await httpClient.post(
          Uri.parse(_tokenUrl),
          headers: {
            'accept': 'application/json',
            'content-type': 'application/x-www-form-urlencoded',
          },
          body: 'client_id=$copilotClientId'
              '&device_code=${device.deviceCode}'
              '&grant_type=$_deviceGrantType',
        );
        final body = jsonDecode(pollResponse.body);
        if (body is! Map) {
          progress.add(
            const AuthFlowFailed(reason: 'malformed poll response'),
          );
          return;
        }
        final accessToken = body['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          try {
            final exchange = await exchangeGithubTokenForCopilotToken(
              accessToken,
              client: httpClient,
            );
            final fields = <String, String>{
              CopilotFields.githubToken: accessToken,
              CopilotFields.copilotToken: exchange.token,
              CopilotFields.expiresAt: exchange.expiresAt.toIso8601String(),
            };
            store.setFields('copilot', fields);
            progress.add(AuthFlowSucceeded(fields: fields));
          } on CopilotAuthException catch (e) {
            progress.add(AuthFlowFailed(reason: e.message));
          }
          return;
        }

        final error = body['error'] as String?;
        switch (error) {
          case 'authorization_pending':
            continue;
          case 'slow_down':
            interval += const Duration(seconds: 5);
            continue;
          case 'access_denied':
            progress.add(
              const AuthFlowFailed(reason: 'access denied'),
            );
            return;
          case 'expired_token':
            progress.add(
              const AuthFlowFailed(reason: 'device code expired'),
            );
            return;
          default:
            progress.add(
              AuthFlowFailed(reason: error ?? 'unknown error'),
            );
            return;
        }
      }
    } finally {
      await progress.close();
      if (closeOnDone) httpClient.close();
    }
  }
}

class _DeviceCodeResponse {
  _DeviceCodeResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.interval,
    required this.expiresIn,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final Duration interval;
  final Duration expiresIn;
}

/// Thin LlmClient that refreshes its Copilot bearer on every request and
/// injects the required Copilot-Integration-Id + Editor-Version headers.
class _CopilotClient implements LlmClient {
  _CopilotClient({
    required this.store,
    required this.model,
    required this.systemPrompt,
    required this.baseUrl,
    http.Client? httpClient,
  }) : _http = httpClient;

  final CredentialStore store;
  final String model;
  final String systemPrompt;
  final String baseUrl;
  final http.Client? _http;

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    final token = await freshCopilotToken(store, client: _http);
    final inner = OpenAiClient(
      apiKey: token,
      model: model,
      systemPrompt: systemPrompt,
      baseUrl: baseUrl,
      profile: CompatibilityProfile.openai,
      extraHeaders: {
        'Copilot-Integration-Id': 'vscode-chat',
        'Editor-Version': 'Glue/${AppConstants.version}',
      },
      requestClientFactory: _http != null ? () => _http : null,
    );
    yield* inner.stream(messages, tools: tools);
  }
}
