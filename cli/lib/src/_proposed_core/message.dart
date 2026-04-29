/// Conversation message types and the streaming/agent event vocabulary
/// shared between the agent loop and the LLM strategies.
///
/// **Status:** part of the proposed core data model — see
/// `docs/plans/2026-04-29-harness-layers.md`. Originally lived in
/// `agent/agent_core.dart`; relocated so strategies (LLM clients,
/// providers) can depend on these types without violating the layer rule.
///
/// The agent loop class itself ([AgentCore]) stays in `agent/`.
library;

import 'package:glue/src/_proposed_core/content_part.dart';
import 'package:glue/src/_proposed_core/ids.dart';

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
    required ToolCallId callId,
    required String content,
    String? toolName,
    List<ContentPart>? contentParts,
  }) =>
      Message._(
          role: Role.toolResult,
          text: content,
          toolCallId: callId.value,
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
  final ToolCallId id;
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
  final ToolCallId id;
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
