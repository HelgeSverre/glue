import 'dart:async';

/// Owns render-loop scheduling and spinner state.
///
/// [schedule] coalesces back-to-back render requests to ~60fps. The actual
/// paint function (still owned by `App` while it exists) is passed in as a
/// callback. [startSpinner] runs a periodic tick that advances [spinnerFrame]
/// and invokes a render callback on every frame.
///
/// State-only — does not know what's being rendered. `App` reaches for
/// [spinnerFrame] and [renderedPanelLastFrame] from the paint path.
class Renderer {
  static const _minRenderInterval = Duration(milliseconds: 16); // ~60fps
  static const _spinnerTickInterval = Duration(milliseconds: 80);
  static const _spinnerFrames = [
    '⠋',
    '⠙',
    '⠹',
    '⠸',
    '⠼',
    '⠴',
    '⠦',
    '⠧',
    '⠇',
    '⠏',
  ];

  int _spinnerFrame = 0;
  Timer? _spinnerTimer;
  DateTime _lastRender = DateTime(0);
  bool _renderScheduled = false;
  bool renderedPanelLastFrame = false;

  /// Current spinner glyph.
  String get spinnerFrame => _spinnerFrames[_spinnerFrame];

  /// Request a render. Coalesces calls so no more than one paint happens
  /// per [_minRenderInterval]. [doRender] is the paint callback — it must
  /// call [markRendered] at its start.
  void schedule(void Function() doRender) {
    final now = DateTime.now();
    if (now.difference(_lastRender) < _minRenderInterval) {
      if (!_renderScheduled) {
        _renderScheduled = true;
        Future.delayed(_minRenderInterval, () {
          _renderScheduled = false;
          if (DateTime.now().difference(_lastRender) >= _minRenderInterval) {
            doRender();
          }
        });
      }
      return;
    }
    doRender();
  }

  /// Called by the paint function to record when a frame landed.
  void markRendered() {
    _lastRender = DateTime.now();
  }

  /// Start the spinner ticker. Safe to call while already running (no-op).
  /// [onTick] is invoked every frame, typically [App._render].
  void startSpinner(void Function() onTick) {
    if (_spinnerTimer != null) return;
    _spinnerFrame = 0;
    _spinnerTimer = Timer.periodic(_spinnerTickInterval, (_) {
      _spinnerFrame = (_spinnerFrame + 1) % _spinnerFrames.length;
      onTick();
    });
  }

  /// Stop the spinner ticker. Safe to call when not running.
  void stopSpinner() {
    _spinnerTimer?.cancel();
    _spinnerTimer = null;
  }
}
