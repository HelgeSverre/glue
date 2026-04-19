/// Width-aware wrapper over [TableFormatter]. Holds rows + column spec;
/// produces header/row strings for any requested content width. Cheap to
/// re-query: the last format() call is cached, so consecutive queries at
/// the same width reuse the same TableRender.
library;

import 'package:glue/src/ui/table_formatter.dart';

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
