/// Maps Glue's *current* [AgentEvent] vocabulary into ACP `session/update`
/// payloads.
///
/// This is the translation the ACP server uses today, while the proposed
/// [SessionEvent] hierarchy in glue_core is wired through the harness.
/// Once the harness emits [SessionEvent] directly, this mapper can be
/// retired in favour of `event_mapping.dart`'s SessionEvent variant.
///
/// Tool-call events here only carry the *visible* side of the loop — the
/// server is responsible for synthesising tool-call status updates
/// (`pending` → `in_progress` → `completed`/`failed`) around its own
/// permission gate and execution.
library;

import 'package:glue_core/glue_core.dart';
import 'package:glue_server/src/acp/messages.dart';

/// Maps a single [AgentEvent] to a [SessionUpdate], or returns `null`
/// when the event has no `session/update` representation today (the
/// server handles tool-call status separately).
SessionUpdate? agentEventToAcpUpdate(AgentEvent event) {
  return switch (event) {
    AgentTextDelta(:final delta) => AgentMessageChunkUpdate(delta),
    AgentThinkingDelta() =>
      null, // ACP `agent_thought_chunk` mapping is a phase-2 follow-up
    AgentToolCallPending() => null, // server emits tool_call(pending) itself
    AgentToolCall() => null, // server emits tool_call(in_progress) itself
    AgentToolResult() => null, // server emits tool_call_update itself
    AgentUsage() =>
      null, // surfaced via session/usage_summary, not session/update
    AgentDone() => null, // server returns SessionPromptResult
    AgentError() => null, // server emits a JSON-RPC error
    AgentNotice(:final message, :final kind) =>
      // Soft-degradation announcement. Surfaced through the
      // agent-message-chunk channel with a leading marker glyph so ACP
      // clients see it inline in the transcript. Glyph mirrors the TUI
      // and --print-mode surfaces.
      AgentMessageChunkUpdate('${kind == 'warning' ? '!' : '·'} $message\n'),
  };
}

/// Maps Glue's [Tool] kind heuristic (by tool name) onto ACP's
/// [ToolCallKind] enum. Falls back to [ToolCallKind.other] for unknown
/// tools.
ToolCallKind toolNameToAcpKind(String toolName) {
  return switch (toolName) {
    'read_file' || 'list_directory' => ToolCallKind.read,
    'grep' => ToolCallKind.search,
    'write_file' || 'edit_file' => ToolCallKind.edit,
    'bash' => ToolCallKind.execute,
    'web_fetch' || 'web_search' || 'web_browser' => ToolCallKind.fetch,
    _ => ToolCallKind.other,
  };
}
