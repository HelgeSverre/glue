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
  Stream<LlmChunk> stream(
    List<Message> messages, {
    List<Tool>? tools,
  });
}
