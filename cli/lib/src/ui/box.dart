import 'dart:math';

/// Immutable set of box-drawing characters for rectangular borders.
///
/// Inspired by Rich's `Box` class — pure data with rendering helpers.
/// Separates character definitions (what to draw) from color (how to style).
class Box {
  final String topLeft, top, topRight;
  final String left, right;
  final String bottomLeft, bottom, bottomRight;

  const Box({
    required this.topLeft,
    required this.top,
    required this.topRight,
    required this.left,
    required this.right,
    required this.bottomLeft,
    required this.bottom,
    required this.bottomRight,
  });

  /// Light box-drawing: ┌─┐│└┘
  static const light = Box(
    topLeft: '┌',
    top: '─',
    topRight: '┐',
    left: '│',
    right: '│',
    bottomLeft: '└',
    bottom: '─',
    bottomRight: '┘',
  );

  /// Heavy/double box-drawing: ╔═╗║╚╝
  static const heavy = Box(
    topLeft: '╔',
    top: '═',
    topRight: '╗',
    left: '║',
    right: '║',
    bottomLeft: '╚',
    bottom: '═',
    bottomRight: '╝',
  );

  /// Rounded box-drawing: ╭─╮│╰╯
  static const rounded = Box(
    topLeft: '╭',
    top: '─',
    topRight: '╮',
    left: '│',
    right: '│',
    bottomLeft: '╰',
    bottom: '─',
    bottomRight: '╯',
  );

  /// Render a complete border frame: top line with title, empty interior rows,
  /// and bottom line. Returns [height] lines, each [width] visible columns.
  ///
  /// [color] is the ANSI escape for the border characters (e.g. `'\x1b[2m'`
  /// for dim, `'\x1b[33m'` for yellow). Title is always yellow.
  List<String> renderFrame(
    int width,
    int height,
    String title, {
    String color = '\x1b[2m',
  }) {
    const rst = '\x1b[0m';
    final innerWidth = width - 2;
    final titleStr = ' $title ';
    final fillCount = max(innerWidth - titleStr.length - 1, 0);

    final lines = <String>[];

    // Top border with title
    lines.add(
      '$color$topLeft$top$rst'
      '\x1b[33m$titleStr$rst'
      '$color${top * fillCount}$topRight$rst',
    );

    // Interior (empty rows with side borders)
    final interior =
        '$color$left$rst'
        '${' ' * innerWidth}'
        '$color$right$rst';
    for (var i = 1; i < height - 1; i++) {
      lines.add(interior);
    }

    // Bottom border
    lines.add('$color$bottomLeft${bottom * innerWidth}$bottomRight$rst');
    return lines;
  }

  /// ANSI-styled left and right border strings for content rows.
  (String, String) styledSides({String color = '\x1b[2m'}) {
    const rst = '\x1b[0m';
    return ('$color$left$rst', '$color$right$rst');
  }
}
