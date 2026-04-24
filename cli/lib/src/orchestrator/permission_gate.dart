import 'package:glue/src/agent/agent.dart';
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
}
