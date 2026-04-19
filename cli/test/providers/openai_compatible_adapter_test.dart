/// Verifies that [OpenAiCompatibleAdapter] wires the correct compatibility
/// profile, base URL, headers, and API key into [OpenAiClient] based on the
/// [ProviderDef]'s `compatibility` field.
///
/// We don't make real HTTP calls — a captured `http.Client` records the
/// outgoing request and we assert on its headers/body. This is the golden
/// request surface per compatibility profile.
library;

import 'dart:async';
import 'dart:convert';

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/llm/openai_client.dart';
import 'package:glue/src/providers/compatibility_profile.dart';
import 'package:glue/src/providers/openai_compatible_adapter.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _CapturedRequest {
  http.BaseRequest? request;
  String? body;
}

class _CapturingClient implements http.Client {
  _CapturingClient(this.captured);
  final _CapturedRequest captured;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    captured.request = request;
    if (request is http.Request) captured.body = request.body;
    return http.StreamedResponse(
      const Stream<List<int>>.empty(),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  @override
  void close() {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_CapturedRequest> _capture(
  OpenAiClient client, {
  List<Message>? messages,
  List<Tool>? tools,
}) async {
  final captured = _CapturedRequest();
  // The client reads its factory on each call; we swap it in via reflection
  // of sorts — we just build a new client sharing the same fields via the
  // profile/baseUrl/apiKey we inject through the adapter path. So instead of
  // mutating, rebuild:
  final clone = OpenAiClient(
    apiKey: client.apiKey,
    model: client.model,
    systemPrompt: client.systemPrompt,
    baseUrl: client.baseUrl,
    profile: client.profile,
    extraHeaders: client.extraHeaders,
    requestClientFactory: () => _CapturingClient(captured),
  );
  final msgs = messages ?? [Message.user('hi')];
  await clone.stream(msgs, tools: tools).drain<void>();
  return captured;
}

ResolvedProvider _resolved({
  required String id,
  String adapter = 'openai',
  String? compatibility,
  String? baseUrl,
  String? apiKey,
  Map<String, String> headers = const {},
  AuthKind authKind = AuthKind.apiKey,
}) =>
    ResolvedProvider(
      def: ProviderDef(
        id: id,
        name: id,
        adapter: adapter,
        compatibility: compatibility,
        baseUrl: baseUrl,
        auth: AuthSpec(
            kind: authKind, envVar: authKind == AuthKind.apiKey ? 'X' : null),
        requestHeaders: headers,
        models: const {},
      ),
      apiKey: apiKey,
    );

const _placeholderProvider = ProviderDef(
  id: 'p',
  name: 'p',
  adapter: 'openai',
  auth: AuthSpec(kind: AuthKind.none),
  models: {},
);

ResolvedModel _model(String id, {ProviderDef? provider}) => ResolvedModel(
      def: ModelDef(id: id, name: id),
      provider: provider ?? _placeholderProvider,
    );

void main() {
  group('OpenAiCompatibleAdapter.adapterId', () {
    test('is "openai"', () {
      expect(OpenAiCompatibleAdapter().adapterId, 'openai');
    });
  });

  group('OpenAiCompatibleAdapter.createClient', () {
    test('vanilla openai: uses api.openai.com + Bearer + stream_options',
        () async {
      final adapter = OpenAiCompatibleAdapter();
      final client = adapter.createClient(
        provider: _resolved(id: 'openai', apiKey: 'sk-oa'),
        model: _model('gpt-5.4'),
        systemPrompt: '',
      ) as OpenAiClient;
      expect(client.profile, CompatibilityProfile.openai);

      final captured = await _capture(client);
      final req = captured.request!;
      expect(req.url.host, 'api.openai.com');
      expect(req.headers['Authorization'], 'Bearer sk-oa');
      final body = jsonDecode(captured.body!) as Map<String, dynamic>;
      expect(body['stream_options'], isNotNull);
    });

    test('groq profile: uses custom base URL and strips stream_options',
        () async {
      final adapter = OpenAiCompatibleAdapter();
      final client = adapter.createClient(
        provider: _resolved(
          id: 'groq',
          compatibility: 'groq',
          baseUrl: 'https://api.groq.com/openai/v1',
          apiKey: 'sk-groq',
        ),
        model: _model('qwen/qwen3-coder'),
        systemPrompt: '',
      ) as OpenAiClient;
      expect(client.profile, CompatibilityProfile.groq);

      final captured = await _capture(client);
      final req = captured.request!;
      expect(req.url.host, 'api.groq.com');
      expect(req.headers['Authorization'], 'Bearer sk-groq');
      final body = jsonDecode(captured.body!) as Map<String, dynamic>;
      expect(body.containsKey('stream_options'), isFalse);
    });

    test('ollama profile: no Authorization header, no stream_options',
        () async {
      final adapter = OpenAiCompatibleAdapter();
      final client = adapter.createClient(
        provider: _resolved(
          id: 'ollama',
          compatibility: 'ollama',
          baseUrl: 'http://localhost:11434/v1',
          authKind: AuthKind.none,
        ),
        model: _model('llama3.2'),
        systemPrompt: '',
      ) as OpenAiClient;
      expect(client.profile, CompatibilityProfile.ollama);

      final captured = await _capture(client);
      final req = captured.request!;
      expect(req.headers.containsKey('Authorization'), isFalse);
      final body = jsonDecode(captured.body!) as Map<String, dynamic>;
      expect(body.containsKey('stream_options'), isFalse);
    });

    test('openrouter profile: injects HTTP-Referer and X-Title headers',
        () async {
      final adapter = OpenAiCompatibleAdapter();
      final client = adapter.createClient(
        provider: _resolved(
          id: 'openrouter',
          compatibility: 'openrouter',
          baseUrl: 'https://openrouter.ai/api/v1',
          apiKey: 'sk-or',
          headers: {
            'HTTP-Referer': 'https://getglue.dev',
            'X-Title': 'Glue',
          },
        ),
        model: _model('anthropic/claude-sonnet-4.6'),
        systemPrompt: '',
      ) as OpenAiClient;

      final captured = await _capture(client);
      final req = captured.request!;
      expect(req.headers['HTTP-Referer'], 'https://getglue.dev');
      expect(req.headers['X-Title'], 'Glue');
    });

    test(
        'validate: ok for AuthKind.none, missing when env-backed and no apiKey',
        () {
      final adapter = OpenAiCompatibleAdapter();
      expect(
        adapter.validate(_resolved(id: 'ollama', authKind: AuthKind.none)),
        ProviderHealth.ok,
      );
      expect(
        adapter.validate(_resolved(id: 'openai')),
        ProviderHealth.missingCredential,
      );
      expect(
        adapter.validate(_resolved(id: 'openai', apiKey: 'sk-x')),
        ProviderHealth.ok,
      );
    });
  });
}
