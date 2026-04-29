import 'package:glue/src/_proposed_core/ids.dart';
import 'package:glue/src/_proposed_core/session_event.dart' as core;
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/approval_mode.dart';

enum PermissionDecision { allow, ask, deny }

/// Pure permission decision logic for tool calls.
///
/// Combines [ApprovalMode] (confirm vs auto) with per-tool trust and the
/// user's trusted-tool allowlist.
class PermissionGate {
  final ApprovalMode approvalMode;
  final Set<String> trustedTools;
  final Map<String, Tool> tools;
  final String cwd;

  const PermissionGate({
    required this.approvalMode,
    required this.trustedTools,
    required this.tools,
    required this.cwd,
  });

  PermissionDecision resolve(ToolCall call) {
    final tool = tools[call.name];
    if (tool == null) return PermissionDecision.deny;

    if (approvalMode == ApprovalMode.auto) {
      return PermissionDecision.allow;
    }

    // confirm mode: safe tools and trusted tools auto-approve.
    if (!tool.isMutating || isTrusted(call.name)) {
      return PermissionDecision.allow;
    }

    return PermissionDecision.ask;
  }

  bool isTrusted(String toolName) => trustedTools.contains(toolName);

  /// Whether this tool needs confirmation at ToolCallPending time.
  bool needsEarlyConfirmation(String toolName) {
    final tool = tools[toolName];
    if (tool == null) return true;

    if (approvalMode == ApprovalMode.auto) return false;
    if (isTrusted(toolName)) return false;
    if (!tool.isMutating) return false;
    return true;
  }

  /// Builds a typed [core.PermissionRequestedEvent] describing the user-facing
  /// "ask" decision for [call].
  ///
  /// This is the proposed-core contract for surfaces: instead of reading
  /// permission state directly, future surfaces consume
  /// [core.PermissionRequestedEvent] from the session event stream and
  /// respond by dispatching `ResolvePermissionCommand`. Today's CLI still
  /// uses the legacy [resolve] path; this method exists so new surfaces
  /// (ACP server, web) and decoupled tests can build on the typed event
  /// contract.
  ///
  /// Pre-condition: [resolve] returned [PermissionDecision.ask] for [call].
  /// Calling this for an `allow`/`deny` decision is a programmer error.
  core.PermissionRequestedEvent requestEventFor(
    ToolCall call, {
    required TurnId turnId,
    required PermissionRequestId requestId,
    required int sequence,
    DateTime? timestamp,
    core.PermissionScope scope = core.PermissionScope.singleCall,
  }) {
    assert(
      resolve(call) == PermissionDecision.ask,
      'requestEventFor expects an ask-decision for ${call.name}',
    );
    final tool = tools[call.name];
    final summary = tool?.description ?? 'Run tool "${call.name}"';
    return core.PermissionRequestedEvent(
      turnId: turnId,
      timestamp: timestamp ?? DateTime.now(),
      sequence: sequence,
      requestId: requestId,
      toolCallId: ToolCallId(call.id),
      scope: scope,
      summary: summary,
      dangerLevel: _classifyDanger(tool),
    );
  }

  static core.ToolKind _classifyDanger(Tool? tool) {
    if (tool == null) return core.ToolKind.exec;
    return tool.isMutating ? core.ToolKind.write : core.ToolKind.read;
  }
}
