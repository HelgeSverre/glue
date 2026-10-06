import 'dart:convert';

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/src/llm/retry.dart';
import 'package:glue_strategies/src/llm/sse.dart';
import 'package:glue_strategies/src/llm/stream_request.dart';
import 'package:glue_strategies/src/llm/tool_args.dart';
import 'package:http/http.dart' as http;

/// Native OpenAI Responses API client used for reasoning-capable tool loops.
class OpenAiResponsesClient implements LlmClient {
  OpenAiResponsesClient({
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    required this.baseUrl,
    this.reasoning = const ReasoningConfig(),
    this.extraHeaders = const {},
    http.Client Function()? requestClientFactory,
  }) : _requestClientFactory = requestClientFactory ?? http.Client.new,
       _baseUri = Uri.parse(baseUrl);

  final http.Client Function() _requestClientFactory;
  final String apiKey;
  final String model;
  final String systemPrompt;
  final String baseUrl;
  final ReasoningConfig reasoning;
  final Map<String, String> extraHeaders;
  final Uri _baseUri;

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) {
    final input = <Map<String, dynamic>>[];
    for (final message in messages) {
      switch (message.role) {
        case Role.user:
          input.add({'role': 'user', 'content': message.text ?? ''});
        case Role.assistant:
          input.addAll(message.reasoningArtifacts);
          if (message.text case final text? when text.isNotEmpty) {
            input.add({'role': 'assistant', 'content': text});
          }
          for (final call in message.toolCalls) {
            input.add({
              'type': 'function_call',
              'call_id': call.id.value,
              'name': call.name,
              'arguments': jsonEncode(call.arguments),
            });
          }
        case Role.toolResult:
          input.add({
            'type': 'function_call_output',
            'call_id': message.toolCallId,
            'output': message.text ?? '',
          });
      }
    }

    final body = <String, dynamic>{
      'model': model,
      'instructions': systemPrompt,
      'input': input,
      'stream': true,
      if (reasoning.effort != ReasoningEffort.auto || reasoning.showThoughts)
        'reasoning': {
          if (reasoning.effort != ReasoningEffort.auto)
            'effort': reasoning.effort == ReasoningEffort.off
                ? 'none'
                : reasoning.effort.name,
          if (reasoning.showThoughts) 'summary': 'auto',
        },
      if (tools != null && tools.isNotEmpty)
        'tools': tools
            .map(
              (tool) => {
                'type': 'function',
                'name': tool.name,
                'description': tool.description,
                'parameters': {
                  'type': 'object',
                  'properties': Map.fromEntries(
                    tool.parameters.map(
                      (parameter) =>
                          MapEntry(parameter.name, parameter.toSchema()),
                    ),
                  ),
                  'required': tool.requiredParameters
                      .map((parameter) => parameter.name)
                      .toList(),
                },
              },
            )
            .toList(),
    };

    final endpointBase = _baseUri.path.endsWith('/')
        ? _baseUri
        : _baseUri.replace(path: '${_baseUri.path}/');
    return retryStream(
      () => sendAndStream(
        requestClientFactory: _requestClientFactory,
        uri: endpointBase.resolve('responses'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
          ...extraHeaders,
        },
        body: body,
        providerName: 'OpenAI',
        parse: (bytes) => parseStreamEvents(
          decodeSse(
            bytes,
          ).map((event) => jsonDecode(event.data) as Map<String, dynamic>),
        ),
      ),
      // Provider diagnostics can contain HTTP-looking text, but a terminal
      // Responses event must never trigger a retry.
      isTransient: (error) =>
          error is! _ResponsesStreamException && isTransientLlmError(error),
    );
  }

  static Stream<LlmChunk> parseStreamEvents(
    Stream<Map<String, dynamic>> events,
  ) async* {
    await for (final event in events) {
      switch (event['type']) {
        case 'response.output_text.delta':
          final delta = event['delta'];
          if (delta is String && delta.isNotEmpty) yield TextDelta(delta);
        case 'response.reasoning_summary_text.delta':
          final delta = event['delta'];
          if (delta is String && delta.isNotEmpty) yield ThinkingDelta(delta);
        case 'response.output_item.added':
          final item = event['item'];
          if (item is Map && item['type'] == 'function_call') {
            final id = (item['call_id'] ?? item['id'])?.toString();
            final name = item['name']?.toString();
            if (id != null && name != null) {
              yield ToolCallStart(id: ToolCallId(id), name: name);
            }
          }
        case 'response.output_item.done':
          final itemRaw = event['item'];
          if (itemRaw is! Map) continue;
          final item = itemRaw.cast<String, dynamic>();
          if (item['type'] == 'function_call') {
            final id = (item['call_id'] ?? item['id'])?.toString();
            final name = item['name']?.toString();
            if (id != null && name != null) {
              final args = ToolArgsBuffer<ToolCallId>(
                id: ToolCallId(id),
                name: name,
              );
              args.write(item['arguments']?.toString() ?? '{}');
              yield ToolCallComplete(
                ToolCall(
                  id: ToolCallId(id),
                  name: name,
                  arguments: args.finalizeArguments(),
                ),
              );
            }
          } else if (item['type'] == 'reasoning') {
            yield ReasoningArtifactChunk(item);
          }
        case 'response.completed':
        case 'response.failed':
        case 'response.incomplete':
          final response = event['response'];
          final usage = response is Map ? response['usage'] : null;
          if (usage is Map) {
            final input = usage['input_tokens'] as int? ?? 0;
            final cached =
                (usage['input_tokens_details'] as Map?)?['cached_tokens']
                    as int? ??
                0;
            yield UsageInfo(
              inputTokens: (input - cached).clamp(0, input),
              outputTokens: usage['output_tokens'] as int? ?? 0,
              cacheReadTokens: cached,
              reasoningTokens:
                  (usage['output_tokens_details'] as Map?)?['reasoning_tokens']
                      as int?,
            );
          }
          if (event['type'] == 'response.completed') return;
          if (event['type'] == 'response.incomplete') {
            final details = response is Map
                ? response['incomplete_details']
                : null;
            final reason = details is Map ? details['reason'] : null;
            throw _ResponsesStreamException(
              'OpenAI response.incomplete: '
              '${reason ?? 'Response incomplete without a reason'}',
            );
          }
          final error = response is Map ? response['error'] : null;
          throw _providerError('response.failed', error);
        case 'error':
          throw _providerError('error', event);
      }
    }
    throw const _ResponsesStreamException(
      'OpenAI Responses stream ended before response.completed; '
      'the response may be truncated',
    );
  }
}

_ResponsesStreamException _providerError(String type, Object? details) {
  final code = details is Map ? details['code'] : null;
  final message = details is Map ? details['message'] : null;
  return _ResponsesStreamException(
    'OpenAI $type: ${code ?? 'unknown_error'}: '
    '${message ?? 'Provider reported an error without a message'}',
  );
}

class _ResponsesStreamException implements Exception {
  const _ResponsesStreamException(this.message);

  final String message;

  @override
  String toString() => message;
}
