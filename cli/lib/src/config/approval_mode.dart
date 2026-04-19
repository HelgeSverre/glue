/// Approval mode controlling whether tool calls require user confirmation.
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
