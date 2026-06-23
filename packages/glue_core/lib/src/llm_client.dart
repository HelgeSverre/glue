/// Abstract LLM client interface — wraps any provider (Anthropic, OpenAI, …).
///
/// **Status:** part of the proposed core data model — see
/// `docs/plans/2026-04-29-harness-layers.md`. Originally lived in
/// `agent/agent_core.dart`; relocated so strategies (LLM clients,
/// providers) can implement this contract without crossing the harness
/// boundary.
library;

import 'package:glue_core/src/message.dart';
import 'package:glue_core/src/tool.dart';

/// Abstract LLM client — wraps any provider (Anthropic, OpenAI, etc.).
///
/// Implementations stream [LlmChunk]s for a given conversation and optional
/// tool definitions.
abstract class LlmClient {
  /// Streams a response for the given [messages].
  ///
  /// If [tools] are provided the model may emit [ToolCallComplete] chunks.
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools});
}

/// Optional capability for an [LlmClient] that knows its model's effective
/// context window. Kept separate from [LlmClient] (rather than a member with
/// a default) because clients use `implements LlmClient`, which would force
/// every client to redeclare the member. Only clients that can resolve a
/// window — today just Ollama — opt in; the context-occupancy gauge
/// type-checks for this and uses the catalog window otherwise.
abstract interface class ContextWindowAware {
  /// The model's effective context window in tokens, or `null` when not yet
  /// resolved / unknown.
  int? get contextWindow;
}

/// Thrown by an [LlmClient] when the underlying model rejects a request
/// for trying to use tool calling on a model that doesn't support it.
///
/// Today Ollama is the only provider that exposes models lacking tool
/// calling — its `/api/chat` endpoint returns
/// `400 {"error":"<model> does not support tools"}` on the first turn
/// that includes a `tools` array. `OllamaClient` recognises that exact
/// shape and rethrows this typed exception. Other adapters may grow
/// the same throw if they ever expose tool-less models.
///
/// `AgentCore` catches this, sets its [Tool] filter to reject everything,
/// emits a one-time notice, and retries the turn in chat-only mode —
/// the user keeps their session rather than crashing on turn one.
class ToolsNotSupportedException implements Exception {
  const ToolsNotSupportedException(this.modelId);

  /// The API id of the model that rejected tools — e.g. `qwen2.5:7b`.
  final String modelId;

  @override
  String toString() =>
      'ToolsNotSupportedException: model "$modelId" does not support '
      'tool calling';
}
