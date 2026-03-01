/// Permission mode controlling how tool calls are approved.
///
/// {@category Configuration}
enum PermissionMode {
  /// Ask for confirmation on untrusted tools.
  confirm,

  /// Auto-approve file edits, still ask for shell commands.
  acceptEdits,

  /// Auto-approve everything. No confirmations.
  ignorePermissions,

  /// Deny all mutating tools. Don't even send them to the LLM.
  readOnly,
}

/// Convenience helpers for [PermissionMode].
extension PermissionModeExt on PermissionMode {
  /// Short label shown in the status bar.
  String get label => switch (this) {
        PermissionMode.confirm => 'confirm',
        PermissionMode.acceptEdits => 'accept-edits',
        PermissionMode.ignorePermissions => 'YOLO',
        PermissionMode.readOnly => 'read-only',
      };

  /// The next mode in the Shift+Tab cycle.
  PermissionMode get next => switch (this) {
        PermissionMode.confirm => PermissionMode.acceptEdits,
        PermissionMode.acceptEdits => PermissionMode.ignorePermissions,
        PermissionMode.ignorePermissions => PermissionMode.readOnly,
        PermissionMode.readOnly => PermissionMode.confirm,
      };
}
