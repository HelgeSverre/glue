import 'dart:async';

import 'package:glue/src/rendering/ansi_utils.dart';

enum ToastKind { success, error }

/// Transient corner notification — narrow chip painted directly into the
/// output viewport at top-right by [App._render]. Holds its own visibility
/// + dismiss timer.
///
/// Why not a `DockedPanel`: the dock manager always paints horizontal
/// floating panels at full output width, which blanks the entire row
/// behind the chip. The toast is narrow by design (chip width =
/// content + padding) so we paint it directly. Picking content width
/// also means a single `paintRect` call only touches the chip's own
/// cells and leaves the rest of the top row of transcript visible.
///
/// Visual style — charcoal chip (256-colour 236) + dim text (250) with
/// the glyph in yellow (220) for success or red (196) for failure.
class Toast {
  Toast({
    required this.onRender,
    this.successDuration = const Duration(milliseconds: 1800),
    this.errorDuration = const Duration(milliseconds: 3500),
  });

  /// Called every time visibility or content changes so the host can
  /// repaint. Wired to `App._render` in production.
  final void Function() onRender;

  /// Configurable for tests; production uses the defaults.
  final Duration successDuration;
  final Duration errorDuration;

  bool _visible = false;
  String _message = '';
  ToastKind _kind = ToastKind.success;
  Timer? _timer;

  bool get visible => _visible;

  /// Cell width of the rendered chip, including the 1-cell left/right
  /// inner padding around the glyph + message. Use this to size the
  /// `paintRect` so it doesn't blank cells it shouldn't.
  int get cellWidth =>
      _visible ? _glyphAndMessageCellWidth + _innerPadding * 2 : 0;

  static const int _innerPadding = 1;

  int get _glyphAndMessageCellWidth =>
      // glyph (1) + space separator (1) + message visible width
      2 + visibleLength(_message);

  /// Show [message] with kind-appropriate duration. A second call
  /// cancels any in-flight dismiss timer and replaces the message.
  void show(String message, {ToastKind kind = ToastKind.success}) {
    _message = message;
    _kind = kind;
    _visible = true;
    _timer?.cancel();
    final dur = kind == ToastKind.success ? successDuration : errorDuration;
    _timer = Timer(dur, () {
      _visible = false;
      _timer = null;
      onRender();
    });
    onRender();
  }

  /// Cancel any in-flight timer and hide immediately. Safe to call
  /// when the toast is already hidden (no-op).
  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (_visible) {
      _visible = false;
      onRender();
    }
  }

  /// The ANSI-styled chip body. Returns an empty string when the
  /// toast isn't visible; callers should `if (toast.visible)` before
  /// painting.
  String renderLine() {
    if (!_visible) return '';
    const bg = '\x1b[48;5;236m'; // charcoal background
    const dim = '\x1b[38;5;250m'; // dim grey text
    const reset = '\x1b[0m';
    final glyph = _kind == ToastKind.success ? '✓' : '!';
    final glyphFg = _kind == ToastKind.success
        ? '\x1b[38;5;220m'
        : '\x1b[38;5;196m';
    // Background stays continuous across the chip — the second fg switch
    // doesn't reset it.
    return '$bg$dim $glyphFg$glyph$dim $_message $reset';
  }
}
