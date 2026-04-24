/// Core LLM streaming types: the [LlmClient] interface and the [LlmChunk]
/// sealed family every provider yields.
///
/// Moved out of `agent/agent.dart` so that provider packages can depend on
/// the streaming contract without pulling in the full agent loop.
library;

import 'package:glue/src/agent/agent.dart' show Message, ToolCall;
import 'package:glue/src/agent/tools.dart';

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
