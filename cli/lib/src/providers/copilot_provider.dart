/// GitHub Copilot provider — OAuth 2.0 device authorization + a
/// periodically-refreshed short-lived Copilot bearer token, inference via
/// the OpenAI-compatible Copilot endpoint.
///
/// Endpoints (all public; same client id as the Copilot CLI / LiteLLM):
///   - `github.com/login/device/code`            — start device flow
///   - `github.com/login/oauth/access_token`     — poll for user approval
///   - `api.github.com/copilot_internal/v2/token`— exchange → Copilot bearer
///   - `api.githubcopilot.com/chat/completions`  — OpenAI-compatible inference
library;

import 'dart:async';
import 'dart:convert';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/credentials/credential_store.dart';
import 'package:glue/src/providers/auth_flow.dart';
import 'package:glue/src/providers/compatibility_profile.dart';
import 'package:glue/src/providers/copilot_token_manager.dart';
import 'package:glue/src/providers/openai_provider.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';
import 'package:http/http.dart' as http;
import 'package:glue/src/utils.dart';

const String _deviceCodeUrl = 'https://github.com/login/device/code';
const String _tokenUrl = 'https://github.com/login/oauth/access_token';
const String _deviceGrantType = 'urn:ietf:params:oauth:grant-type:device_code';
const String _defaultBaseUrl = 'https://api.githubcopilot.com';

/// Copilot adapter + client in one class.
///
/// - Adapter role: device-code OAuth flow, health checks, token caching via
///   [CredentialStore], spawning per-request client instances.
/// - Client role: refresh the Copilot bearer on every request and delegate
///   streaming to an internal [OpenAiProvider] configured with the
///   Copilot-Integration-Id + Editor-Version headers Copilot demands.
class CopilotProvider extends ProviderAdapter implements LlmClient {
  CopilotProvider({
    http.Client? client,
    CredentialStore? credentialStore,
    http.Client Function()? requestClientFactory,
    // Client-role state — set by createClient() when spawning a per-request
    // instance. Zero-valued on an adapter-role instance.
    this.model = '',
    this.systemPrompt = '',
    this.baseUrl = _defaultBaseUrl,
  })  : _http = client ?? http.Client(),
        _store = credentialStore,
        _requestClientFactory = requestClientFactory;

  final http.Client _http;
  final CredentialStore? _store;
  final http.Client Function()? _requestClientFactory;

  final String model;
  final String systemPrompt;
  final String baseUrl;

  // ---------- ProviderAdapter ----------

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
    if (_store == null) {
      throw StateError(
        'CopilotProvider needs a CredentialStore to refresh tokens; '
        'construct it with credentialStore:',
      );
    }
    return CopilotProvider(
      client: _http,
      credentialStore: _store,
      requestClientFactory: _requestClientFactory,
      model: model.apiId,
      systemPrompt: systemPrompt,
      baseUrl: provider.baseUrl ?? _defaultBaseUrl,
    );
  }

  @override
  Future<AuthFlow?> beginInteractiveAuth({
    required ProviderDef provider,
    required CredentialStore store,
  }) async {
    final device = await _requestDeviceCode(_http);

    // ignore: close_sinks -- closed inside _runPollingLoop's finally block.
    final progress = StreamController<AuthFlowProgress>();
    unawaited(
      _runPollingLoop(
        device: device,
        httpClient: _http,
        store: store,
        progress: progress,
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

  // ---------- LlmClient ----------

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    final store = _store;
    if (store == null) {
      throw StateError(
        'CopilotProvider.stream called on an instance without a '
        'CredentialStore — did you forget createClient()?',
      );
    }
    final token = await freshCopilotToken(store, client: _http);
    final inner = OpenAiProvider(
      apiKey: token,
      model: model,
      systemPrompt: systemPrompt,
      baseUrl: baseUrl,
      profile: CompatibilityProfile.openai,
      extraHeaders: {
        'Copilot-Integration-Id': 'vscode-chat',
        'Editor-Version': 'Glue/${AppConstants.version}',
      },
      requestClientFactory:
          _requestClientFactory ?? (() => _http),
    );
    yield* inner.stream(messages, tools: tools);
  }

  // ---------- OAuth helpers (private) ----------

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
      interval: ((decoded['interval'] as int?) ?? 5).seconds,
      expiresIn: ((decoded['expires_in'] as int?) ?? 900).seconds,
    );
  }

  Future<void> _runPollingLoop({
    required _DeviceCodeResponse device,
    required http.Client httpClient,
    required CredentialStore store,
    required StreamController<AuthFlowProgress> progress,
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
            interval += 5.seconds;
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
