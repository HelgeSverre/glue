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

import 'package:glue_core/src/content_part.dart';
import 'package:glue_core/src/ids.dart';

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

  /// Build a user message. Pass [contentParts] for multimodal input
  /// (text + images + resource links) — the LLM mappers will serialise
  /// them per provider, falling back to [text] for clients that don't
  /// support multimodal input.
  factory Message.user(String text, {List<ContentPart>? contentParts}) =>
      Message._(role: Role.user, text: text, contentParts: contentParts);

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
  }) => Message._(
    role: Role.toolResult,
    text: content,
    toolCallId: callId.value,
    toolName: toolName,
    contentParts: contentParts,
  );
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

/// A delta of streaming reasoning/"thinking" content. Distinct from
/// [TextDelta] so renderers can style it as deliberative-aside rather
/// than final assistant output.
///
/// Only reasoning-capable models emit this — Claude 4.x with extended
/// thinking, GPT-5 / o-series, DeepSeek R1, QwQ, etc. Parsers that don't
/// see thinking blocks simply never yield this variant.
///
/// Thinking content is **not** appended to the assistant message that
/// gets sent back to the model on the next turn — Anthropic explicitly
/// forbids this without the right block structure, and including it
/// would pollute context for other providers.
class ThinkingDelta extends LlmChunk {
  final String text;
  ThinkingDelta(this.text);
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
///
/// [cacheReadTokens] and [cacheCreationTokens] surface provider-native
/// prompt caching statistics when available. Both are nullable: `null`
/// means the provider did not report the field (e.g. Ollama, or a cache
/// miss on a provider that omits zeroed fields). Distinguish "not
/// reported" from "reported as zero" — that distinction is the difference
/// between a passive read and an unsupported provider.
///
/// `inputTokens` reflects only the **uncached** input tokens billed at
/// the provider's standard rate. Cache reads are billed separately
/// (Anthropic: 0.1× input price; OpenAI: ~50% discount). Total billed
/// input across the request is roughly:
///   `inputTokens + (cacheReadTokens ?? 0) + (cacheCreationTokens ?? 0)`.
class UsageInfo extends LlmChunk {
  final int inputTokens;
  final int outputTokens;
  final int? cacheReadTokens;
  final int? cacheCreationTokens;

  UsageInfo({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheReadTokens,
    this.cacheCreationTokens,
  });

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

  /// Provider-specific opaque token that must be echoed back on the next
  /// request. Currently set only by the Gemini provider when the model is in
  /// thinking mode; null for all other providers. See
  /// https://ai.google.dev/gemini-api/docs/thought-signatures.
  final String? thoughtSignature;

  ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.description = '',
    this.thoughtSignature,
  });
}
