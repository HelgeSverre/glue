class DebugController {
  bool _enabled;

  DebugController({bool enabled = false}) : _enabled = enabled;

  bool get enabled => _enabled;

  void toggle() {
    _enabled = !_enabled;
  }

  void enable() => _enabled = true;
  void disable() => _enabled = false;
}
