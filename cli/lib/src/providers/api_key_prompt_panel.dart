/// Single-input modal for providers that need an API key.
///
/// Built on [AbstractPanel]. Masks input as `•`; pre-fills with "[using $ENV
/// — leave blank to keep]" when the provider's env var is already set.
library;

import 'dart:async';
import 'dart:math';

import 'package:glue/src/ui/rendering/ansi_utils.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/components/panel.dart';

class ApiKeyPromptPanel implements AbstractPanel {
  ApiKeyPromptPanel({
    required this.providerId,
    required this.providerName,
    this.envVar,
    this.envPresent,
    this.helpUrl,
    PanelSize? width,
    PanelSize? height,
  })  : _width = width ?? PanelFluid(0.7, 50),
        _height = height ?? PanelFluid(0.4, 9);

  final String providerId;
  final String providerName;
  final String? envVar;
  final String? envPresent;
  final String? helpUrl;

  final PanelSize _width;
  final PanelSize _height;

  final _buffer = StringBuffer();
  final _submitted = Completer<String?>();

  bool get hasEnvPresent => envPresent != null && envPresent!.isNotEmpty;

  /// Resolves with:
  ///   - null on Esc cancel.
  ///   - '' (empty) when submit is pressed with no input AND env is present
  ///     (user accepts env-only).
  ///   - the typed string otherwise.
  Future<String?> get result => _submitted.future;

  @override
  bool get isComplete => _submitted.isCompleted;

  @override
  void cancel() {
    if (!_submitted.isCompleted) _submitted.complete(null);
  }

  @override
  bool handleEvent(TerminalEvent event) {
    if (isComplete) return false;
    switch (event) {
      case KeyEvent(key: Key.escape):
        cancel();
        return true;
      case KeyEvent(key: Key.enter):
        final entered = _buffer.toString();
        // Empty submit with env set → keep env (return ''). Empty without
        // env → require input; ignore the submit.
        if (entered.isEmpty && !hasEnvPresent) return true;
        _submitted.complete(entered);
        return true;
      case KeyEvent(key: Key.backspace):
        if (_buffer.isNotEmpty) {
          final s = _buffer.toString();
          _buffer
            ..clear()
            ..write(s.substring(0, s.length - 1));
        }
        return true;
      case KeyEvent(key: Key.ctrlU):
        _buffer.clear();
        return true;
      case CharEvent(:final char, alt: false):
        _buffer.write(char);
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
    final panelW = _width.resolve(termWidth);
    final panelH = _height.resolve(termHeight);
    final innerW = max(1, panelW - 2);

    final dimmed = applyBarrier(BarrierStyle.dim, backgroundLines);
    final content = <String>[];
    content.add('');
    content.add(' ${'API key:'.styled.dim} ${_maskedInput(innerW - 12)}');
    content.add('');
    if (hasEnvPresent) {
      content.add(
        ' ${'[using \$$envVar — leave blank to keep]'.styled.dim}',
      );
    } else if (helpUrl != null) {
      final url = helpUrl!;
      content.add(
        ' ${'Get one at'.styled.dim} ${osc8Link(url, url).styled.cyan}',
      );
    }
    while (content.length < panelH - 2) {
      content.add('');
    }
    content.add(' ${'Enter submit · Esc cancel'.styled.dim}');

    return _composeModal(
      title: 'Connect $providerName',
      panelW: panelW,
      panelH: panelH,
      content: content,
      background: dimmed,
      termWidth: termWidth,
      termHeight: termHeight,
    );
  }

  String _maskedInput(int width) {
    final len = _buffer.length;
    final mask = '•' * len;
    const cursor = '\x1b[7m \x1b[0m'; // inverse-video block cursor
    final visible = mask + cursor;
    return visible.length > width
        ? visible.substring(visible.length - width)
        : visible;
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

  // Paint content into the border's interior.
  final painted = <String>[];
  painted.add(bordered.first);
  for (var i = 1; i < bordered.length - 1; i++) {
    final row = i - 1;
    final line = row < content.length ? content[row] : '';
    final visibleLine = ansiTruncate(line, innerW);
    final pad = max(0, innerW - visibleLength(visibleLine));
    painted.add('\x1b[2m│\x1b[0m$visibleLine${' ' * pad}\x1b[2m│\x1b[0m');
  }
  painted.add(bordered.last);

  return _centerOverlay(
    painted,
    background,
    panelW,
    panelH,
    termWidth,
    termHeight,
  );
}

List<String> _centerOverlay(
  List<String> panel,
  List<String> background,
  int panelW,
  int panelH,
  int termWidth,
  int termHeight,
) {
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
    final line = panel[i];
    out[topPad + i] = '$leftBg$line';
  }
  return out;
}
