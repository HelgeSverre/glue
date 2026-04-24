/// OpenAiProvider tests — covers both adapter-role wiring (compat profile,
/// base URL, headers, auth) and client-role parsing.
///
/// Adapter-role: a captured http.Client records outgoing requests so we can
/// assert on the golden request surface per compatibility profile.
/// Client-role: parseStreamEvents is fed synthetic chunks.
library;

import 'dart:async';
import 'dart:convert';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/providers/compatibility_profile.dart';
import 'package:glue/src/providers/openai_provider.dart';
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
  OpenAiProvider client, {
  List<Message>? messages,
  List<Tool>? tools,
}) async {
  final captured = _CapturedRequest();
  final clone = OpenAiProvider(
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
  group('OpenAiProvider.adapterId', () {
    test('is "openai"', () {
      expect(OpenAiProvider().adapterId, 'openai');
    });
  });

  group('OpenAiProvider.createClient', () {
    test('vanilla openai: uses api.openai.com + Bearer + stream_options',
        () async {
      final adapter = OpenAiProvider();
      final client = adapter.createClient(
        provider: _resolved(id: 'openai', apiKey: 'sk-oa'),
        model: _model('gpt-5.4'),
        systemPrompt: '',
      ) as OpenAiProvider;
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
      final adapter = OpenAiProvider();
      final client = adapter.createClient(
        provider: _resolved(
          id: 'groq',
          compatibility: 'groq',
          baseUrl: 'https://api.groq.com/openai/v1',
          apiKey: 'sk-groq',
        ),
        model: _model('gpt-oss-120b'),
        systemPrompt: '',
      ) as OpenAiProvider;
      expect(client.profile, CompatibilityProfile.groq);

      final captured = await _capture(client);
      final req = captured.request!;
      expect(req.url.host, 'api.groq.com');
      expect(req.url.path, '/openai/v1/chat/completions');
      expect(req.headers['Authorization'], 'Bearer sk-groq');
      final body = jsonDecode(captured.body!) as Map<String, dynamic>;
      expect(body.containsKey('stream_options'), isFalse);
    });

    test('openrouter profile: injects HTTP-Referer and X-Title headers',
        () async {
      final adapter = OpenAiProvider();
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
      ) as OpenAiProvider;

      final captured = await _capture(client);
      final req = captured.request!;
      expect(req.headers['HTTP-Referer'], 'https://getglue.dev');
      expect(req.headers['X-Title'], 'Glue');
    });

    test(
        'validate: ok for AuthKind.none, missing when env-backed and no apiKey',
        () {
      final adapter = OpenAiProvider();
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

  group('OpenAiProvider.parseStreamEvents', () {
    test('parses text deltas', () async {
      final events = [
        {
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': 'Hello '}
            }
          ]
        },
        {
          'choices': [
            {
              'index': 0,
              'delta': {'content': 'world'}
            }
          ]
        },
        {
          'choices': [
            {'index': 0, 'delta': {}, 'finish_reason': 'stop'}
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 5}
        },
      ];
      final chunks = await OpenAiProvider.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final text = chunks.whereType<TextDelta>().map((d) => d.text).join();
      expect(text, 'Hello world');
    });

    test('parses streaming tool calls', () async {
      final events = [
        {
          'choices': [
            {
              'index': 0,
              'delta': {
                'role': 'assistant',
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'tc1',
                    'type': 'function',
                    'function': {'name': 'read_file', 'arguments': ''}
                  }
                ]
              }
            }
          ]
        },
        {
          'choices': [
            {
              'index': 0,
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': '{"path":'}
                  }
                ]
              }
            }
          ]
        },
        {
          'choices': [
            {
              'index': 0,
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': ' "main.dart"}'}
                  }
                ]
              }
            }
          ]
        },
        {
          'choices': [
            {'index': 0, 'delta': {}, 'finish_reason': 'tool_calls'}
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 15}
        },
      ];

      final chunks = await OpenAiProvider.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final toolCalls = chunks.whereType<ToolCallComplete>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.toolCall.name, 'read_file');
      expect(toolCalls.first.toolCall.arguments['path'], 'main.dart');
    });

    test('emits ToolCallStart before ToolCallComplete', () async {
      final events = [
        {
          'choices': [
            {
              'index': 0,
              'delta': {
                'role': 'assistant',
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'tc1',
                    'type': 'function',
                    'function': {'name': 'write_file', 'arguments': ''}
                  }
                ]
              }
            }
          ]
        },
        {
          'choices': [
            {
              'index': 0,
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': '{"path": "a.txt"}'}
                  }
                ]
              }
            }
          ]
        },
        {
          'choices': [
            {'index': 0, 'delta': {}, 'finish_reason': 'tool_calls'}
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 10}
        },
      ];

      final chunks = await OpenAiProvider.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final starts = chunks.whereType<ToolCallStart>().toList();
      expect(starts, hasLength(1));
      expect(starts.first.id, 'tc1');
      expect(starts.first.name, 'write_file');

      final startIdx = chunks.indexWhere((c) => c is ToolCallStart);
      final deltaIdx = chunks.indexWhere((c) => c is ToolCallComplete);
      expect(startIdx, lessThan(deltaIdx));
    });
  });
}
