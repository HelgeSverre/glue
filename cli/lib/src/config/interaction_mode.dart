import 'package:glue/src/agent/tools.dart';

/// Interaction mode controlling which tool groups the LLM can access.
///
/// Copied from the Roo Code / Kilo Code tool-group model.
enum InteractionMode {
  /// All tools available. Default mode.
  code,

  /// Read + MCP + edit (.md files only). For planning and research.
  architect,

  /// Read + MCP only. No changes at all.
  ask,
}

/// Convenience helpers for [InteractionMode].
extension InteractionModeExt on InteractionMode {
  /// Short label shown in the status bar.
  String get label => name;

  /// The next mode in the Shift+Tab cycle.
  InteractionMode get next => switch (this) {
        InteractionMode.code => InteractionMode.architect,
        InteractionMode.architect => InteractionMode.ask,
        InteractionMode.ask => InteractionMode.code,
      };

  /// Whether this mode allows a given tool group.
  bool allowsGroup(ToolGroup group) => switch (this) {
        InteractionMode.code => true,
        InteractionMode.architect => group != ToolGroup.command,
        InteractionMode.ask =>
          group == ToolGroup.read || group == ToolGroup.mcp,
      };
}

/// Approval mode controlling whether tool calls require user confirmation.
///
/// Orthogonal to [InteractionMode].
enum ApprovalMode {
  /// Ask before untrusted tool calls.
  confirm,

  /// Auto-approve everything.
  auto,
}

/// Convenience helpers for [ApprovalMode].
extension ApprovalModeExt on ApprovalMode {
  /// Short label shown in the status bar.
  String get label => name;

  /// Toggle between confirm and auto.
  ApprovalMode get toggle => switch (this) {
        ApprovalMode.confirm => ApprovalMode.auto,
        ApprovalMode.auto => ApprovalMode.confirm,
      };
}
