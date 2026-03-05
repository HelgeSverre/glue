import 'dart:math';

import 'package:glue/src/rendering/ansi_utils.dart';

enum TableAlign { left, right }

class TableColumn {
  final String key;
  final String header;
  final TableAlign align;
  final int minWidth;
  final int? maxWidth;

  const TableColumn({
    required this.key,
    required this.header,
    this.align = TableAlign.left,
    this.minWidth = 0,
    this.maxWidth,
  });
}

class TableRender {
  final List<String> headerLines;
  final List<String> rowLines;

  const TableRender({
    required this.headerLines,
    required this.rowLines,
  });
}

class TableFormatter {
  const TableFormatter._();

  static TableRender format({
    required List<TableColumn> columns,
    required List<Map<String, String>> rows,
    String gap = '  ',
    bool includeHeader = true,
    bool includeHeaderInWidth = true,
    bool includeDivider = true,
    String? headerStylePrefix = '\x1b[90m',
    String? headerStyleSuffix = '\x1b[0m',
  }) {
    if (columns.isEmpty) {
      return const TableRender(headerLines: [], rowLines: []);
    }

    final widths = <String, int>{};
    for (final column in columns) {
      var width = column.minWidth;
      if (includeHeaderInWidth) {
        width = max(width, visibleLength(column.header));
      }
      for (final row in rows) {
        final value = row[column.key] ?? '';
        width = max(width, visibleLength(value));
      }
      if (column.maxWidth != null) {
        width = min(width, column.maxWidth!);
      }
      widths[column.key] = width;
    }

    String padCell(String raw, TableColumn column) {
      final width = widths[column.key]!;
      final truncated = ansiTruncate(raw, width);
      final visLen = visibleLength(truncated);
      final padding = ' ' * max(0, width - visLen);
      return column.align == TableAlign.right
          ? '$padding$truncated'
          : '$truncated$padding';
    }

    String renderRow(Map<String, String> row) {
      return columns
          .map((column) => padCell(row[column.key] ?? '', column))
          .join(gap);
    }

    final rowLines = rows.map(renderRow).toList(growable: false);
    final headerLines = <String>[];
    if (includeHeader) {
      final headerMap = {
        for (final column in columns) column.key: column.header,
      };
      final header = renderRow(headerMap);
      final totalWidth = visibleLength(header);
      final divider = '─' * totalWidth;
      if (headerStylePrefix != null && headerStyleSuffix != null) {
        headerLines.add('$headerStylePrefix$header$headerStyleSuffix');
        if (includeDivider) {
          headerLines.add('$headerStylePrefix$divider$headerStyleSuffix');
        }
      } else {
        headerLines.add(header);
        if (includeDivider) headerLines.add(divider);
      }
    }

    return TableRender(
      headerLines: headerLines,
      rowLines: rowLines,
    );
  }
}
