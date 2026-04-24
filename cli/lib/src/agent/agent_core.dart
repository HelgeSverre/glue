import 'dart:async';
import 'dart:convert';

import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/redaction.dart';

// ---------------------------------------------------------------------------
// Message types for the conversation history
// ---------------------------------------------------------------------------

/// Role of a message in the conversation.
///
/// {@category Agent}
enum Role { user, assistant, toolResult }

/// A single message in the conversation history.
class Message {
  final Role role;
  final String? text;
  final List<ToolCall> toolCalls;
  final String? toolCallId;
  final String? toolName;
  final List<ContentPart>? contentParts;

  const Message._({
    required this.role,
    this.text,
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
    this.contentParts,
  });

  factory Message.user(String text) => Message._(role: Role.user, text: text);

  factory Message.assistant({String? text, List<ToolCall>? toolCalls}) =>
      Message._(
        role: Role.assistant,
        text: text,
        toolCalls: toolCalls ?? const [],
      );

  factory Message.toolResult({
    required String callId,
    required String content,
    String? toolName,
    List<ContentPart>? contentParts,
  }) =>
      Message._(
          role: Role.toolResult,
          text: content,
          toolCallId: callId,
          toolName: toolName,
          contentParts: contentParts);
}

// ---------------------------------------------------------------------------
// LLM streaming types
// ---------------------------------------------------------------------------

/// A chunk emitted by the LLM streaming response.
sealed class LlmChunk {}

/// A delta of generated text.
class TextDelta extends LlmChunk {
  final String text;
  TextDelta(this.text);
}

/// The model has started a tool call, but the arguments are still streaming in.
///
/// Use this to show early UI feedback (e.g. "preparing read_file…") before the
/// full [ToolCallComplete] arrives with parsed arguments.
///
/// Not every provider emits this — Ollama delivers tool calls fully formed, so
/// you may only receive [ToolCallComplete]. Always treat this event as optional.
class ToolCallStart extends LlmChunk {
  final String id;
  final String name;
  ToolCallStart({required this.id, required this.name});
}

/// A fully-formed tool call with parsed arguments, ready to execute.
class ToolCallComplete extends LlmChunk {
  final ToolCall toolCall;
  ToolCallComplete(this.toolCall);
}

/// Token usage reported by the LLM after a response.
class UsageInfo extends LlmChunk {
  final int inputTokens;
  final int outputTokens;
  UsageInfo({required this.inputTokens, required this.outputTokens});

  int get totalTokens => inputTokens + outputTokens;
}

// ---------------------------------------------------------------------------
// Tool call / result
// ---------------------------------------------------------------------------

/// A tool invocation requested by the model.
class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String description;

  ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.description = '',
  });
}

// ---------------------------------------------------------------------------
// Abstract LLM client
// ---------------------------------------------------------------------------

/// Abstract LLM client — wraps any provider (Anthropic, OpenAI, etc.).
///
/// Implementations stream [LlmChunk]s for a given conversation and optional
/// tool definitions.
abstract class LlmClient {
  /// Streams a response for the given [messages].
  ///
  /// If [tools] are provided the model may emit [ToolCallComplete] chunks.
  Stream<LlmChunk> stream(
    List<Message> messages, {
    List<Tool>? tools,
  });
}

// ---------------------------------------------------------------------------
// App-level events emitted by the agent
// ---------------------------------------------------------------------------

/// Events emitted by the agent that the UI subscribes to.
sealed class AgentEvent {}

/// A delta of generated text forwarded to the UI.
class AgentTextDelta extends AgentEvent {
  final String delta;
  AgentTextDelta(this.delta);
}

/// Notification that a tool call is being prepared.
class AgentToolCallPending extends AgentEvent {
  final String id;
  final String name;
  AgentToolCallPending({required this.id, required this.name});
}

/// A fully-formed tool call ready for execution.
class AgentToolCall extends AgentEvent {
  final ToolCall call;
  AgentToolCall(this.call);
}

/// The result of an executed tool call.
class AgentToolResult extends AgentEvent {
  final ToolResult result;
  AgentToolResult(this.result);
}

/// Signals that the agent has finished its response.
class AgentDone extends AgentEvent {}

/// An error encountered during the agent loop.
class AgentError extends AgentEvent {
  final Object error;
  AgentError(this.error);
}

// ---------------------------------------------------------------------------
// Agent core
// ---------------------------------------------------------------------------

/// The agent core manages the LLM ↔ tool execution loop.
///
/// It runs independently from the UI, emitting [AgentEvent]s that the
/// application subscribes to. The agentic loop:
///
/// 1. Send messages to the LLM.
/// 2. Stream back text and/or tool calls.
/// 3. If tool calls are present: wait for execution results, add them to
///    the conversation, and go to step 1.
/// 4. If no tool calls: done.
class AgentCore {
  LlmClient llm;
  final Map<String, Tool> tools;
  final String modelId;
  final List<Message> _conversation = [];
  int tokenCount = 0;

  /// Optional observability sink. When non-null, tool invocations emit
  /// `tool.<name>` spans and fatal agent errors emit `agent.error` spans.
  final Observability? _obs;
  final ObservabilitySpan? _traceParent;

  /// Optional predicate to exclude tools before sending to the LLM.
  bool Function(Tool)? toolFilter;

  /// Tools to send to the LLM, filtered by [toolFilter] when set.
  List<Tool> get allowedTools {
    if (toolFilter == null) return tools.values.toList();
    return tools.values.where(toolFilter!).toList();
  }

  /// Completers keyed by tool call ID for parallel tool execution.
  final Map<String, Completer<ToolResult>> _pendingToolResults = {};

  AgentCore({
    required this.llm,
    required this.tools,
    String? modelId,
    Observability? obs,
    ObservabilitySpan? traceParent,
  })  : modelId = modelId ?? 'unknown',
        _obs = obs,
        _traceParent = traceParent;

  /// The full conversation history.
  List<Message> get conversation => List.unmodifiable(_conversation);

  /// Adds a message directly to the conversation history.
  void addMessage(Message message) => _conversation.add(message);

  /// Clear all conversation history (for session fork).
  void clearConversation() => _conversation.clear();

  /// Runs a [userMessage] through the agent loop.
  ///
  /// Returns a stream of [AgentEvent]s that the UI subscribes to.
  Stream<AgentEvent> run(String userMessage) async* {
    _conversation.add(Message.user(userMessage));

    try {
      while (true) {
        final assistantText = StringBuffer();
        final toolCalls = <ToolCall>[];
        final toolFutures = <Future<ToolResult>>[];
        final iterationSpan = _obs?.startSpan(
          'agent.iteration',
          kind: 'agent',
          parent: _traceParent,
          attributes: {
            'openinference.span.kind': 'AGENT',
            'llm.message_count': _conversation.length,
            'llm.tool_count': allowedTools.length,
            'llm.model_name': modelId,
          },
        );
        final llmSpan = _obs?.startSpan(
          'llm.stream',
          kind: 'llm',
          parent: iterationSpan,
          attributes: {
            'openinference.span.kind': 'LLM',
            'llm.model_name': modelId,
            'llm.input_messages.count': _conversation.length,
            'llm.tools.count': allowedTools.length,
            'input.value': redactBody(
              _conversationSummary(_conversation),
              maxBytes: 65536,
            ),
          },
        );
        final previousActive = _obs?.activeSpan;
        if (llmSpan != null) _obs!.activeSpan = llmSpan;
        var inputTokens = 0;
        var outputTokens = 0;
        var textDeltaCount = 0;

        try {
          await for (final chunk in llm.stream(
            _conversation,
            tools: allowedTools,
          )) {
            switch (chunk) {
              case TextDelta(:final text):
                textDeltaCount++;
                if (textDeltaCount == 1) {
                  llmSpan?.addEvent('llm.first_token');
                }
                assistantText.write(text);
                yield AgentTextDelta(text);
              case ToolCallStart(:final id, :final name):
                llmSpan?.addEvent('llm.tool_call.start', attributes: {
                  'tool_call.id': id,
                  'tool.name': name,
                });
                yield AgentToolCallPending(id: id, name: name);
              case ToolCallComplete(:final toolCall):
                toolCalls.add(toolCall);
                llmSpan?.addEvent('llm.tool_call.complete', attributes: {
                  'tool_call.id': toolCall.id,
                  'tool.name': toolCall.name,
                });
                final completer = Completer<ToolResult>();
                _pendingToolResults[toolCall.id] = completer;
                toolFutures.add(completer.future);
                yield AgentToolCall(toolCall);
              case UsageInfo(
                  inputTokens: final chunkInputTokens,
                  outputTokens: final chunkOutputTokens,
                ):
                tokenCount += chunkInputTokens + chunkOutputTokens;
                inputTokens += chunkInputTokens;
                outputTokens += chunkOutputTokens;
            }
          }
        } finally {
          if (_obs != null && llmSpan != null && _obs.activeSpan == llmSpan) {
            _obs.activeSpan = previousActive;
          }
          if (llmSpan != null) {
            _obs!.endSpan(llmSpan, extra: {
              'llm.token_count.prompt': inputTokens,
              'llm.token_count.completion': outputTokens,
              'llm.token_count.total': inputTokens + outputTokens,
              'llm.output_messages.count': 1,
              'llm.output_text.length': assistantText.length,
              'llm.tool_call_count': toolCalls.length,
              'output.value': redactBody(
                assistantText.toString(),
                maxBytes: 65536,
              ),
            });
          }
        }

        _conversation.add(Message.assistant(
          text: assistantText.toString(),
          toolCalls: toolCalls,
        ));

        // No tool calls → turn is complete.
        if (toolCalls.isEmpty) {
          if (iterationSpan != null) {
            _obs!.endSpan(iterationSpan, extra: {
              'agent.iteration.tool_call_count': 0,
              'agent.iteration.output_text.length': assistantText.length,
            });
          }
          break;
        }

        // Tools may have started executing as soon as they were yielded
        // above, so some futures could already be resolved by the time we
        // get here.
        final results = await Future.wait(toolFutures);

        // Add results to conversation and yield events
        for (var i = 0; i < toolCalls.length; i++) {
          _conversation.add(Message.toolResult(
            callId: toolCalls[i].id,
            content: results[i].content,
            toolName: toolCalls[i].name,
            contentParts: results[i].contentParts,
          ));
          yield AgentToolResult(results[i]);
        }
        if (iterationSpan != null) {
          _obs!.endSpan(iterationSpan, extra: {
            'agent.iteration.tool_call_count': toolCalls.length,
            'agent.iteration.output_text.length': assistantText.length,
            'agent.iteration.tool_success_count':
                results.where((r) => r.success).length,
          });
        }

        // Loop: send tool results back to the LLM.
      }

      yield AgentDone();
    } on Object catch (e, st) {
      if (_obs != null) {
        final errorSpan = _obs.startSpan(
          'agent.error',
          kind: 'error',
          attributes: {
            'error': true,
            'error.type': e.runtimeType.toString(),
            'error.message': e.toString(),
            'error.stack': st.toString(),
          },
        );
        _obs.endSpan(errorSpan);
      }
      yield AgentError(e);
    } finally {
      for (final completer in _pendingToolResults.values) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('Agent stream cancelled while awaiting tool result'),
          );
        }
      }
      _pendingToolResults.clear();
    }
  }

  /// Provides a [result] for a pending tool call.
  ///
  /// Called by the application after the user approves (or denies) a tool
  /// invocation.
  void completeToolCall(ToolResult result) {
    final completer = _pendingToolResults.remove(result.callId);
    if (completer == null || completer.isCompleted) return;
    completer.complete(result);
  }

  /// Ensures the conversation history is structurally valid for the next
  /// API call.
  ///
  /// When the user cancels (Escape) while a tool is executing, the agent's
  /// stream subscription is cancelled. This kills the generator before it
  /// reaches the code that adds tool_result messages to the conversation.
  /// The conversation is left with an assistant message containing tool_use
  /// blocks but no matching tool_result messages — which the Anthropic and
  /// OpenAI APIs reject as invalid.
  ///
  /// This method scans backwards from the end of the conversation, finds
  /// any unmatched tool_use blocks, and injects synthetic `[cancelled]`
  /// tool_result messages so the next API call succeeds.
  void ensureToolResultsComplete() {
    // Walk backwards to find the last assistant message with tool calls.
    // Skip over any tool_result messages that may already be present.
    for (var i = _conversation.length - 1; i >= 0; i--) {
      final msg = _conversation[i];

      if (msg.role == Role.toolResult) continue;

      if (msg.role == Role.assistant && msg.toolCalls.isNotEmpty) {
        final resultIdsAfter = <String>{};
        for (var j = i + 1; j < _conversation.length; j++) {
          if (_conversation[j].role == Role.toolResult) {
            final id = _conversation[j].toolCallId;
            if (id != null) resultIdsAfter.add(id);
          }
        }

        for (final tc in msg.toolCalls) {
          final alreadyHasResult = resultIdsAfter.contains(tc.id);
          if (!alreadyHasResult) {
            _conversation.add(Message.toolResult(
              callId: tc.id,
              content: '[cancelled by user]',
              toolName: tc.name,
            ));
          }
        }
        break;
      }

      // Hit a user message or something else — no unmatched tool_use.
      break;
    }
  }

  /// Executes a [call] directly using the registered tool.
  Future<ToolResult> executeTool(ToolCall call) async {
    final tool = tools[call.name];
    if (tool == null) {
      return ToolResult(
        callId: call.id,
        content: 'Unknown tool: ${call.name}',
        success: false,
      );
    }

    ObservabilitySpan? span;
    if (_obs != null) {
      final encodedArgs = jsonEncode(call.arguments);
      span = _obs.startSpan(
        'tool.${call.name}',
        kind: 'tool',
        parent: _traceParent,
        attributes: {
          'openinference.span.kind': 'TOOL',
          'tool_call.id': call.id,
          'tool.name': call.name,
          'tool.input_size': encodedArgs.length,
          'tool.input': redactBody(encodedArgs, maxBytes: 65536),
          'input.value': redactBody(encodedArgs, maxBytes: 65536),
        },
      );
    }
    final stopwatch = Stopwatch()..start();

    try {
      final result = await tool.execute(call.arguments);
      stopwatch.stop();
      if (span != null) {
        _obs!.endSpan(span, extra: {
          'tool.duration_ms': stopwatch.elapsedMilliseconds,
          'tool.success': true,
          'tool.output': redactBody(result.content, maxBytes: 65536),
          'output.value': redactBody(result.content, maxBytes: 65536),
          if (result.summary != null) 'tool.summary': result.summary,
          if (result.metadata.isNotEmpty)
            'tool.metadata': jsonEncode(result.metadata),
        });
      }
      return result.withCallId(call.id);
    } catch (e, st) {
      stopwatch.stop();
      if (span != null) {
        _obs!.endSpan(span, extra: {
          'tool.duration_ms': stopwatch.elapsedMilliseconds,
          'tool.success': false,
          'error': true,
          'error.type': e.runtimeType.toString(),
          'error.message': e.toString(),
          'error.stack': st.toString(),
        });
      }
      return ToolResult(
        callId: call.id,
        content: 'Tool error: $e',
        success: false,
      );
    }
  }
}

String _conversationSummary(List<Message> messages) {
  final out = <Map<String, dynamic>>[];
  for (final message in messages) {
    out.add({
      'role': message.role.name,
      if (message.text != null) 'text': message.text,
      if (message.toolCalls.isNotEmpty)
        'tool_calls': [
          for (final call in message.toolCalls)
            {
              'id': call.id,
              'name': call.name,
              'arguments': call.arguments,
            }
        ],
      if (message.toolCallId != null) 'tool_call_id': message.toolCallId,
      if (message.toolName != null) 'tool_name': message.toolName,
    });
  }
  return jsonEncode(out);
}
