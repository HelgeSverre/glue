/// Modal for OAuth device-code flows (GitHub Copilot).
///
/// Shows the verification URI and a short user code, subscribes to the
/// adapter's progress stream, and completes when the adapter emits
/// [AuthFlowSucceeded] or [AuthFlowFailed] (or the user presses Esc).
library;

import 'dart:async';
import 'dart:math';

import 'package:glue/src/providers/auth_flow.dart';
import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/panel_modal.dart';

class DeviceCodePanel implements PanelOverlay {
  DeviceCodePanel({
    required this.flow,
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
      },
      onDone: () {
        if (!_completer.isCompleted) _completer.complete(null);
      },
      onError: (Object e) {
        if (!_completer.isCompleted) _completer.complete(null);
      },
    );
  }

  final DeviceCodeFlow flow;
  final PanelSize _width;
  final PanelSize _height;

  final Completer<Map<String, String>?> _completer = Completer();
  StreamSubscription<AuthFlowProgress>? _subscription;
  AuthFlowProgress _latest = const AuthFlowPolling();
  int _spinnerFrame = 0;

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
    if (event case KeyEvent(key: Key.escape)) {
      cancel();
      return true;
    }
    return true;
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

    final content = <String>[
      '',
      ' 1. Open  ${flow.verificationUri.styled.cyan}',
      ' 2. Enter code  ${flow.userCode.styled.bold}',
      ' 3. Approve in your browser',
      '',
      ' ${statusLine.styled.dim}',
    ];
    while (content.length < panelH - 2) {
      content.add('');
    }
    content.add(' ${'Esc cancel'.styled.dim}');

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
