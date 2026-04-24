import 'dart:math';

import 'package:glue/src/ui/rendering/ansi_utils.dart';

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
    int? maxTotalWidth,
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
    _fitWidthsToBudget(
      columns: columns,
      widths: widths,
      gapWidth: visibleLength(gap),
      maxTotalWidth: maxTotalWidth,
    );

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

  static void _fitWidthsToBudget({
    required List<TableColumn> columns,
    required Map<String, int> widths,
    required int gapWidth,
    required int? maxTotalWidth,
  }) {
    if (maxTotalWidth == null || maxTotalWidth <= 0 || columns.isEmpty) return;

    int totalWidth() {
      final cols = columns.fold<int>(0, (sum, c) => sum + (widths[c.key] ?? 0));
      final gaps = gapWidth * (columns.isNotEmpty ? columns.length - 1 : 0);
      return cols + gaps;
    }

    var currentTotal = totalWidth();
    if (currentTotal <= maxTotalWidth) return;

    while (currentTotal > maxTotalWidth) {
      TableColumn? candidate;
      var candidateSlack = 0;

      for (final column in columns) {
        final width = widths[column.key] ?? 0;
        final slack = width - column.minWidth;
        if (slack > candidateSlack) {
          candidate = column;
          candidateSlack = slack;
        }
      }

      if (candidate == null || candidateSlack <= 0) {
        break;
      }

      widths[candidate.key] = (widths[candidate.key] ?? 0) - 1;
      currentTotal--;
    }
  }
}

class ResponsiveTable<T> {
  ResponsiveTable({
    required this.columns,
    required List<T> rows,
    required Map<String, String> Function(T row) getValues,
    this.gap = '  ',
    this.includeDivider = true,
    this.includeHeaderInWidth = false,
  })  : _rows = rows.map(getValues).toList(growable: false),
        _sources = List<T>.from(rows, growable: false);

  final List<TableColumn> columns;
  final List<Map<String, String>> _rows;
  final List<T> _sources;
  final String gap;
  final bool includeDivider;
  final bool includeHeaderInWidth;

  int? _cachedWidth;
  TableRender? _cached;

  int get rowCount => _rows.length;
  T sourceAt(int index) => _sources[index];

  TableRender _renderAt(int width) {
    if (_cachedWidth == width && _cached != null) return _cached!;
    _cached = TableFormatter.format(
      columns: columns,
      rows: _rows,
      gap: gap,
      maxTotalWidth: width,
      includeHeader: true,
      includeHeaderInWidth: includeHeaderInWidth,
      includeDivider: includeDivider,
    );
    _cachedWidth = width;
    return _cached!;
  }

  List<String> renderHeader(int width) => _renderAt(width).headerLines;
  String renderRow(int index, int width) => _renderAt(width).rowLines[index];
}
