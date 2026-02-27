import 'dart:async';

import 'tools.dart';

// ---------------------------------------------------------------------------
// Message types for the conversation history
// ---------------------------------------------------------------------------

/// Role of a message in the conversation.
enum Role { user, assistant, toolResult }

/// A single message in the conversation history.
class Message {
  final Role role;
  final String? text;
  final List<ToolCall> toolCalls;
  final String? toolCallId;
  final String? toolName;

  const Message._({
    required this.role,
    this.text,
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
  });

  factory Message.user(String text) =>
      Message._(role: Role.user, text: text);

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
  }) =>
      Message._(role: Role.toolResult, text: content, toolCallId: callId, toolName: toolName);
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

/// A tool call requested by the model.
class ToolCallDelta extends LlmChunk {
  final ToolCall toolCall;
  ToolCallDelta(this.toolCall);
}

/// Token usage information.
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

/// The result of executing a tool.
class ToolResult {
  final String callId;
  final String content;
  final bool success;

  ToolResult({
    required this.callId,
    required this.content,
    this.success = true,
  });

  factory ToolResult.denied(String callId) => ToolResult(
        callId: callId,
        content: 'User denied tool execution',
        success: false,
      );
}

// ---------------------------------------------------------------------------
// Abstract LLM client
// ---------------------------------------------------------------------------

/// Abstract LLM client — wraps any provider (Anthropic, OpenAI, etc.).
///
/// Implementations stream [LlmChunk]s for a given conversation and optional
/// tool definitions.
abstract class LlmClient {
  /// Stream a response for the given [messages].
  ///
  /// If [tools] are provided the model may emit [ToolCallDelta] chunks.
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

class AgentTextDelta extends AgentEvent {
  final String delta;
  AgentTextDelta(this.delta);
}

class AgentToolCall extends AgentEvent {
  final ToolCall call;
  AgentToolCall(this.call);
}

class AgentToolResult extends AgentEvent {
  final ToolResult result;
  AgentToolResult(this.result);
}

class AgentDone extends AgentEvent {}

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
  final LlmClient llm;
  final Map<String, Tool> tools;
  final String modelName;
  final List<Message> _conversation = [];
  int tokenCount = 0;

  /// Completers keyed by tool call ID for parallel tool execution.
  final Map<String, Completer<ToolResult>> _pendingToolResults = {};

  AgentCore({required this.llm, required this.tools, this.modelName = 'unknown'});

  /// The full conversation history.
  List<Message> get conversation => List.unmodifiable(_conversation);

  /// Run a [userMessage] through the agent loop.
  ///
  /// Returns a stream of [AgentEvent]s that the UI subscribes to.
  Stream<AgentEvent> run(String userMessage) async* {
    _conversation.add(Message.user(userMessage));

    try {
      while (true) {
        final assistantText = StringBuffer();
        final toolCalls = <ToolCall>[];

        await for (final chunk in llm.stream(
          _conversation,
          tools: tools.values.toList(),
        )) {
          switch (chunk) {
            case TextDelta(:final text):
              assistantText.write(text);
              yield AgentTextDelta(text);
            case ToolCallDelta(:final toolCall):
              toolCalls.add(toolCall);
            case UsageInfo(:final totalTokens):
              tokenCount += totalTokens;
          }
        }

        _conversation.add(Message.assistant(
          text: assistantText.toString(),
          toolCalls: toolCalls,
        ));

        // No tool calls → turn is complete.
        if (toolCalls.isEmpty) break;

        // Create completers and capture futures before yielding
        final futures = <Future<ToolResult>>[];
        for (final call in toolCalls) {
          final completer = Completer<ToolResult>();
          _pendingToolResults[call.id] = completer;
          futures.add(completer.future);
        }

        // Emit all tool calls
        for (final call in toolCalls) {
          yield AgentToolCall(call);
        }

        // Wait for all results
        final results = await Future.wait(futures);

        // Add results to conversation and yield events
        for (var i = 0; i < toolCalls.length; i++) {
          _conversation.add(Message.toolResult(
            callId: toolCalls[i].id,
            content: results[i].content,
            toolName: toolCalls[i].name,
          ));
          yield AgentToolResult(results[i]);
        }

        // Loop: send tool results back to the LLM.
      }

      yield AgentDone();
    } on Object catch (e) {
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

  /// Provide a [result] for a pending tool call.
  ///
  /// Called by the application after the user approves (or denies) a tool
  /// invocation.
  void completeToolCall(ToolResult result) {
    final completer = _pendingToolResults.remove(result.callId);
    if (completer == null || completer.isCompleted) return;
    completer.complete(result);
  }

  /// Execute a [call] directly using the registered tool.
  Future<ToolResult> executeTool(ToolCall call) async {
    final tool = tools[call.name];
    if (tool == null) {
      return ToolResult(
        callId: call.id,
        content: 'Unknown tool: ${call.name}',
        success: false,
      );
    }
    try {
      final output = await tool.execute(call.arguments);
      return ToolResult(callId: call.id, content: output);
    } catch (e) {
      return ToolResult(
        callId: call.id,
        content: 'Tool error: $e',
        success: false,
      );
    }
  }
}
