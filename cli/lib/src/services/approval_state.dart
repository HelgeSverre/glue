import 'package:glue_harness/glue_harness.dart';

/// Mutable holder for the current approval mode. App owns the storage
/// (the `_approvalMode` field); this service exposes it through a typed
/// surface so commands and other consumers do not reach into App.
class ApprovalState {
  ApprovalState({required this._get, required this._set});

  final ApprovalMode Function() _get;
  final void Function(ApprovalMode) _set;

  ApprovalMode get mode => _get();

  void setMode(ApprovalMode mode) => _set(mode);

  /// Cycles between confirm and auto. Returns the new mode.
  ApprovalMode toggle() {
    final next = mode.toggle;
    _set(next);
    return next;
  }
}
