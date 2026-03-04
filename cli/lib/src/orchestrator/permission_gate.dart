import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/permission_mode.dart';
import 'package:path/path.dart' as p;

enum PermissionDecision { allow, ask, deny }

/// Pure permission decision logic for tool calls.
class PermissionGate {
  final PermissionMode permissionMode;
  final Set<String> trustedTools;
  final Map<String, Tool> tools;
  final String cwd;

  const PermissionGate({
    required this.permissionMode,
    required this.trustedTools,
    required this.tools,
    required this.cwd,
  });

  PermissionDecision resolve(ToolCall call) {
    final tool = tools[call.name];

    switch (permissionMode) {
      case PermissionMode.ignorePermissions:
        return PermissionDecision.allow;

      case PermissionMode.readOnly:
        if (tool != null && tool.isMutating) return PermissionDecision.deny;
        return PermissionDecision.allow;

      case PermissionMode.acceptEdits:
        if (isTrusted(call.name)) return PermissionDecision.allow;
        if (tool != null && tool.trust == ToolTrust.fileEdit) {
          if (targetsPathOutsideCwd(call)) return PermissionDecision.ask;
          return PermissionDecision.allow;
        }
        return PermissionDecision.ask;

      case PermissionMode.confirm:
        if (isTrusted(call.name)) return PermissionDecision.allow;
        return PermissionDecision.ask;
    }
  }

  bool isTrusted(String toolName) => trustedTools.contains(toolName);

  bool targetsPathOutsideCwd(ToolCall call) {
    final rawPath = call.arguments['path'] as String? ??
        call.arguments['file_path'] as String?;
    if (rawPath == null) return false;
    final resolved = p.normalize(
      p.isAbsolute(rawPath) ? rawPath : p.join(cwd, rawPath),
    );
    return !p.isWithin(cwd, resolved) && resolved != cwd;
  }

  /// Whether this tool needs confirmation at ToolCallPending time.
  bool needsEarlyConfirmation(String toolName) {
    final tool = tools[toolName];

    switch (permissionMode) {
      case PermissionMode.ignorePermissions:
      case PermissionMode.readOnly:
        return false;

      case PermissionMode.acceptEdits:
        if (isTrusted(toolName)) return false;
        if (tool != null && tool.trust == ToolTrust.fileEdit) return false;
        return true;

      case PermissionMode.confirm:
        return !isTrusted(toolName);
    }
  }
}
