import 'dart:async';

import 'package:glue/src/agent/tools.dart';

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
  }) =>
      Message._(
          role: Role.toolResult,
          text: content,
          toolCallId: callId,
          toolName: toolName);
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

/// Emitted as soon as a tool call begins (name/ID known, arguments still
/// streaming). Not all providers emit this — Ollama delivers fully formed
/// tool calls without incremental streaming.
class ToolCallStart extends LlmChunk {
  final String id;
  final String name;
  ToolCallStart({required this.id, required this.name});
}

/// A completed tool call requested by the model (arguments fully parsed).
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

class AgentToolCallPending extends AgentEvent {
  final String id;
  final String name;
  AgentToolCallPending({required this.id, required this.name});
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
  LlmClient llm;
  final Map<String, Tool> tools;
  final String modelName;
  final List<Message> _conversation = [];
  int tokenCount = 0;

  /// Completers keyed by tool call ID for parallel tool execution.
  final Map<String, Completer<ToolResult>> _pendingToolResults = {};

  AgentCore(
      {required this.llm, required this.tools, this.modelName = 'unknown'});

  /// The full conversation history.
  List<Message> get conversation => List.unmodifiable(_conversation);

  /// Add a message directly to the conversation history (for session resume).
  void addMessage(Message message) => _conversation.add(message);

  /// Run a [userMessage] through the agent loop.
  ///
  /// Returns a stream of [AgentEvent]s that the UI subscribes to.
  Stream<AgentEvent> run(String userMessage) async* {
    _conversation.add(Message.user(userMessage));

    try {
      while (true) {
        final assistantText = StringBuffer();
        final toolCalls = <ToolCall>[];
        final toolFutures = <Future<ToolResult>>[];

        await for (final chunk in llm.stream(
          _conversation,
          tools: tools.values.toList(),
        )) {
          switch (chunk) {
            case TextDelta(:final text):
              assistantText.write(text);
              yield AgentTextDelta(text);
            case ToolCallStart(:final id, :final name):
              yield AgentToolCallPending(id: id, name: name);
            case ToolCallDelta(:final toolCall):
              toolCalls.add(toolCall);
              final completer = Completer<ToolResult>();
              _pendingToolResults[toolCall.id] = completer;
              toolFutures.add(completer.future);
              yield AgentToolCall(toolCall);
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

        // Wait for all results (some may already be completed if
        // auto-approved tools started executing during streaming).
        final results = await Future.wait(toolFutures);

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

  /// Ensure the conversation history is structurally valid for the next
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
  /// any unmatched tool_use blocks, and injects synthetic "[cancelled]"
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
