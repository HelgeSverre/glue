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
import 'package:glue_server/src/acp/content.dart';
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

/// Builds the `content[]` array for a `tool_call_update` notification
/// from an [AgentEvent]-era [ToolResult].
///
/// Priority order:
///   1. `result.metadata['diff']` (path/old_text/new_text) — emit a
///      `diff` content block so editors render a real diff view.
///   2. `result.contentParts` — multimodal output (text, images,
///      resource links) flows through unchanged.
///   3. Fallback: a single `text` block derived from
///      [ToolResult.summary] or [ToolResult.content].
///
/// (1) and (2) compose: a write_file result whose contentParts include
/// e.g. a confirmation TextPart still gets the diff block first, then
/// the text parts after.
List<AcpToolCallContent> toolResultContent(ToolResult result) {
  final out = <AcpToolCallContent>[];

  // Diff metadata (write_file / edit_file).
  final diffRaw = result.metadata['diff'];
  if (diffRaw is Map) {
    final diff = diffRaw.cast<String, Object?>();
    final path = diff['path'];
    final oldText = diff['old_text'];
    final newText = diff['new_text'];
    if (path is String && oldText is String && newText is String) {
      out.add(AcpToolCallDiff(path: path, oldText: oldText, newText: newText));
    }
  }

  // Multimodal content parts.
  final parts = result.contentParts;
  if (parts != null && parts.isNotEmpty) {
    for (final part in parts) {
      out.add(AcpToolCallContentValue(AcpContentBlock.fromContentPart(part)));
    }
    return out;
  }

  if (out.isEmpty) {
    // No diff, no parts — fall back to a single text block.
    out.add(
      AcpToolCallContentValue(AcpTextBlock(result.summary ?? result.content)),
    );
  }
  return out;
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
