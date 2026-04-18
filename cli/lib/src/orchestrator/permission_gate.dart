import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/interaction_mode.dart';

enum PermissionDecision { allow, ask, deny }

/// Pure permission decision logic for tool calls.
///
/// Combines [InteractionMode] (which tools are available) with
/// [ApprovalMode] (whether to confirm before execution).
class PermissionGate {
  final InteractionMode interactionMode;
  final ApprovalMode approvalMode;
  final Set<String> trustedTools;
  final Map<String, Tool> tools;
  final String cwd;

  const PermissionGate({
    required this.interactionMode,
    required this.approvalMode,
    required this.trustedTools,
    required this.tools,
    required this.cwd,
  });

  PermissionDecision resolve(ToolCall call) {
    final tool = tools[call.name];
    if (tool == null) return PermissionDecision.deny;

    final group = tool.group;

    // 1. Check if the interaction mode allows this tool group at all.
    if (!interactionMode.allowsGroup(group)) {
      return PermissionDecision.deny;
    }

    // 2. Architect mode: edit tools only for .md files.
    if (interactionMode == InteractionMode.architect &&
        group == ToolGroup.edit) {
      if (!_targetsMarkdownFile(call)) {
        return PermissionDecision.deny;
      }
    }

    // 3. Apply approval mode.
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

  bool _targetsMarkdownFile(ToolCall call) {
    final rawPath = call.arguments['path'] as String? ??
        call.arguments['file_path'] as String?;
    if (rawPath == null) return false;
    return rawPath.endsWith('.md');
  }

  /// Whether this tool needs confirmation at ToolCallPending time.
  bool needsEarlyConfirmation(String toolName) {
    final tool = tools[toolName];
    if (tool == null) return true;

    if (!interactionMode.allowsGroup(tool.group)) return false;

    if (approvalMode == ApprovalMode.auto) return false;
    if (isTrusted(toolName)) return false;
    if (!tool.isMutating) return false;
    return true;
  }
}
