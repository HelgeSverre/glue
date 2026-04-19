import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/ui/responsive_table.dart';
import 'package:glue/src/ui/table_formatter.dart';

/// A single row for the model picker: one provider's name plus one of its
/// models. Callers flatten the catalog into this shape.
typedef CatalogRow = ({
  String providerId,
  String providerName,
  ModelDef model,
});

/// Result of formatting model entries for the panel.
class ModelPanelLines {
  ModelPanelLines({
    this.headerLines = const [],
    required this.lines,
    required this.entries,
    required this.initialIndex,
  });

  /// Optional header rows shown above selectable lines.
  final List<String> headerLines;

  /// Formatted display lines (one per entry).
  final List<String> lines;

  /// Flat list of entries corresponding 1:1 with [lines].
  final List<CatalogRow> entries;

  /// Index into [entries] for the currently active model, or 0 if none match.
  final int initialIndex;
}

/// Builds the formatted lines for the model-switch panel.
///
/// Columns are sized dynamically so they align regardless of content length.
/// Provider headers are normalised to the widest provider name.
ModelPanelLines formatModelPanelLines(
  List<CatalogRow> entries, {
  required ModelRef currentRef,
  int? maxTotalWidth,
}) {
  if (entries.isEmpty) {
    return ModelPanelLines(
      headerLines: const [],
      lines: const [],
      entries: const [],
      initialIndex: 0,
    );
  }

  final rows = <Map<String, String>>[];
  String? lastProvider;
  var flatInitial = 0;

  for (var i = 0; i < entries.length; i++) {
    final row = entries[i];
    final isCurrent = row.providerId == currentRef.providerId &&
        row.model.id == currentRef.modelId;
    final providerHeader = row.providerId != lastProvider
        ? row.providerName.styled.cyan.toString()
        : '';
    lastProvider = row.providerId;

    final marker = isCurrent ? '\u25cf ' : '  ';
    final name = row.model.name;
    final tag = (row.model.notes ?? '').styled.dim.toString();

    if (isCurrent) flatInitial = i;
    rows.add({
      'provider': providerHeader,
      'marker': marker,
      'name': name,
      'tag': tag,
    });
  }

  final table = TableFormatter.format(
    columns: const [
      TableColumn(key: 'provider', header: 'PROVIDER'),
      TableColumn(key: 'marker', header: ''),
      TableColumn(key: 'name', header: 'MODEL'),
      TableColumn(key: 'tag', header: 'NOTES'),
    ],
    rows: rows,
    maxTotalWidth: maxTotalWidth,
    includeHeader: true,
    includeHeaderInWidth: false,
  );

  return ModelPanelLines(
    headerLines: table.headerLines,
    lines: table.rowLines,
    entries: entries,
    initialIndex: flatInitial,
  );
}

/// Width-aware builder for the model picker.
///
/// Unlike [formatModelPanelLines], this does not pre-render at a fixed width.
/// Instead it holds the row data and re-formats on demand, so the picker
/// can reflow its columns as the user resizes the terminal.
class ModelPanelBuilder {
  ModelPanelBuilder._(this._table, this.initialIndex, this.entries);

  final ResponsiveTable<int> _table;

  /// Index into [entries] for the currently active model, or 0 if none match.
  final int initialIndex;

  /// Flat list of entries corresponding 1:1 with the builder's rows.
  final List<CatalogRow> entries;

  int get rowCount => entries.length;
  List<String> renderHeader(int width) => _table.renderHeader(width);
  String renderRow(int index, int width) => _table.renderRow(index, width);
}

/// Builds a [ModelPanelBuilder] that reflows column widths with the
/// terminal. Provider headers are shown only on the first row of each
/// provider group; the current model is marked with a filled dot.
ModelPanelBuilder buildModelPanel(
  List<CatalogRow> entries, {
  required ModelRef currentRef,
}) {
  var flatInitial = 0;
  final headers = <String>[];
  String? lastProvider;
  for (var i = 0; i < entries.length; i++) {
    final row = entries[i];
    if (row.providerId == currentRef.providerId &&
        row.model.id == currentRef.modelId) {
      flatInitial = i;
    }
    headers.add(
      row.providerId != lastProvider
          ? row.providerName.styled.cyan.toString()
          : '',
    );
    lastProvider = row.providerId;
  }

  final indexed = List<int>.generate(entries.length, (i) => i);
  final table = ResponsiveTable<int>(
    columns: const [
      TableColumn(key: 'provider', header: 'PROVIDER'),
      TableColumn(key: 'marker', header: ''),
      TableColumn(key: 'name', header: 'MODEL'),
      TableColumn(key: 'tag', header: 'NOTES'),
    ],
    rows: indexed,
    getValues: (i) {
      final row = entries[i];
      final isCurrent = row.providerId == currentRef.providerId &&
          row.model.id == currentRef.modelId;
      return {
        'provider': headers[i],
        'marker': isCurrent ? '\u25cf ' : '  ',
        'name': row.model.name,
        'tag': (row.model.notes ?? '').styled.dim.toString(),
      };
    },
  );

  return ModelPanelBuilder._(table, flatInitial, entries);
}

/// Flatten a [ModelCatalog] into rows suitable for the model panel.
///
/// Filters to catalog-default capabilities (from `selection.default_filter`)
/// plus the "has credentials available" check the caller provides.
List<CatalogRow> flattenCatalog(
  ModelCatalog catalog, {
  bool Function(ProviderDef)? where,
}) {
  final rows = <CatalogRow>[];
  for (final provider in catalog.providers.values) {
    if (!provider.enabled) continue;
    if (where != null && !where(provider)) continue;
    for (final model in provider.models.values) {
      rows.add((
        providerId: provider.id,
        providerName: provider.name,
        model: model,
      ));
    }
  }
  return rows;
}
