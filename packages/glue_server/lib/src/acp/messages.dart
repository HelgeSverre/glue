/// Typed Dart shapes for the subset of the Agent Client Protocol (ACP)
/// that Glue's server implements.
///
/// Only the v1 message vocabulary needed to drive a `glue serve` session:
/// `initialize`, `session/new`, `session/prompt`, `session/cancel`,
/// `session/update`, `session/request_permission`, plus their parameter
/// and response shapes.
///
/// See `docs/plans/2026-02-27-acp-webui.md` and the upstream spec at
/// https://agentclientprotocol.com/.
library;

import 'package:glue_server/src/acp/content.dart';

// ---------------------------------------------------------------------------
// Method names
// ---------------------------------------------------------------------------

abstract final class AcpMethod {
  static const initialize = 'initialize';
  static const sessionNew = 'session/new';
  static const sessionPrompt = 'session/prompt';
  static const sessionCancel = 'session/cancel';
  static const sessionUpdate = 'session/update';
  static const sessionRequestPermission = 'session/request_permission';
  static const sessionUsageSummary = 'session/usage_summary';
}

// ---------------------------------------------------------------------------
// `initialize`
// ---------------------------------------------------------------------------

class InitializeParams {
  const InitializeParams({
    required this.protocolVersion,
    this.clientCapabilities,
    this.clientInfo,
  });

  final int protocolVersion;
  final Map<String, Object?>? clientCapabilities;
  final ClientInfo? clientInfo;

  factory InitializeParams.fromJson(Map<String, Object?> json) =>
      InitializeParams(
        protocolVersion: (json['protocolVersion'] as num).toInt(),
        clientCapabilities:
            (json['clientCapabilities'] as Map?)?.cast<String, Object?>(),
        clientInfo: json['clientInfo'] is Map
            ? ClientInfo.fromJson(
                (json['clientInfo']! as Map).cast<String, Object?>(),
              )
            : null,
      );
}

class ClientInfo {
  const ClientInfo({required this.name, this.title, this.version});
  final String name;
  final String? title;
  final String? version;

  factory ClientInfo.fromJson(Map<String, Object?> json) => ClientInfo(
        name: json['name'] as String,
        title: json['title'] as String?,
        version: json['version'] as String?,
      );
}

class InitializeResult {
  const InitializeResult({
    required this.protocolVersion,
    required this.agentInfo,
    this.agentCapabilities = const {},
  });

  final int protocolVersion;
  final AgentInfo agentInfo;
  final Map<String, Object?> agentCapabilities;

  Map<String, Object?> toJson() => {
        'protocolVersion': protocolVersion,
        'agentInfo': agentInfo.toJson(),
        'agentCapabilities': agentCapabilities,
      };
}

class AgentInfo {
  const AgentInfo({required this.name, this.title, this.version});
  final String name;
  final String? title;
  final String? version;

  Map<String, Object?> toJson() => {
        'name': name,
        if (title != null) 'title': title,
        if (version != null) 'version': version,
      };
}

// ---------------------------------------------------------------------------
// `session/new`
// ---------------------------------------------------------------------------

class SessionNewParams {
  const SessionNewParams({required this.cwd, this.mcpServers = const []});
  final String cwd;
  final List<Map<String, Object?>> mcpServers;

  factory SessionNewParams.fromJson(Map<String, Object?> json) =>
      SessionNewParams(
        cwd: json['cwd'] as String,
        mcpServers: ((json['mcpServers'] as List?) ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map((e) => e.cast<String, Object?>())
            .toList(),
      );
}

class SessionNewResult {
  const SessionNewResult({required this.sessionId});
  final String sessionId;

  Map<String, Object?> toJson() => {'sessionId': sessionId};
}

// ---------------------------------------------------------------------------
// `session/prompt`
// ---------------------------------------------------------------------------

class SessionPromptParams {
  const SessionPromptParams({required this.sessionId, required this.prompt});
  final String sessionId;
  final List<AcpContentBlock> prompt;

  factory SessionPromptParams.fromJson(Map<String, Object?> json) =>
      SessionPromptParams(
        sessionId: json['sessionId'] as String,
        prompt: [
          for (final block in (json['prompt'] as List?) ?? const [])
            if (block is Map<Object?, Object?>)
              AcpContentBlock.fromJson(block.cast<String, Object?>()),
        ],
      );

  /// Convenience: returns the concatenated text of all [AcpTextBlock]s
  /// in the prompt. Image/audio/resource blocks are ignored — see
  /// [imageBlocks] for those.
  String get text {
    final buf = StringBuffer();
    for (final block in prompt) {
      if (block is AcpTextBlock) buf.write(block.text);
    }
    return buf.toString();
  }

  /// Image blocks the client attached to the prompt. Empty when text-only.
  List<AcpImageBlock> get imageBlocks =>
      prompt.whereType<AcpImageBlock>().toList();
}

class SessionPromptResult {
  const SessionPromptResult({required this.stopReason});
  final StopReason stopReason;

  Map<String, Object?> toJson() => {'stopReason': stopReason.wireName};
}

enum StopReason {
  endTurn('end_turn'),
  maxTokens('max_tokens'),
  maxTurnRequests('max_turn_requests'),
  refusal('refusal'),
  cancelled('cancelled');

  const StopReason(this.wireName);
  final String wireName;
}

// ---------------------------------------------------------------------------
// `session/cancel` (notification)
// ---------------------------------------------------------------------------

class SessionCancelParams {
  const SessionCancelParams({required this.sessionId});
  final String sessionId;

  factory SessionCancelParams.fromJson(Map<String, Object?> json) =>
      SessionCancelParams(sessionId: json['sessionId'] as String);
}

// ---------------------------------------------------------------------------
// `session/update` (notification — agent → client)
// ---------------------------------------------------------------------------

/// All `session/update` payloads. The `sessionUpdate` field is the
/// discriminator on the wire.
sealed class SessionUpdate {
  const SessionUpdate();
  String get kind;
  Map<String, Object?> toJson();
}

class AgentMessageChunkUpdate extends SessionUpdate {
  const AgentMessageChunkUpdate(this.text);
  final String text;

  @override
  String get kind => 'agent_message_chunk';

  @override
  Map<String, Object?> toJson() => {
        'sessionUpdate': kind,
        'content': {'type': 'text', 'text': text},
      };
}

class AgentThoughtChunkUpdate extends SessionUpdate {
  const AgentThoughtChunkUpdate(this.text);
  final String text;

  @override
  String get kind => 'agent_thought_chunk';

  @override
  Map<String, Object?> toJson() => {
        'sessionUpdate': kind,
        'content': {'type': 'text', 'text': text},
      };
}

class ToolCallUpdate extends SessionUpdate {
  const ToolCallUpdate({
    required this.toolCallId,
    required this.title,
    required this.kind_,
    required this.status,
    this.rawInput,
  });

  final String toolCallId;
  final String title;
  final ToolCallKind kind_;
  final ToolCallStatus status;
  final Map<String, Object?>? rawInput;

  @override
  String get kind => 'tool_call';

  @override
  Map<String, Object?> toJson() => {
        'sessionUpdate': kind,
        'toolCallId': toolCallId,
        'title': title,
        'kind': kind_.wireName,
        'status': status.wireName,
        if (rawInput != null) 'rawInput': rawInput,
      };
}

class ToolCallStatusUpdate extends SessionUpdate {
  const ToolCallStatusUpdate({
    required this.toolCallId,
    required this.status,
    this.content = const [],
  });

  final String toolCallId;
  final ToolCallStatus status;
  final List<AcpToolCallContent> content;

  @override
  String get kind => 'tool_call_update';

  @override
  Map<String, Object?> toJson() => {
        'sessionUpdate': kind,
        'toolCallId': toolCallId,
        'status': status.wireName,
        if (content.isNotEmpty)
          'content': [for (final c in content) c.toJson()],
      };
}

enum ToolCallKind {
  read('read'),
  edit('edit'),
  execute('execute'),
  search('search'),
  fetch('fetch'),
  other('other');

  const ToolCallKind(this.wireName);
  final String wireName;
}

enum ToolCallStatus {
  pending('pending'),
  inProgress('in_progress'),
  completed('completed'),
  failed('failed');

  const ToolCallStatus(this.wireName);
  final String wireName;
}

/// Full payload for a `session/update` notification.
class SessionUpdateNotification {
  const SessionUpdateNotification({
    required this.sessionId,
    required this.update,
  });

  final String sessionId;
  final SessionUpdate update;

  Map<String, Object?> toJson() => {
        'sessionId': sessionId,
        'update': update.toJson(),
      };
}

// ---------------------------------------------------------------------------
// `session/request_permission` (request — agent → client)
// ---------------------------------------------------------------------------

class RequestPermissionParams {
  const RequestPermissionParams({
    required this.sessionId,
    required this.toolCallId,
    required this.title,
    required this.kind_,
    required this.options,
  });

  final String sessionId;
  final String toolCallId;
  final String title;
  final ToolCallKind kind_;
  final List<PermissionOption> options;

  Map<String, Object?> toJson() => {
        'sessionId': sessionId,
        'toolCallId': toolCallId,
        'title': title,
        'kind': kind_.wireName,
        'options': [for (final o in options) o.toJson()],
      };
}

class PermissionOption {
  const PermissionOption({
    required this.optionId,
    required this.label,
    this.description,
  });

  final String optionId;
  final String label;
  final String? description;

  Map<String, Object?> toJson() => {
        'optionId': optionId,
        'label': label,
        if (description != null) 'description': description,
      };
}

class RequestPermissionResult {
  const RequestPermissionResult({required this.outcome});
  final PermissionOutcome outcome;

  factory RequestPermissionResult.fromJson(Map<String, Object?> json) {
    final outcomeMap = (json['outcome'] as Map).cast<String, Object?>();
    return RequestPermissionResult(
      outcome: PermissionOutcome.fromJson(outcomeMap),
    );
  }
}

sealed class PermissionOutcome {
  const PermissionOutcome();

  factory PermissionOutcome.fromJson(Map<String, Object?> json) {
    final outcomeKind = json['outcome'];
    if (outcomeKind == 'cancelled') return const PermissionCancelled();
    if (outcomeKind == 'selected') {
      return PermissionSelected(json['optionId'] as String);
    }
    throw FormatException('unknown permission outcome: $outcomeKind');
  }
}

class PermissionCancelled extends PermissionOutcome {
  const PermissionCancelled();
}

class PermissionSelected extends PermissionOutcome {
  const PermissionSelected(this.optionId);
  final String optionId;
}
