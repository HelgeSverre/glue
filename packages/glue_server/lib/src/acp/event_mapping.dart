/// Translates Glue's typed [SessionEvent] vocabulary (from glue_core)
/// into ACP `session/update` payloads.
///
/// Pure function — no harness state, no side effects. The server class
/// in `server.dart` calls this to render every event the harness emits.
///
/// Coverage today: the conversation, tool, and thinking events that ACP
/// has direct counterparts for. Lifecycle events (TurnStarted/Completed,
/// StatusChange, MetricsUpdated, TitleGenerated) and permission/auth
/// events return `null` — they are handled out-of-band by the server
/// (e.g. permission events drive `session/request_permission` requests,
/// not `session/update` notifications).
library;

import 'package:glue_core/glue_core.dart';
import 'package:glue_server/src/acp/content.dart';
import 'package:glue_server/src/acp/messages.dart';

/// Maps a single [SessionEvent] to a [SessionUpdate], or returns `null`
/// when the event has no `session/update` representation.
SessionUpdate? sessionEventToAcpUpdate(SessionEvent event) {
  return switch (event) {
    AssistantChunkEvent(:final delta, :final kind) => kind == ChunkKind.thinking
        ? AgentThoughtChunkUpdate(delta)
        : AgentMessageChunkUpdate(delta),
    AssistantMessageEvent() => null, // chunks already covered the text
    AssistantThinkingStartedEvent() => null,
    AssistantThinkingCompletedEvent() => null,
    UserMessageEvent() => null, // client knows what it sent
    ToolCallStartedEvent(:final id, :final tool, :final kind, :final args) =>
      ToolCallUpdate(
        toolCallId: id.value,
        title: tool,
        kind_: _toolKindToAcp(kind),
        status: ToolCallStatus.inProgress,
        rawInput: args,
      ),
    ToolCallProgressEvent() => null, // not yet surfaced
    ToolCallCompletedEvent(:final id, :final result) => ToolCallStatusUpdate(
        toolCallId: id.value,
        status: switch (result) {
          ToolOkSnapshot() => ToolCallStatus.completed,
          ToolErrorSnapshot() => ToolCallStatus.failed,
          ToolCancelledSnapshot() => ToolCallStatus.failed,
        },
        content: _resultContent(result),
      ),
    PermissionRequestedEvent() => null, // drives session/request_permission
    PermissionResolvedEvent() => null,
    SubagentSpawnedEvent() => null, // surfaced as forwarded events
    SubagentEventForwardedEvent(:final inner) => sessionEventToAcpUpdate(inner),
    SubagentCompletedEvent() => null,
    DeviceCodeRequestedEvent() => null, // out-of-band auth flow
    DeviceCodeResolvedEvent() => null,
    TurnStartedEvent() => null,
    TurnCompletedEvent() => null, // server returns SessionPromptResult
    StatusChangeEvent() => null,
    TitleGeneratedEvent() => null,
    MetricsUpdatedEvent() => null,
    ErrorEvent() => null, // server emits a JSON-RPC error
    // MCP lifecycle events: B7 will route these as a Glue-extension
    // `glue_mcp_status` session/update payload + a session/request_permission
    // for the auth-required variant. v1 (this bundle) drops them.
    McpServerConnectedEvent() => null,
    McpServerDisconnectedEvent() => null,
    McpServerErrorEvent() => null,
    McpServerAuthRequiredEvent() => null,
    McpToolListChangedEvent() => null,
    // Runtime lifecycle events: declared in glue_core for the cloud
    // runtime work, but not yet routed to ACP. PR 4/5 of the cloud
    // runtimes plan will translate them into a `glue_runtime_status`
    // extension update once the session bus emits them.
    RuntimeCommandStartedEvent() => null,
    RuntimeCommandOutputEvent() => null,
    RuntimeCommandCompletedEvent() => null,
    RuntimeCommandFailedEvent() => null,
    RuntimeCommandCancelledEvent() => null,
    RuntimeContainerStartedEvent() => null,
    RuntimeContainerStoppedEvent() => null,
  };
}

ToolCallKind _toolKindToAcp(ToolKind kind) {
  return switch (kind) {
    ToolKind.read => ToolCallKind.read,
    ToolKind.write => ToolCallKind.edit,
    ToolKind.exec => ToolCallKind.execute,
    ToolKind.network => ToolCallKind.fetch,
    ToolKind.meta => ToolCallKind.other,
  };
}

List<AcpToolCallContent> _resultContent(ToolResultSnapshot result) {
  return switch (result) {
    ToolOkSnapshot(:final contentSummary) => [
        AcpToolCallContentValue(AcpTextBlock(contentSummary)),
      ],
    ToolErrorSnapshot(:final message) => [
        AcpToolCallContentValue(AcpTextBlock('Error: $message')),
      ],
    ToolCancelledSnapshot() => const [
        AcpToolCallContentValue(AcpTextBlock('[cancelled]')),
      ],
  };
}
