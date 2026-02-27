import 'dart:math';

import '../rendering/ansi_utils.dart';

enum PanelStyle { tape, simple, heavy }

enum BarrierStyle { dim, obscure, none }

sealed class PanelSize {
  int resolve(int available);
}

class PanelFixed extends PanelSize {
  final int size;
  PanelFixed(this.size);

  @override
  int resolve(int available) => min(size, available);
}

class PanelFluid extends PanelSize {
  final double maxPercent;
  final int minSize;
  PanelFluid(this.maxPercent, this.minSize);

  @override
  int resolve(int available) =>
      min(max((available * maxPercent).floor(), minSize), available);
}

List<String> renderBorder(
  PanelStyle style,
  int width,
  int height,
  String title,
) {
  return switch (style) {
    PanelStyle.simple => _renderSimple(width, height, title),
    PanelStyle.heavy => _renderHeavy(width, height, title),
    PanelStyle.tape => _renderTape(width, height, title),
  };
}

List<String> _renderSimple(int width, int height, String title) {
  final lines = <String>[];
  final innerWidth = width - 2;
  final titleStr = ' $title ';
  final fillCount = max(innerWidth - titleStr.length - 1, 0);
  final top = '\x1b[2m┌─\x1b[0m'
      '\x1b[33m$titleStr\x1b[0m'
      '\x1b[2m${'─' * fillCount}┐\x1b[0m';
  lines.add(top);

  final interior = '\x1b[2m│\x1b[0m'
      '${' ' * innerWidth}'
      '\x1b[2m│\x1b[0m';
  for (var i = 1; i < height - 1; i++) {
    lines.add(interior);
  }

  final bottom = '\x1b[2m└${'─' * innerWidth}┘\x1b[0m';
  lines.add(bottom);
  return lines;
}

List<String> _renderHeavy(int width, int height, String title) {
  final lines = <String>[];
  final innerWidth = width - 2;
  final titleStr = ' $title ';
  final fillCount = max(innerWidth - titleStr.length - 1, 0);
  final top = '\x1b[33m╔═$titleStr${'═' * fillCount}╗\x1b[0m';
  lines.add(top);

  final interior = '\x1b[33m║\x1b[0m'
      '${' ' * innerWidth}'
      '\x1b[33m║\x1b[0m';
  for (var i = 1; i < height - 1; i++) {
    lines.add(interior);
  }

  final bottom = '\x1b[33m╚${'═' * innerWidth}╝\x1b[0m';
  lines.add(bottom);
  return lines;
}

List<String> _renderTape(int width, int height, String title) {
  final lines = <String>[];
  final innerWidth = width - 2;

  final titleStr = ' $title ';
  final tapePattern = '▚▞';
  final prefixLen = 2;
  final suffixLen = max(width - titleStr.length - prefixLen, 0);
  final prefixTape = _repeatTape(tapePattern, prefixLen);
  final suffixTape = _repeatTape(tapePattern, suffixLen);
  final top = '\x1b[33m$prefixTape\x1b[0m'
      '\x1b[30;43m$titleStr\x1b[0m'
      '\x1b[33m$suffixTape\x1b[0m';
  lines.add(top);

  final interior = '\x1b[33m│\x1b[0m'
      '${' ' * innerWidth}'
      '\x1b[33m│\x1b[0m';
  for (var i = 1; i < height - 1; i++) {
    lines.add(interior);
  }

  final bottomTape = _repeatTape(tapePattern, width);
  final bottom = '\x1b[33m$bottomTape\x1b[0m';
  lines.add(bottom);
  return lines;
}

String _repeatTape(String pattern, int length) {
  final buf = StringBuffer();
  for (var i = 0; i < length; i++) {
    buf.write(pattern[i % pattern.length]);
  }
  return buf.toString();
}

List<String> applyBarrier(BarrierStyle style, List<String> lines) {
  return switch (style) {
    BarrierStyle.none => lines,
    BarrierStyle.dim => lines
        .map((line) => '\x1b[2m${stripAnsi(line)}\x1b[0m')
        .toList(),
    BarrierStyle.obscure => lines.map((line) {
        final len = visibleLength(line);
        return '\x1b[90m${'░' * len}\x1b[0m';
      }).toList(),
  };
}
