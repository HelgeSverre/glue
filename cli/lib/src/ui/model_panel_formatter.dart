import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/config/model_registry.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/ui/table_formatter.dart';

/// Result of formatting model entries for the panel.
class ModelPanelLines {
  /// Optional header rows shown above selectable lines.
  final List<String> headerLines;

  /// Formatted display lines (one per entry).
  final List<String> lines;

  /// Flat list of entries corresponding 1:1 with [lines].
  final List<ModelEntry> entries;

  /// Index into [entries] for the currently active model, or 0 if none match.
  final int initialIndex;

  ModelPanelLines({
    this.headerLines = const [],
    required this.lines,
    required this.entries,
    required this.initialIndex,
  });
}

/// Builds the formatted lines for the model-switch panel.
///
/// Columns are sized dynamically so they align regardless of content length.
/// Provider headers are normalised to the widest provider name.
ModelPanelLines formatModelPanelLines(
  List<ModelEntry> entries, {
  required String currentModelId,
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
  final flatEntries = <ModelEntry>[];
  LlmProvider? lastProvider;
  var flatInitial = 0;

  for (final entry in entries) {
    final isCurrent = entry.modelId == currentModelId;
    final providerHeader = entry.provider != lastProvider
        ? entry.provider.name.styled.cyan.toString()
        : '';
    lastProvider = entry.provider;

    final marker = isCurrent ? '\u25cf ' : '  ';
    final name = entry.displayName;
    final tag = entry.tagline.styled.dim.toString();
    final cost = entry.costLabel;
    final speed = entry.speedLabel;

    if (isCurrent) flatInitial = flatEntries.length;
    rows.add({
      'provider': providerHeader,
      'marker': marker,
      'name': name,
      'tag': tag,
      'cost': cost,
      'speed': speed,
    });
    flatEntries.add(entry);
  }

  final table = TableFormatter.format(
    columns: const [
      TableColumn(key: 'provider', header: 'PROVIDER'),
      TableColumn(key: 'marker', header: ''),
      TableColumn(key: 'name', header: 'MODEL'),
      TableColumn(key: 'tag', header: 'TAGLINE'),
      TableColumn(key: 'cost', header: 'COST', align: TableAlign.right),
      TableColumn(key: 'speed', header: 'SPEED', align: TableAlign.right),
    ],
    rows: rows,
    maxTotalWidth: maxTotalWidth,
    includeHeader: true,
    includeHeaderInWidth: false,
  );

  return ModelPanelLines(
    headerLines: table.headerLines,
    lines: table.rowLines,
    entries: flatEntries,
    initialIndex: flatInitial,
  );
}
