/// Modal for OAuth device-code flows (GitHub Copilot).
///
/// Shows the verification URI and a short user code, subscribes to the
/// adapter's progress stream, and completes when the adapter emits
/// [AuthFlowSucceeded] or [AuthFlowFailed] (or the user presses Esc).
library;

import 'dart:async';
import 'dart:math';

import 'package:glue/src/core/clipboard.dart';
import 'package:glue/src/core/url_launcher.dart';
import 'package:glue/src/providers/auth_flow.dart';
import 'package:glue/src/ui/rendering/ansi_utils.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/components/panel.dart';

class DeviceCodePanel implements AbstractPanel {
  DeviceCodePanel({
    required this.flow,
    this.onNeedsRender,
    PanelSize? width,
    PanelSize? height,
  })  : _width = width ?? PanelFluid(0.7, 56),
        _height = height ?? PanelFluid(0.4, 11) {
    _subscription = flow.progress.listen(
      (ev) {
        _latest = ev;
        if (ev is AuthFlowSucceeded && !_completer.isCompleted) {
          _completer.complete(ev.fields);
        } else if (ev is AuthFlowFailed && !_completer.isCompleted) {
          _completer.complete(null);
        }
        // The panel stack's render is event-driven; adapter progress
        // events (polling, success, failure) don't otherwise trigger one.
        // Request a redraw so the status line updates in real time.
        onNeedsRender?.call();
      },
      onDone: () {
        if (!_completer.isCompleted) _completer.complete(null);
      },
      onError: (Object e) {
        if (!_completer.isCompleted) _completer.complete(null);
      },
    );

    // Auto-copy the user code so the user can paste it directly in the
    // browser — our TUI claims the terminal in raw mode, so ordinary
    // text-selection is blocked and they'd otherwise have to transcribe
    // ABCD-1234 by hand.
    unawaited(_copyUserCode());
  }

  final DeviceCodeFlow flow;

  /// Called when the panel's render state has changed outside the normal
  /// event-driven render cycle (async clipboard completion, stream events).
  /// Supplied by [PanelController] so the frame refreshes without a keypress.
  final void Function()? onNeedsRender;

  final PanelSize _width;
  final PanelSize _height;

  final Completer<Map<String, String>?> _completer = Completer();
  StreamSubscription<AuthFlowProgress>? _subscription;
  AuthFlowProgress _latest = const AuthFlowPolling();
  int _spinnerFrame = 0;
  bool _copied = false;

  Future<void> _copyUserCode() async {
    final ok = await copyToClipboard(flow.userCode);
    _copied = ok;
    // Surface the "(copied to clipboard)" hint on the next frame.
    if (ok) onNeedsRender?.call();
  }

  static const _spinner = ['⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷'];

  /// Resolves with the adapter-returned fields on success, or null on
  /// cancel / failure.
  Future<Map<String, String>?> get result => _completer.future;

  @override
  bool get isComplete => _completer.isCompleted;

  @override
  void cancel() {
    _subscription?.cancel();
    if (!_completer.isCompleted) _completer.complete(null);
  }

  @override
  bool handleEvent(TerminalEvent event) {
    if (isComplete) return false;
    switch (event) {
      case KeyEvent(key: Key.escape):
        cancel();
        return true;
      case KeyEvent(key: Key.enter):
        // Fire-and-forget: if the launcher fails the user still has the URL
        // on screen (with OSC-8 hyperlink on supporting terminals).
        unawaited(openInBrowser(flow.verificationUri));
        return true;
      case CharEvent(char: 'c', alt: false):
      case CharEvent(char: 'C', alt: false):
        unawaited(_copyUserCode());
        return true;
      default:
        return true;
    }
  }

  @override
  List<String> render(
    int termWidth,
    int termHeight,
    List<String> backgroundLines,
  ) {
    _spinnerFrame = (_spinnerFrame + 1) % _spinner.length;

    final panelW = _width.resolve(termWidth);
    final panelH = _height.resolve(termHeight);
    final dimmed = applyBarrier(BarrierStyle.dim, backgroundLines);

    final remaining = flow.expiresAt.difference(DateTime.now().toUtc());
    final remainingLabel = remaining.isNegative
        ? 'expired'
        : 'expires in ${_prettyDuration(remaining)}';

    final statusLine = switch (_latest) {
      AuthFlowPolling() =>
        '${_spinner[_spinnerFrame]}  Waiting for approval...  ($remainingLabel)',
      AuthFlowSucceeded() => '✓  Connected.',
      AuthFlowFailed(:final reason) => '✗  Failed: $reason',
    };

    final linkedUri =
        osc8Link(flow.verificationUri, flow.verificationUri).styled.cyan;
    final copiedHint = _copied ? '  (copied to clipboard)'.styled.dim : '';
    final content = <String>[
      '',
      ' 1. Open  $linkedUri',
      ' 2. Enter code  ${flow.userCode.styled.bold}$copiedHint',
      ' 3. Approve in your browser',
      '',
      ' ${statusLine.styled.dim}',
    ];
    while (content.length < panelH - 2) {
      content.add('');
    }
    content.add(
      ' ${'Enter open in browser · c copy code · Esc cancel'.styled.dim}',
    );

    return _composeModal(
      title: 'Connect ${flow.providerName}',
      panelW: panelW,
      panelH: panelH,
      content: content,
      background: dimmed,
      termWidth: termWidth,
      termHeight: termHeight,
    );
  }

  String _prettyDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

List<String> _composeModal({
  required String title,
  required int panelW,
  required int panelH,
  required List<String> content,
  required List<String> background,
  required int termWidth,
  required int termHeight,
}) {
  final bordered = renderBorder(PanelStyle.simple, panelW, panelH, title);
  final innerW = max(1, panelW - 2);

  final painted = <String>[];
  painted.add(bordered.first);
  for (var i = 1; i < bordered.length - 1; i++) {
    final row = i - 1;
    final line = row < content.length ? content[row] : '';
    final visible = ansiTruncate(line, innerW);
    final pad = max(0, innerW - visibleLength(visible));
    painted.add('\x1b[2m│\x1b[0m$visible${' ' * pad}\x1b[2m│\x1b[0m');
  }
  painted.add(bordered.last);

  final topPad = max(0, (termHeight - panelH) ~/ 2);
  final leftPad = max(0, (termWidth - panelW) ~/ 2);
  final out = List<String>.from(background);
  while (out.length < termHeight) {
    out.add('');
  }
  for (var i = 0; i < panelH && topPad + i < out.length; i++) {
    final bg = out[topPad + i];
    final bgLen = visibleLength(bg);
    final leftBg = bgLen >= leftPad
        ? ansiTruncate(bg, leftPad)
        : bg + ' ' * (leftPad - bgLen);
    out[topPad + i] = '$leftBg${painted[i]}';
  }
  return out;
}
