import 'dart:math';

import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/config/model_registry.dart';

/// Result of formatting model entries for the panel.
class ModelPanelLines {
  /// Formatted display lines (one per entry).
  final List<String> lines;

  /// Flat list of entries corresponding 1:1 with [lines].
  final List<ModelEntry> entries;

  /// Index into [entries] for the currently active model, or 0 if none match.
  final int initialIndex;

  ModelPanelLines({
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
}) {
  if (entries.isEmpty) {
    return ModelPanelLines(lines: [], entries: [], initialIndex: 0);
  }

  const dim = '\x1b[90m';
  const yellow = '\x1b[33m';
  const rst = '\x1b[0m';

  // Compute dynamic column widths from the data.
  final maxProvider =
      entries.fold<int>(0, (m, e) => max(m, e.provider.name.length));
  final maxName = entries.fold<int>(0, (m, e) => max(m, e.displayName.length));
  final maxTag = entries.fold<int>(0, (m, e) => max(m, e.tagline.length));
  final maxCost = entries.fold<int>(0, (m, e) => max(m, e.costLabel.length));

  final flatLines = <String>[];
  final flatEntries = <ModelEntry>[];
  LlmProvider? lastProvider;
  var flatInitial = 0;

  for (final entry in entries) {
    final isCurrent = entry.modelId == currentModelId;

    // Provider header: show name for first entry of a group, spaces otherwise.
    final providerHeader = entry.provider != lastProvider
        ? '$yellow${entry.provider.name.padRight(maxProvider)}$rst  '
        : ' ' * (maxProvider + 2);
    lastProvider = entry.provider;

    final marker = isCurrent ? '\u25cf ' : '  ';
    final name = entry.displayName.padRight(maxName);
    final tag = entry.tagline.padRight(maxTag);
    final cost = entry.costLabel.padRight(maxCost);
    final speed = entry.speedLabel;

    if (isCurrent) flatInitial = flatEntries.length;
    flatLines.add('$providerHeader$marker$name $dim$tag$rst $cost $speed');
    flatEntries.add(entry);
  }

  return ModelPanelLines(
    lines: flatLines,
    entries: flatEntries,
    initialIndex: flatInitial,
  );
}
