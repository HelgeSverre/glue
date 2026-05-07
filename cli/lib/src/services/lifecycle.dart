/// Tiny service that lets the slash command system request app shutdown
/// without holding a reference to the App.
class Lifecycle {
  Lifecycle({required void Function() onExit}) : _onExit = onExit;

  final void Function() _onExit;

  void requestExit() => _onExit();
}
