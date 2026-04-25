import 'dart:async';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/llm/llm.dart';
import 'package:glue/src/llm/tool_schema.dart';
import 'package:glue/src/providers/gemini_provider.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';
import 'package:test/test.dart';

void main() {
  group('GeminiProvider (adapter role)', () {
    test('adapterId is "gemini"', () {
      expect(GeminiProvider().adapterId, 'gemini');
    });

    test('createClient returns a GeminiProvider with the resolved apiKey', () {
      final adapter = GeminiProvider();
      const provider = ProviderDef(
        id: 'gemini',
        name: 'Google Gemini',
        adapter: 'gemini',
        auth: AuthSpec(kind: AuthKind.apiKey, envVar: 'GEMINI_API_KEY'),
        models: {},
      );
      const model = ModelDef(
        id: 'gemini-3-flash-preview',
        name: 'Gemini 3 Flash Preview',
      );
      final client = adapter.createClient(
        provider: const ResolvedProvider(def: provider, apiKey: 'sk-test'),
        model: const ResolvedModel(def: model, provider: provider),
        systemPrompt: 'you are a helpful assistant',
      );
      expect(client, isA<GeminiProvider>());
      expect((client as GeminiProvider).apiKey, 'sk-test');
      expect(client.model, 'gemini-3-flash-preview');
      expect(client.systemPrompt, 'you are a helpful assistant');
    });

    test('validate returns missingCredential when apiKey is null/empty', () {
      final adapter = GeminiProvider();
      const provider = ProviderDef(
        id: 'gemini',
        name: 'Google Gemini',
        adapter: 'gemini',
        auth: AuthSpec(kind: AuthKind.apiKey, envVar: 'GEMINI_API_KEY'),
        models: {},
      );
      expect(
        adapter.validate(const ResolvedProvider(def: provider, apiKey: null)),
        ProviderHealth.missingCredential,
      );
      expect(
        adapter.validate(const ResolvedProvider(def: provider, apiKey: '')),
        ProviderHealth.missingCredential,
      );
      expect(
        adapter.validate(const ResolvedProvider(def: provider, apiKey: 'sk')),
        ProviderHealth.ok,
      );
    });
  });

  group('GeminiToolEncoder', () {
    test('wraps tools in functionDeclarations and uppercases types', () {
      final encoded = const GeminiToolEncoder().encodeAll([_FakeTool()]);
      expect(encoded, hasLength(1));
      final fnDecls = encoded.first['functionDeclarations'] as List;
      expect(fnDecls, hasLength(1));
      final decl = fnDecls.first as Map<String, dynamic>;
      expect(decl['name'], 'echo');
      final params = decl['parameters'] as Map<String, dynamic>;
      expect(params['type'], 'OBJECT');
      expect(params['required'], ['msg']);
      final props = params['properties'] as Map<String, dynamic>;
      expect((props['msg'] as Map)['type'], 'STRING');
      expect((props['count'] as Map)['type'], 'INTEGER');
    });

    test('uppercases nested array item types', () {
      final encoded = const GeminiToolEncoder().encodeAll([_ArrayTool()]);
      final decl =
          (encoded.first['functionDeclarations'] as List).first as Map;
      final params = decl['parameters'] as Map<String, dynamic>;
      final props = params['properties'] as Map<String, dynamic>;
      final tagsSchema = props['tags'] as Map;
      expect(tagsSchema['type'], 'ARRAY');
      expect((tagsSchema['items'] as Map)['type'], 'STRING');
    });
  });

  group('GeminiProvider.parseStreamEvents (client role)', () {
    test('emits TextDeltas for text parts and a final UsageInfo', () async {
      final events = [
        {
          'candidates': [
            {
              'content': {
                'role': 'model',
                'parts': [
                  {'text': 'Hello '}
                ],
              }
            }
          ],
        },
        {
          'candidates': [
            {
              'content': {
                'role': 'model',
                'parts': [
                  {'text': 'world'}
                ],
              }
            }
          ],
        },
        {
          'usageMetadata': {
            'promptTokenCount': 7,
            'candidatesTokenCount': 5,
            'totalTokenCount': 12,
          },
        },
      ];
      final chunks = await GeminiProvider.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final text = chunks.whereType<TextDelta>().map((d) => d.text).join();
      expect(text, 'Hello world');

      final usage = chunks.whereType<UsageInfo>().single;
      expect(usage.inputTokens, 7);
      expect(usage.outputTokens, 5);
    });

    test('emits ToolCallStart + ToolCallComplete for functionCall parts',
        () async {
      final events = [
        {
          'candidates': [
            {
              'content': {
                'role': 'model',
                'parts': [
                  {
                    'functionCall': {
                      'name': 'read_file',
                      'args': {'path': 'main.dart'},
                    },
                  }
                ],
              },
              'finishReason': 'STOP',
            }
          ],
          'usageMetadata': {
            'promptTokenCount': 12,
            'candidatesTokenCount': 4,
            'totalTokenCount': 16,
          },
        },
      ];
      final chunks = await GeminiProvider.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final starts = chunks.whereType<ToolCallStart>().toList();
      final completes = chunks.whereType<ToolCallComplete>().toList();
      expect(starts, hasLength(1));
      expect(completes, hasLength(1));
      expect(starts.first.id, completes.first.toolCall.id);
      expect(completes.first.toolCall.name, 'read_file');
      expect(completes.first.toolCall.arguments['path'], 'main.dart');

      // ToolCallStart precedes ToolCallComplete.
      final startIdx = chunks.indexWhere((c) => c is ToolCallStart);
      final completeIdx = chunks.indexWhere((c) => c is ToolCallComplete);
      expect(startIdx, lessThan(completeIdx));
    });

    test('always emits a UsageInfo even when usageMetadata is absent',
        () async {
      final events = <Map<String, dynamic>>[
        {
          'candidates': [
            {
              'content': {
                'role': 'model',
                'parts': [
                  {'text': 'hi'}
                ],
              }
            }
          ],
        },
      ];
      final chunks = await GeminiProvider.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final usage = chunks.whereType<UsageInfo>().single;
      expect(usage.inputTokens, 0);
      expect(usage.outputTokens, 0);
    });
  });
}

class _FakeTool extends Tool {
  @override
  String get name => 'echo';
  @override
  String get description => 'Echo a message a number of times.';
  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'msg',
          type: 'string',
          description: 'Message to echo.',
        ),
        ToolParameter(
          name: 'count',
          type: 'integer',
          description: 'Repeat count.',
          required: false,
        ),
      ];
  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async =>
      ToolResult(content: 'noop');
}

class _ArrayTool extends Tool {
  @override
  String get name => 'tag';
  @override
  String get description => 'Apply tags.';
  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'tags',
          type: 'array',
          description: 'List of tags.',
          items: {'type': 'string'},
        ),
      ];
  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async =>
      ToolResult(content: 'noop');
}
