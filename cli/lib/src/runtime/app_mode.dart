/// Top-level application mode — what the user is currently doing and
/// therefore what kind of input should be accepted.
///
/// {@category Core}
enum AppMode {
  /// Waiting for user input.
  idle,

  /// The LLM is streaming a response.
  streaming,

  /// A tool is currently executing.
  toolRunning,

  /// Waiting for user to approve a tool invocation.
  confirming,

  /// A bash command is currently executing.
  bashRunning,
}
