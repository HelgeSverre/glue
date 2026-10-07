import 'dart:convert';

import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../_helpers/test_config.dart';

void main() {
  final ref = ModelRef.parse('anthropic/claude-haiku-5-5');

  test('Haiku 5.5 is recommended with its native limits and reasoning', () {
    final provider = bundledCatalog.providers['anthropic']!;
    final model = provider.models[ref.modelId]!;
    expect(model.recommended, isTrue);
    expect(model.apiId, 'claude-haiku-5-5');
    expect(model.contextWindow, 1000000);
    expect(model.maxOutputTokens, 128000);
    expect(model.capabilities, containsAll(['tools', 'vision', 'reasoning']));
    expect(model.reasoning!.defaultEffort, ReasoningEffort.medium);
    expect(provider.models['claude-haiku-4-5']!.recommended, isFalse);
  });

  for (final effort in ReasoningEffort.values.where(
    (effort) => effort != ReasoningEffort.minimal,
  )) {
    test(
      'Haiku 5.5 resolves $effort through the factory and adapter',
      () async {
        late http.Request request;
        final config = testConfig(
          activeModel: ref,
          env: {'ANTHROPIC_API_KEY': 'sk-test'},
        ).copyWith(reasoning: ReasoningConfig(effort: effort));
        config.adapters = AdapterRegistry([
          AnthropicAdapter(
            requestClientFactory: () => MockClient((r) async {
              request = r;
              return http.Response('data: {"type":"message_stop"}\n\n', 200);
            }),
          ),
        ]);
        final client = LlmClientFactory(
          config,
        ).createFromConfig(systemPrompt: 'You are Glue.');
        await client.stream([Message.user('hi')]).drain<void>();

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'claude-haiku-5-5');
        expect(body['max_tokens'], 128000);
        expect(body.keys, isNot(contains('temperature')));
        expect(body.keys, isNot(contains('top_p')));
        expect(body.keys, isNot(contains('top_k')));
        if (effort == ReasoningEffort.off) {
          expect(body['thinking'], {'type': 'disabled'});
          expect(body, isNot(contains('output_config')));
        } else {
          expect(body['thinking'], {
            'type': 'adaptive',
            'display': 'omitted',
            'block_binding': {'prefix_mismatch_behavior': 'drop_block'},
          });
          expect(
            request.headers['anthropic-beta'],
            contains('thinking-binding-controls-2026-08-01'),
          );
          if (effort == ReasoningEffort.auto) {
            expect(body, isNot(contains('output_config')));
          } else {
            expect(body['output_config'], {'effort': effort.name});
          }
        }
      },
    );
  }

  test(
    'show thoughts requests summaries and preserves provider betas',
    () async {
      late http.Request request;
      final client = AnthropicClient(
        apiKey: 'sk-test',
        model: ref.modelId,
        systemPrompt: '',
        reasoning: const ReasoningConfig(showThoughts: true),
        extraHeaders: const {'Anthropic-Beta': 'other-beta'},
        requestClientFactory: () => MockClient((r) async {
          request = r;
          return http.Response('data: {"type":"message_stop"}\n\n', 200);
        }),
      );
      await client.stream([Message.user('hi')]).drain<void>();
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect((body['thinking'] as Map)['display'], 'summarized');
      expect(request.headers['anthropic-beta'], contains('other-beta'));
      expect(
        request.headers['anthropic-beta'],
        contains('thinking-binding-controls-2026-08-01'),
      );
    },
  );

  for (final showThoughts in [false, true]) {
    test(
      'replays signature-only thinking and tool calls ($showThoughts)',
      () async {
        final events = [
          {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'thinking', 'thinking': ''},
          },
          for (final signature in ['signed-', 'reasoning'])
            {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'signature_delta', 'signature': signature},
            },
          {'type': 'content_block_stop', 'index': 0},
          {
            'type': 'content_block_start',
            'index': 1,
            'content_block': {
              'type': 'tool_use',
              'id': 'call-1',
              'name': 'lookup',
              'input': <String, dynamic>{},
            },
          },
          {
            'type': 'content_block_delta',
            'index': 1,
            'delta': {'type': 'input_json_delta', 'partial_json': '{"id":42}'},
          },
          {'type': 'content_block_stop', 'index': 1},
          {'type': 'message_stop'},
        ];
        final chunks = await AnthropicClient.parseStreamEvents(
          Stream.fromIterable(events),
          showThoughts: showThoughts,
        ).toList();
        final artifact = chunks
            .whereType<ReasoningArtifactChunk>()
            .single
            .artifact;
        expect(artifact, {
          'type': 'thinking',
          'thinking': '',
          'signature': 'signed-reasoning',
        });
        final call = chunks.whereType<ToolCallComplete>().single.toolCall;
        expect(call.arguments, {'id': 42});
        final history = [
          Message.user('Look up 42'),
          Message.assistant(reasoningArtifacts: [artifact], toolCalls: [call]),
          Message.toolResult(callId: call.id, content: 'found'),
        ];
        final mapped = const AnthropicMessageMapper().mapMessages(
          history,
          systemPrompt: '',
        );
        expect((mapped.messages[1]['content'] as List).first, artifact);
        expect(mapped.messages.last['role'], 'user');

        late Map<String, dynamic> body;
        final client = AnthropicClient(
          apiKey: 'sk-test',
          model: ref.modelId,
          systemPrompt: 'changed after resume',
          reasoning: const ReasoningConfig(effort: ReasoningEffort.off),
          requestClientFactory: () => MockClient((request) async {
            body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response('data: {"type":"message_stop"}\n\n', 200);
          }),
        );
        await client.stream(history).drain<void>();
        final assistant = (body['messages'] as List)[1] as Map;
        final content = assistant['content'] as List;
        expect((content.single as Map)['type'], 'tool_use');
        expect(history[1].reasoningArtifacts, [artifact]);
      },
    );
  }

  test('refusal stop reason surfaces an error instead of an empty success', () {
    final events = Stream<Map<String, dynamic>>.fromIterable([
      {
        'type': 'message_delta',
        'delta': {'stop_reason': 'refusal'},
        'usage': {'output_tokens': 0},
      },
      {'type': 'message_stop'},
    ]);
    expect(
      AnthropicClient.parseStreamEvents(events),
      emitsError(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('refus'),
        ),
      ),
    );
  });
}
