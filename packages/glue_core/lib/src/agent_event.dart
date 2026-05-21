/// Events emitted by the agent loop that the surface (UI, ACP, web)
/// subscribes to.
///
/// **Status:** part of the proposed core data model — see
/// `docs/plans/2026-04-29-harness-layers.md`. Originally lived in
/// `agent/agent_core.dart`. This is the *current* agent-event vocabulary;
/// the richer [SessionEvent] hierarchy in `session_event.dart` is the
/// proposed future contract.
library;

import 'package:glue_core/src/ids.dart';
import 'package:glue_core/src/message.dart';
import 'package:glue_core/src/tool.dart';

/// Events emitted by the agent that the UI subscribes to.
sealed class AgentEvent {}

/// A delta of generated text forwarded to the UI.
class AgentTextDelta extends AgentEvent {
  final String delta;
  AgentTextDelta(this.delta);
}

/// A delta of streaming reasoning/"thinking" content forwarded to the
/// UI. Only emitted by reasoning-capable models. Renderers should style
/// this distinctly from [AgentTextDelta] (typically dim + italic) so
/// users see the reasoning as an aside, not as the final answer.
class AgentThinkingDelta extends AgentEvent {
  final String delta;
  AgentThinkingDelta(this.delta);
}

/// Notification that a tool call is being prepared.
class AgentToolCallPending extends AgentEvent {
  final ToolCallId id;
  final String name;
  AgentToolCallPending({required this.id, required this.name});
}

/// A fully-formed tool call ready for execution.
class AgentToolCall extends AgentEvent {
  final ToolCall call;
  AgentToolCall(this.call);
}

/// The result of an executed tool call.
class AgentToolResult extends AgentEvent {
  final ToolResult result;
  AgentToolResult(this.result);
}

/// Signals that the agent has finished its response.
class AgentDone extends AgentEvent {}

/// Token usage reported by the LLM for one call. Forwarded as an
/// [AgentEvent] so [AgentRunner], surfaces, and the session log can
/// aggregate per-call costs without poking inside [AgentCore].
class AgentUsage extends AgentEvent {
  final UsageInfo usage;
  AgentUsage(this.usage);
}

/// An error encountered during the agent loop.
class AgentError extends AgentEvent {
  final Object error;
  AgentError(this.error);
}

/// Non-fatal informational message addressed to the user via the
/// transcript surface. Use for soft-degradation announcements — e.g.
/// "tools disabled for this session because the model doesn't support
/// them" — where the agent loop kept running but the user should know
/// something changed.
///
/// **Every new surface (TUI, ACP, JSON, print) must learn to render
/// this** — it's not optional. The fallback behaviour is to skip the
/// notice silently, which masks soft degradation from users.
class AgentNotice extends AgentEvent {
  AgentNotice(this.message, {this.kind = 'info'});

  /// Single-line human-readable text. No leading marker glyph — surfaces
  /// add their own (TUI uses `markerInfo`/`markerWarn`, --print uses
  /// `! ` on stderr).
  final String message;

  /// `info` (default) for "FYI" messages, `warning` for soft-degradation
  /// announcements the user should react to. Forward-compatible string
  /// rather than an enum so adding new kinds doesn't break compile.
  final String kind;
}
