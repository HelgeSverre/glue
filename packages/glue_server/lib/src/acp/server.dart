/// ACP agent server.
///
/// Owns the JSON-RPC dispatch loop. Routes incoming `initialize`,
/// `session/new`, `session/prompt`, and `session/cancel` to a pluggable
/// [AcpServerDelegate]; emits `session/update` notifications and
/// `session/request_permission` requests as the delegate runs.
///
/// The server itself has **no dependency on glue_harness** — the
/// delegate is the wiring point. A test can stand up an [AcpServer]
/// with a fake delegate and exercise the full protocol without the
/// real agent loop. The cli's `glue serve --stdio` provides a
/// production delegate that uses [`AgentCore`] + `SessionManager` from
/// glue_harness.
library;

import 'dart:async';

import 'package:glue_core/glue_core.dart';
import 'package:glue_server/src/acp/agent_event_mapping.dart';
import 'package:glue_server/src/acp/content.dart';
import 'package:glue_server/src/acp/messages.dart';
import 'package:glue_server/src/jsonrpc/messages.dart';
import 'package:glue_server/src/jsonrpc/transport.dart';

/// Adapter the server calls into for everything that needs harness
/// state. Implementations live above this package (e.g. in the cli).
abstract class AcpServerDelegate {
  /// Create a new session for the given client params; return its id.
  /// The server uses [SessionNewParams.cwd] and `mcpServers` as opaque
  /// inputs — interpretation is up to the delegate.
  Future<String> createSession(SessionNewParams params);

  /// Run a single prompt turn. Yields [AgentEvent]s as the agent
  /// produces them. The server translates events into `session/update`
  /// notifications and synthesises tool-call lifecycle updates around
  /// the permission gate.
  ///
  /// When a [Tool] call needs permission, the server invokes
  /// [requestPermission] (which the delegate routes to *its* permission
  /// gate). The future resolves to `true` to allow, `false` to deny.
  ///
  /// [userContentParts] carries multimodal input attached to the
  /// prompt (images, resource_links). Empty when the client sent only
  /// text. Implementations are free to ignore parts they can't
  /// represent — but ideally pass them through to the LLM.
  Stream<AgentEvent> prompt({
    required String sessionId,
    required String userMessage,
    required Future<bool> Function(ToolCall call) requestPermission,
    List<ContentPart> userContentParts = const [],
  });

  /// Cancel the active prompt on [sessionId], if any. Best-effort.
  void cancelPrompt(String sessionId);

  /// Returns a per-role token-usage breakdown for [sessionId]. Surfaces
  /// the same data the CLI shows under `/usage`, in a structure ACP
  /// clients can consume directly. Tokens only — no cost / pricing.
  UsageReport usageSummary(String sessionId);

  /// Close any resources held for [sessionId]. Called on connection
  /// teardown.
  Future<void> closeSession(String sessionId);
}

/// Static configuration for the ACP server.
class AcpServerConfig {
  const AcpServerConfig({
    this.protocolVersion = 1,
    this.agentInfo = const AgentInfo(name: 'glue', title: 'Glue'),
    this.agentCapabilities = const {},
  });

  final int protocolVersion;
  final AgentInfo agentInfo;
  final Map<String, Object?> agentCapabilities;
}

/// The ACP agent server. Construct, then call [serve] to drive the
/// dispatch loop until the transport closes.
class AcpServer {
  AcpServer({
    required this.transport,
    required this.delegate,
    this.config = const AcpServerConfig(),
  });

  final JsonRpcTransport transport;
  final AcpServerDelegate delegate;
  final AcpServerConfig config;

  // Per-session state for active prompts and pending permission requests.
  final Set<String> _knownSessions = {};
  int _nextRequestId = 1000000;
  final Map<int, Completer<RequestPermissionResult>> _pendingPermissions = {};

  /// Drives the dispatch loop until the inbound stream closes.
  Future<void> serve() async {
    final completer = Completer<void>();
    final sub = transport.incoming.listen(
      _dispatch,
      onError: (Object e, StackTrace st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
    );
    try {
      await completer.future;
    } finally {
      await sub.cancel();
      for (final id in _knownSessions.toList()) {
        await delegate.closeSession(id);
      }
      _knownSessions.clear();
    }
  }

  void _dispatch(JsonRpcMessage message) {
    switch (message) {
      case JsonRpcRequest(:final id, :final method, :final params):
        _handleRequest(id: id, method: method, params: params);
      case JsonRpcNotification(:final method, :final params):
        _handleNotification(method: method, params: params);
      case JsonRpcResponse(:final id, :final result):
        _handlePeerResponse(id: id, result: result);
      case JsonRpcError(:final id, :final code, :final message, :final data):
        _handlePeerError(id: id, code: code, message: message, data: data);
    }
  }

  Future<void> _handleRequest({
    required Object id,
    required String method,
    required Map<String, Object?>? params,
  }) async {
    try {
      switch (method) {
        case AcpMethod.initialize:
          transport.send(
            JsonRpcResponse(
              id: id,
              result: InitializeResult(
                protocolVersion: config.protocolVersion,
                agentInfo: config.agentInfo,
                agentCapabilities: config.agentCapabilities,
              ).toJson(),
            ),
          );
        case AcpMethod.sessionNew:
          if (params == null) {
            _replyInvalidParams(id, 'session/new requires params');
            return;
          }
          final newParams = SessionNewParams.fromJson(params);
          final sessionId = await delegate.createSession(newParams);
          _knownSessions.add(sessionId);
          transport.send(
            JsonRpcResponse(
              id: id,
              result: SessionNewResult(sessionId: sessionId).toJson(),
            ),
          );
        case AcpMethod.sessionPrompt:
          if (params == null) {
            _replyInvalidParams(id, 'session/prompt requires params');
            return;
          }
          final promptParams = SessionPromptParams.fromJson(params);
          if (!_knownSessions.contains(promptParams.sessionId)) {
            transport.send(
              JsonRpcError(
                id: id,
                code: JsonRpcErrorCode.sessionNotFound,
                message: 'unknown session: ${promptParams.sessionId}',
              ),
            );
            return;
          }
          final stopReason = await _runPrompt(promptParams);
          transport.send(
            JsonRpcResponse(
              id: id,
              result: SessionPromptResult(stopReason: stopReason).toJson(),
            ),
          );
        case AcpMethod.sessionUsageSummary:
          final sessionId = (params?['sessionId'] as String?)?.trim();
          if (sessionId == null || sessionId.isEmpty) {
            _replyInvalidParams(id, 'session/usage_summary requires sessionId');
            return;
          }
          if (!_knownSessions.contains(sessionId)) {
            transport.send(
              JsonRpcError(
                id: id,
                code: JsonRpcErrorCode.sessionNotFound,
                message: 'unknown session: $sessionId',
              ),
            );
            return;
          }
          transport.send(
            JsonRpcResponse(
              id: id,
              result: delegate.usageSummary(sessionId).toJson(),
            ),
          );
        default:
          transport.send(
            JsonRpcError(
              id: id,
              code: JsonRpcErrorCode.methodNotFound,
              message: 'method "$method" is not implemented',
            ),
          );
      }
    } on Object catch (e, st) {
      transport.send(
        JsonRpcError(
          id: id,
          code: JsonRpcErrorCode.internalError,
          message: 'internal error: $e',
          data: st.toString(),
        ),
      );
    }
  }

  void _handleNotification({
    required String method,
    required Map<String, Object?>? params,
  }) {
    if (method == AcpMethod.sessionCancel && params != null) {
      final cancel = SessionCancelParams.fromJson(params);
      delegate.cancelPrompt(cancel.sessionId);
      return;
    }
    // Other notifications are accepted silently in this scaffold.
  }

  void _handlePeerResponse({required Object id, required Object? result}) {
    if (id is! int) return;
    final pending = _pendingPermissions.remove(id);
    if (pending == null) return;
    if (result is! Map) {
      pending.completeError(
        FormatException('expected object result, got ${result.runtimeType}'),
      );
      return;
    }
    try {
      pending.complete(
        RequestPermissionResult.fromJson(result.cast<String, Object?>()),
      );
    } on Object catch (e, st) {
      pending.completeError(e, st);
    }
  }

  void _handlePeerError({
    required Object? id,
    required int code,
    required String message,
    required Object? data,
  }) {
    if (id is! int) return;
    final pending = _pendingPermissions.remove(id);
    pending?.completeError(StateError('permission request failed: $message'));
  }

  void _replyInvalidParams(Object id, String message) {
    transport.send(
      JsonRpcError(
        id: id,
        code: JsonRpcErrorCode.invalidParams,
        message: message,
      ),
    );
  }

  /// Runs a single prompt, streaming `session/update` notifications and
  /// gating tool calls through `session/request_permission`.
  Future<StopReason> _runPrompt(SessionPromptParams promptParams) async {
    final sessionId = promptParams.sessionId;
    // Translate non-text prompt blocks (images, resource_links) into
    // glue_core ContentParts for the harness to consume.
    final userParts = <ContentPart>[
      for (final block in promptParams.prompt)
        if (block is AcpImageBlock)
          ImagePart(bytes: block.decodedBytes(), mimeType: block.mimeType)
        else if (block is AcpResourceLinkBlock)
          ResourceLinkPart(
            uri: block.uri,
            name: block.name,
            description: block.description,
            mimeType: block.mimeType,
          ),
    ];

    final stream = delegate.prompt(
      sessionId: sessionId,
      userMessage: promptParams.text,
      requestPermission: (call) =>
          _requestPermissionFromClient(sessionId: sessionId, call: call),
      userContentParts: userParts,
    );

    // Track every tool call we've announced so we can update its status
    // when the corresponding result event arrives.
    final announced = <String>{};

    StopReason stopReason = StopReason.endTurn;
    try {
      await for (final event in stream) {
        switch (event) {
          case AgentTextDelta(:final delta):
            transport.send(
              JsonRpcNotification(
                method: AcpMethod.sessionUpdate,
                params: SessionUpdateNotification(
                  sessionId: sessionId,
                  update: AgentMessageChunkUpdate(delta),
                ).toJson(),
              ),
            );
          case AgentThinkingDelta():
            // Reasoning traces are a phase-2 ACP feature; agent_event_mapping
            // returns null so we drop the event here.
            break;
          case AgentToolCallPending(:final id, :final name):
            if (announced.add(id.value)) {
              transport.send(
                JsonRpcNotification(
                  method: AcpMethod.sessionUpdate,
                  params: SessionUpdateNotification(
                    sessionId: sessionId,
                    update: ToolCallUpdate(
                      toolCallId: id.value,
                      title: name,
                      kind_: toolNameToAcpKind(name),
                      status: ToolCallStatus.pending,
                    ),
                  ).toJson(),
                ),
              );
            }
          case AgentToolCall(:final call):
            if (announced.add(call.id.value)) {
              transport.send(
                JsonRpcNotification(
                  method: AcpMethod.sessionUpdate,
                  params: SessionUpdateNotification(
                    sessionId: sessionId,
                    update: ToolCallUpdate(
                      toolCallId: call.id.value,
                      title: call.name,
                      kind_: toolNameToAcpKind(call.name),
                      status: ToolCallStatus.inProgress,
                      rawInput: call.arguments,
                    ),
                  ).toJson(),
                ),
              );
            } else {
              transport.send(
                JsonRpcNotification(
                  method: AcpMethod.sessionUpdate,
                  params: SessionUpdateNotification(
                    sessionId: sessionId,
                    update: ToolCallStatusUpdate(
                      toolCallId: call.id.value,
                      status: ToolCallStatus.inProgress,
                    ),
                  ).toJson(),
                ),
              );
            }
          case AgentToolResult(:final result):
            transport.send(
              JsonRpcNotification(
                method: AcpMethod.sessionUpdate,
                params: SessionUpdateNotification(
                  sessionId: sessionId,
                  update: ToolCallStatusUpdate(
                    toolCallId: result.callId.value,
                    status: result.success
                        ? ToolCallStatus.completed
                        : ToolCallStatus.failed,
                    content: _toolResultContent(result),
                  ),
                ).toJson(),
              ),
            );
          case AgentUsage():
            // Token usage flows through to ACP clients via the upcoming
            // `session/usage_summary` request; per-call deltas don't need
            // a notification today.
            break;
          case AgentDone():
            stopReason = StopReason.endTurn;
          case AgentError(:final error):
            stopReason = StopReason.refusal;
            transport.send(
              JsonRpcNotification(
                method: AcpMethod.sessionUpdate,
                params: SessionUpdateNotification(
                  sessionId: sessionId,
                  update: AgentMessageChunkUpdate('\n[error] $error'),
                ).toJson(),
              ),
            );
          case AgentNotice(:final message, :final kind):
            // Soft-degradation announcement. Inline in the message stream
            // so ACP clients see it in the transcript.
            transport.send(
              JsonRpcNotification(
                method: AcpMethod.sessionUpdate,
                params: SessionUpdateNotification(
                  sessionId: sessionId,
                  update: AgentMessageChunkUpdate(
                    '${kind == 'warning' ? '!' : '·'} $message\n',
                  ),
                ).toJson(),
              ),
            );
        }
      }
    } on _PromptCancelled {
      stopReason = StopReason.cancelled;
    }
    return stopReason;
  }

  /// Sends `session/request_permission` to the client and awaits the
  /// reply. Resolves to `true` for `selected` (any optionId), `false`
  /// for `cancelled`.
  Future<bool> _requestPermissionFromClient({
    required String sessionId,
    required ToolCall call,
  }) async {
    final id = _nextRequestId++;
    final completer = Completer<RequestPermissionResult>();
    _pendingPermissions[id] = completer;

    transport.send(
      JsonRpcRequest(
        id: id,
        method: AcpMethod.sessionRequestPermission,
        params: RequestPermissionParams(
          sessionId: sessionId,
          toolCallId: call.id.value,
          title: call.name,
          kind_: toolNameToAcpKind(call.name),
          options: const [
            PermissionOption(optionId: 'allow', label: 'Allow'),
            PermissionOption(optionId: 'deny', label: 'Deny'),
          ],
        ).toJson(),
      ),
    );

    final result = await completer.future;
    return switch (result.outcome) {
      PermissionSelected(:final optionId) => optionId == 'allow',
      PermissionCancelled() => false,
    };
  }
}

/// Builds the `content[]` array for a `tool_call_update` notification.
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
List<AcpToolCallContent> _toolResultContent(ToolResult result) {
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

/// Internal sentinel used to signal a prompt was cancelled. Delegates
/// can throw this from their stream to route through the cancelled path.
class _PromptCancelled implements Exception {
  const _PromptCancelled();
}
