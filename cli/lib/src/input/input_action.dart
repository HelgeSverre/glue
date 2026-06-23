/// Actions that a text editor signals back to its owner.
enum InputAction {
  /// The buffer contents changed (re-render needed).
  changed,

  /// The user pressed Enter — submit the buffer.
  submit,

  /// Ctrl+C — interrupt / cancel.
  interrupt,

  /// Ctrl+D on an empty buffer — EOF.
  eof,

  /// Escape pressed.
  escape,

  /// Tab pressed — request auto-completion.
  requestCompletion,
}
