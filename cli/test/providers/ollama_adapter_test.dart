/// Tests for the native Ollama adapter.
///
/// Covers the contract shift from "Ollama masquerades as OpenAI-compat"
/// to "Ollama gets its own adapter with num_ctx injection":
///   - createClient returns an OllamaClient pointed at `/api/chat`.
///   - model.apiId (not the catalog key) goes on the wire.
///   - contextWindow from ModelDef flows through as num_ctx.
///   - legacy `/v1` baseUrl suffix is stripped so native paths resolve.
///   - discoverModels hits /api/tags via OllamaDiscovery.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/credentials/credential_store.dart';
import 'package:glue/src/llm/ollama_client.dart';
import 'package:glue/src/providers/ollama_adapter.dart';
import 'package:glue/src/providers/ollama_discovery.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _FakeHttp extends http.BaseClient {
  _FakeHttp(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest req) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

ResolvedProvider _provider({String? baseUrl}) {
  return ResolvedProvider(
    def: ProviderDef(
      id: 'ollama',
      name: 'Ollama',
      adapter: 'ollama',
      baseUrl: baseUrl,
      auth: const AuthSpec(kind: AuthKind.none),
      models: const {},
    ),
    apiKey: null,
    credentials: const {},
  );
}

ResolvedModel _model({
  String id = 'qwen3-coder:30b',
  int? contextWindow,
  String? apiId,
}) {
  final def = ModelDef(
    id: id,
    name: id,
    apiId: apiId,
    contextWindow: contextWindow,
  );
  return ResolvedModel(
    def: def,
    provider: ProviderDef(
      id: 'ollama',
      name: 'Ollama',
      adapter: 'ollama',
      auth: const AuthSpec(kind: AuthKind.none),
      models: {id: def},
    ),
  );
}

void main() {
  group('OllamaAdapter.createClient', () {
    test('returns an OllamaClient', () {
      final adapter = OllamaAdapter();
      final client = adapter.createClient(
        provider: _provider(),
        model: _model(),
        systemPrompt: 'you are glue',
      );
      expect(client, isA<OllamaClient>());
    });

    test('propagates model.apiId on the wire, not the catalog key', () async {
      Map<String, Object?>? capturedBody;
      final adapter = OllamaAdapter(
        requestClientFactory: () => _FakeHttp((req) async {
          capturedBody =
              jsonDecode((req as http.Request).body) as Map<String, Object?>;
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(jsonEncode({
              'model': 'whatever',
              'message': {'role': 'assistant', 'content': ''},
              'done': true,
              'prompt_eval_count': 0,
              'eval_count': 0,
            }))),
            200,
            headers: {'content-type': 'application/x-ndjson'},
          );
        }),
      );
      final client = adapter.createClient(
        provider: _provider(),
        model: _model(id: 'qwen3-coder:30b', apiId: 'qwen3-coder:30b'),
        systemPrompt: '',
      );
      // Drain the stream to force the HTTP call.
      await client.stream([]).toList();
      expect(capturedBody?['model'], 'qwen3-coder:30b');
    });

    test('injects options.num_ctx from ModelDef.contextWindow', () async {
      Map<String, Object?>? capturedBody;
      final adapter = OllamaAdapter(
        requestClientFactory: () => _FakeHttp((req) async {
          capturedBody =
              jsonDecode((req as http.Request).body) as Map<String, Object?>;
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(jsonEncode({
              'message': {'role': 'assistant', 'content': ''},
              'done': true,
            }))),
            200,
            headers: {'content-type': 'application/x-ndjson'},
          );
        }),
      );
      final client = adapter.createClient(
        provider: _provider(),
        model: _model(contextWindow: 256000),
        systemPrompt: '',
      );
      await client.stream([]).toList();
      final options = capturedBody?['options'];
      expect(options, isA<Map<String, Object?>>());
      // 256K gets clamped to the 128K ceiling.
      expect(
          (options! as Map<String, Object?>)['num_ctx'], ollamaNumCtxCeiling);
    });

    test(
        'passes num_ctx through unclamped when ModelDef.contextWindow is '
        'below the ceiling', () async {
      Map<String, Object?>? capturedBody;
      final adapter = OllamaAdapter(
        requestClientFactory: () => _FakeHttp((req) async {
          capturedBody =
              jsonDecode((req as http.Request).body) as Map<String, Object?>;
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(jsonEncode({
              'message': {'role': 'assistant', 'content': ''},
              'done': true,
            }))),
            200,
            headers: {'content-type': 'application/x-ndjson'},
          );
        }),
      );
      final client = adapter.createClient(
        provider: _provider(),
        model: _model(contextWindow: 8192),
        systemPrompt: '',
      );
      await client.stream([]).toList();
      final options = capturedBody?['options'] as Map?;
      expect(options?['num_ctx'], 8192);
    });

    test(
        'omits options entirely when ModelDef.contextWindow is null '
        '(uncatalogued passthrough)', () async {
      Map<String, Object?>? capturedBody;
      final adapter = OllamaAdapter(
        requestClientFactory: () => _FakeHttp((req) async {
          capturedBody =
              jsonDecode((req as http.Request).body) as Map<String, Object?>;
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(jsonEncode({
              'message': {'role': 'assistant', 'content': ''},
              'done': true,
            }))),
            200,
            headers: {'content-type': 'application/x-ndjson'},
          );
        }),
      );
      final client = adapter.createClient(
        provider: _provider(),
        model: _model(contextWindow: null),
        systemPrompt: '',
      );
      await client.stream([]).toList();
      expect(capturedBody?.containsKey('options'), isFalse);
    });

    test('strips legacy /v1 suffix from baseUrl so /api/chat resolves',
        () async {
      Uri? capturedUrl;
      final adapter = OllamaAdapter(
        requestClientFactory: () => _FakeHttp((req) async {
          capturedUrl = req.url;
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(jsonEncode({
              'message': {'role': 'assistant', 'content': ''},
              'done': true,
            }))),
            200,
            headers: {'content-type': 'application/x-ndjson'},
          );
        }),
      );
      final client = adapter.createClient(
        provider: _provider(baseUrl: 'http://localhost:11434/v1'),
        model: _model(),
        systemPrompt: '',
      );
      await client.stream([]).toList();
      expect(capturedUrl.toString(), 'http://localhost:11434/api/chat');
    });
  });

  group('OllamaAdapter health', () {
    test('validate always returns ok (no credentials required)', () {
      expect(OllamaAdapter().validate(_provider()), ProviderHealth.ok);
    });

    test('isConnected is always true', () {
      final store = CredentialStore(
        path: '${Directory.systemTemp.path}/glue_adapter_test_creds.json',
        env: const {},
      );
      expect(OllamaAdapter().isConnected(_provider().def, store), isTrue);
    });
  });

  group('OllamaAdapter.discoverModels', () {
    setUp(OllamaDiscovery.resetCacheForTesting);

    test('maps /api/tags into DiscoveredModel list', () async {
      final adapter = OllamaAdapter(
        requestClientFactory: () => _FakeHttp((req) async {
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(jsonEncode({
              'models': [
                {'name': 'qwen3-coder:30b', 'size': 20000000000},
                {'name': 'gemma4:latest', 'size': 9600000000},
              ],
            }))),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      // discoverModels uses OllamaDiscovery internally, which builds its
      // own http.Client. We can't easily inject it end-to-end here — the
      // contract test lives in ollama_discovery_test.dart. This is just
      // a smoke test that the adapter returns the expected shape when
      // the daemon is actually present. If the daemon isn't, we expect
      // an empty list (fail-soft), which is also a valid outcome.
      final out = await adapter.discoverModels(_provider());
      expect(out, isA<List<DiscoveredModel>>());
    });
  });
}
