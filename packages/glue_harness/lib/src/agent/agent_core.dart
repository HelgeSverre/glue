import 'dart:async';
import 'dart:convert';

import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/src/observability/observability.dart';
import 'package:glue_harness/src/observability/redaction.dart';

// Re-export the data types and event vocabulary that were originally
// declared here. Consumers that import this file continue to get the
// same names; the types now live in `_proposed_core/` so strategies can
// depend on them without crossing the harness layer.
export 'package:glue_core/src/agent_event.dart';
export 'package:glue_core/src/content_part.dart';
export 'package:glue_core/src/llm_client.dart';
export 'package:glue_core/src/message.dart';
export 'package:glue_core/src/tool.dart' show Tool;

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

  /// Cumulative usage across every LLM call this core has run. Surfaces
  /// (CLI status bar, ACP `session/usage_summary`, tests) read it
  /// directly via [stats]. The old `tokenCount` field has been removed —
  /// it counted only `input + output` and undercounted heavy-cache
  /// sessions, which the status bar then displayed in conflict with
  /// `/usage`. Use `stats.totalTokens` for the all-buckets total or
  /// `stats.billedInputTokens` to compute hit rate.
  final UsageStats stats = UsageStats();

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
  final Map<ToolCallId, Completer<ToolResult>> _pendingToolResults = {};

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
  /// Pass [userContentParts] for multimodal input (images, resource
  /// links) — the LLM mappers will serialise them per provider.
  Stream<AgentEvent> run(
    String userMessage, {
    List<ContentPart>? userContentParts,
  }) async* {
    _conversation.add(
      Message.user(userMessage, contentParts: userContentParts),
    );

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
        var cacheReadTokens = 0;
        var cacheCreationTokens = 0;
        var sawCacheStats = false;
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
              case ThinkingDelta(:final text):
                // Forward but do NOT append to assistantText. Thinking
                // content stays out of the conversation history we send
                // back to the model.
                yield AgentThinkingDelta(text);
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
              case final UsageInfo usage:
                stats.record(usage);
                inputTokens += usage.inputTokens;
                outputTokens += usage.outputTokens;
                if (usage.cacheReadTokens != null) {
                  cacheReadTokens += usage.cacheReadTokens!;
                  sawCacheStats = true;
                }
                if (usage.cacheCreationTokens != null) {
                  cacheCreationTokens += usage.cacheCreationTokens!;
                  sawCacheStats = true;
                }
                yield AgentUsage(usage);
            }
          }
        } finally {
          if (_obs != null && llmSpan != null && _obs.activeSpan == llmSpan) {
            _obs.activeSpan = previousActive;
          }
          if (llmSpan != null) {
            // Cache savings: cached_read_tokens are billed at ~10× discount
            // on Anthropic and ~50% on OpenAI. The percentage we surface is
            // a coarse "fraction of effective input served from cache" —
            // useful for spotting drops in hit rate, not for billing math.
            final billableInput = inputTokens + cacheReadTokens;
            final cacheSavingsPct = (sawCacheStats && billableInput > 0)
                ? (cacheReadTokens * 100 / billableInput)
                : 0.0;
            _obs!.endSpan(llmSpan, extra: {
              'llm.token_count.prompt': inputTokens,
              'llm.token_count.completion': outputTokens,
              'llm.token_count.total': inputTokens + outputTokens,
              'llm.output_messages.count': 1,
              'llm.output_text.length': assistantText.length,
              'llm.tool_call_count': toolCalls.length,
              if (sawCacheStats) 'llm.cache_read_tokens': cacheReadTokens,
              if (sawCacheStats)
                'llm.cache_creation_tokens': cacheCreationTokens,
              if (sawCacheStats)
                'llm.cache_savings_pct':
                    double.parse(cacheSavingsPct.toStringAsFixed(1)),
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
        final resultIdsAfter = <ToolCallId>{};
        for (var j = i + 1; j < _conversation.length; j++) {
          if (_conversation[j].role == Role.toolResult) {
            final id = _conversation[j].toolCallId;
            if (id != null) resultIdsAfter.add(ToolCallId(id));
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
