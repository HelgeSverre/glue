/// Sealed event hierarchy emitted by a running session.
///
/// **Status:** proposed (PR 2 of harness-layers plan). Not yet wired to
/// consumers — see `docs/plans/2026-04-29-harness-layers.md`.
///
/// Design properties encoded here:
///
/// 1. **Permission and OAuth are events, not callbacks.** The agent emits
///    [PermissionRequestedEvent] and the surface responds via
///    `session.dispatch(ResolvePermissionCommand(...))`. Same for device-code
///    OAuth. The agent never imports surface code.
///
/// 2. **Subagents emit forwarded events.** [SubagentEventForwardedEvent]
///    carries an inner event. Surfaces decide whether to render inline
///    (CLI does this) or in a separate pane (web could).
///
/// 3. **Sequence numbers are mandatory.** Every event has a monotonic
///    per-session [SessionEvent.sequence]. This is what makes "snapshot +
///    subscribe" work without missing or duplicating events.
library;

import 'package:glue/src/_proposed_core/ids.dart';

/// Base type for all events emitted by a [Session].
///
/// Pattern-match with `switch` to handle each variant:
/// ```dart
/// switch (event) {
///   AssistantChunkEvent(:final delta) => render(delta),
///   PermissionRequestedEvent() => showPermissionUi(event),
///   _ => null,
/// }
/// ```
sealed class SessionEvent {
  const SessionEvent({
    required this.turnId,
    required this.timestamp,
    required this.sequence,
  });

  /// The turn this event belongs to. A turn is one user-message →
  /// assistant-response cycle (which may include many tool calls).
  final TurnId turnId;

  /// Wall-clock time the event was produced.
  final DateTime timestamp;

  /// Monotonic per-session sequence number. Surfaces use this to resume
  /// from a known position without missing or duplicating events.
  final int sequence;
}

// ---------------------------------------------------------------------------
// Conversation events
// ---------------------------------------------------------------------------

/// User-authored input dispatched into a session.
class UserMessageEvent extends SessionEvent {
  const UserMessageEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.text,
    this.attachments = const [],
    this.fileRefs = const [],
  });

  final String text;
  final List<Attachment> attachments;

  /// `@file` expansions resolved at dispatch time.
  final List<FileReference> fileRefs;
}

/// The model has begun producing thinking tokens (if exposed).
class AssistantThinkingStartedEvent extends SessionEvent {
  const AssistantThinkingStartedEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
  });
}

/// A streamed delta from the model — text, thinking, or tool-call args.
class AssistantChunkEvent extends SessionEvent {
  const AssistantChunkEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.delta,
    required this.kind,
  });

  final String delta;
  final ChunkKind kind;
}

/// The model finished producing a complete assistant message for this turn.
class AssistantMessageEvent extends SessionEvent {
  const AssistantMessageEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.text,
    required this.usage,
    required this.elapsed,
  });

  final String text;
  final TokenUsage usage;
  final Duration elapsed;
}

/// The model finished producing thinking tokens.
class AssistantThinkingCompletedEvent extends SessionEvent {
  const AssistantThinkingCompletedEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.usage,
    this.summary,
  });

  /// Some providers expose a thinking summary; null if not.
  final String? summary;
  final TokenUsage usage;
}

// ---------------------------------------------------------------------------
// Tool events
// ---------------------------------------------------------------------------

/// A tool call has begun executing (after permission, if applicable).
class ToolCallStartedEvent extends SessionEvent {
  const ToolCallStartedEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.id,
    required this.tool,
    required this.args,
    required this.kind,
  });

  final ToolCallId id;
  final String tool;
  final Map<String, Object?> args;
  final ToolKind kind;
}

/// Optional progress update emitted while a tool is running.
class ToolCallProgressEvent extends SessionEvent {
  const ToolCallProgressEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.id,
    required this.message,
    this.percentComplete,
  });

  final ToolCallId id;
  final String message;
  final double? percentComplete;
}

/// A tool call finished — either successfully, with an error, or cancelled.
class ToolCallCompletedEvent extends SessionEvent {
  const ToolCallCompletedEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.id,
    required this.result,
    required this.elapsed,
  });

  final ToolCallId id;
  final ToolResultSnapshot result;
  final Duration elapsed;
}

// ---------------------------------------------------------------------------
// Permission events (was a callback, is now data)
// ---------------------------------------------------------------------------

/// The agent needs the user's permission to proceed with a tool call.
///
/// The surface responds by dispatching a `ResolvePermissionCommand` with
/// the same [requestId].
class PermissionRequestedEvent extends SessionEvent {
  const PermissionRequestedEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.requestId,
    required this.toolCallId,
    required this.scope,
    required this.summary,
    required this.dangerLevel,
  });

  final PermissionRequestId requestId;
  final ToolCallId toolCallId;
  final PermissionScope scope;
  final String summary;
  final ToolKind dangerLevel;
}

/// The user resolved a pending permission request.
class PermissionResolvedEvent extends SessionEvent {
  const PermissionResolvedEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.requestId,
    required this.granted,
    required this.appliedScope,
  });

  final PermissionRequestId requestId;
  final bool granted;
  final PermissionScope appliedScope;
}

// ---------------------------------------------------------------------------
// Subagent events
// ---------------------------------------------------------------------------

/// The agent spawned a subagent. Subsequent events from that subagent
/// arrive wrapped in [SubagentEventForwardedEvent].
class SubagentSpawnedEvent extends SessionEvent {
  const SubagentSpawnedEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.childId,
    required this.childSessionId,
    required this.task,
    required this.model,
  });

  final SubagentId childId;
  final SessionId childSessionId;
  final String task;
  final ModelRef model;
}

/// An event emitted by a subagent, forwarded to the parent stream.
///
/// Surfaces choose to render [inner] inline (CLI today) or in a separate
/// pane (a future web client could).
class SubagentEventForwardedEvent extends SessionEvent {
  const SubagentEventForwardedEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.childId,
    required this.inner,
  });

  final SubagentId childId;
  final SessionEvent inner;
}

/// A subagent finished — emitted on the parent stream.
class SubagentCompletedEvent extends SessionEvent {
  const SubagentCompletedEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.childId,
    required this.usage,
    required this.elapsed,
    this.finalMessage,
  });

  final SubagentId childId;
  final String? finalMessage;
  final TokenUsage usage;
  final Duration elapsed;
}

// ---------------------------------------------------------------------------
// Auth events (was a callback, is now data)
// ---------------------------------------------------------------------------

/// A device-code OAuth flow has produced a code the user must enter.
///
/// The surface displays [code] + [verificationUrl], waits for the user to
/// complete the flow in their browser, and dispatches
/// `ResolveDeviceCodeCommand`.
class DeviceCodeRequestedEvent extends SessionEvent {
  const DeviceCodeRequestedEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.code,
    required this.verificationUrl,
    required this.expiresIn,
  });

  final String code;
  final String verificationUrl;
  final Duration expiresIn;
}

/// The OAuth flow completed (success or failure).
class DeviceCodeResolvedEvent extends SessionEvent {
  const DeviceCodeResolvedEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.success,
    this.errorMessage,
  });

  final bool success;
  final String? errorMessage;
}

// ---------------------------------------------------------------------------
// Lifecycle events
// ---------------------------------------------------------------------------

/// A new turn started.
class TurnStartedEvent extends SessionEvent {
  const TurnStartedEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.model,
  });

  /// Equal to [SessionEvent.turnId]; included for ergonomics in switch arms.
  TurnId get id => turnId;

  final ModelRef model;
}

/// The current turn finished — completed normally, was interrupted, or
/// errored.
class TurnCompletedEvent extends SessionEvent {
  const TurnCompletedEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.outcome,
    required this.usage,
  });

  TurnId get id => turnId;

  final TurnOutcome outcome;
  final TokenUsage usage;
}

/// The session's high-level status changed.
class StatusChangeEvent extends SessionEvent {
  const StatusChangeEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.from,
    required this.to,
  });

  final SessionStatus from;
  final SessionStatus to;
}

/// A title was generated for this session (typically after the first turn).
class TitleGeneratedEvent extends SessionEvent {
  const TitleGeneratedEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.title,
  });

  final String title;
}

/// Session metrics were refreshed.
class MetricsUpdatedEvent extends SessionEvent {
  const MetricsUpdatedEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.current,
  });

  final SessionMetricsSnapshot current;
}

/// An error occurred. May or may not be recoverable.
class ErrorEvent extends SessionEvent {
  const ErrorEvent({
    required super.turnId,
    required super.timestamp,
    required super.sequence,
    required this.message,
    required this.category,
    required this.recoverable,
    this.stackTrace,
  });

  final String message;
  final ErrorCategory category;
  final bool recoverable;

  /// Null in production builds.
  final StackTrace? stackTrace;
}

// ---------------------------------------------------------------------------
// Supporting value types
// ---------------------------------------------------------------------------

/// A non-text input attached to a user message.
class Attachment {
  const Attachment({
    required this.kind,
    required this.bytes,
    this.mimeType,
    this.filename,
  });

  final AttachmentKind kind;
  final List<int> bytes;
  final String? mimeType;
  final String? filename;
}

enum AttachmentKind { image, pdf, text, binary }

/// A reference to a file in the project (the result of `@file` expansion).
class FileReference {
  const FileReference({
    required this.path,
    required this.absolutePath,
    this.lineRange,
  });

  final String path;
  final String absolutePath;

  /// Optional `@file:start-end` line restriction.
  final ({int start, int end})? lineRange;
}

class TokenUsage {
  const TokenUsage({
    required this.promptTokens,
    required this.completionTokens,
    this.cachedTokens = 0,
    this.estimatedCostUsd = 0.0,
  });

  final int promptTokens;
  final int completionTokens;

  /// Tokens served from prompt cache (provider-dependent).
  final int cachedTokens;

  /// Cost estimate in USD. May be 0.0 when pricing is unavailable.
  final double estimatedCostUsd;
}

class SessionMetricsSnapshot {
  const SessionMetricsSnapshot({
    required this.turnCount,
    required this.usage,
    required this.totalElapsed,
  });

  final int turnCount;
  final TokenUsage usage;
  final Duration totalElapsed;
}

enum ChunkKind { text, thinking, toolCallArgs }

enum ToolKind { read, write, exec, network, meta }

enum SessionStatus {
  idle,
  thinking,
  callingTool,
  awaitingPermission,
  completed,
  error,
}

enum TurnOutcome { completed, interrupted, errored }

enum ErrorCategory { provider, tool, runtime, internal }

/// How long a permission grant applies.
enum PermissionScope {
  /// Just this one tool call.
  singleCall,

  /// All subsequent calls of the same tool kind in this session.
  session,

  /// Persisted to the project's settings — applies to all future sessions.
  persistent,
}

/// A serializable snapshot of a [ToolCall]'s outcome. The runtime tool
/// result type lives elsewhere; this is the on-the-wire / on-disk shape.
sealed class ToolResultSnapshot {
  const ToolResultSnapshot({required this.id, required this.elapsed});
  final ToolCallId id;
  final Duration elapsed;
}

class ToolOkSnapshot extends ToolResultSnapshot {
  const ToolOkSnapshot({
    required super.id,
    required super.elapsed,
    required this.contentSummary,
  });

  /// Human-readable summary; the full content is the tool's own concern.
  final String contentSummary;
}

class ToolErrorSnapshot extends ToolResultSnapshot {
  const ToolErrorSnapshot({
    required super.id,
    required super.elapsed,
    required this.message,
    required this.category,
    required this.retryable,
  });

  final String message;
  final ErrorCategory category;
  final bool retryable;
}

class ToolCancelledSnapshot extends ToolResultSnapshot {
  const ToolCancelledSnapshot({required super.id, required super.elapsed});
}
