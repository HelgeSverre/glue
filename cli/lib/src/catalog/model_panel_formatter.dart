import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/providers/ollama_discovery.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/ui/components/tables.dart';

/// Per-row availability hint — today only Ollama reports more than
/// [unknown]. Lets the picker annotate catalog rows with "not pulled"
/// and surface tag-only installs the user may want to pick.
enum ModelAvailability {
  /// No information (non-Ollama or discovery disabled).
  unknown,

  /// Catalogued and confirmed present locally.
  installed,

  /// Catalogued but the user hasn't pulled it yet.
  notInstalled,

  /// Pulled locally but not in our curated catalog — we synthesised the
  /// row from `/api/tags`.
  installedOnly,
}

/// A single row for the model picker: one provider's name plus one of its
/// models. Callers flatten the catalog into this shape.
typedef CatalogRow = ({
  String providerId,
  String providerName,
  ModelDef model,
  ModelAvailability availability,
});

/// Width-aware builder for the model picker.
///
/// Holds the row data and re-formats on demand, so the picker can reflow
/// its columns as the user resizes the terminal.
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
        'tag': _renderNotesWithAvailability(row),
      };
    },
  );

  return ModelPanelBuilder._(table, flatInitial, entries);
}

/// Flatten a [ModelCatalog] into rows suitable for the model panel.
///
/// Filters to catalog-default capabilities (from `selection.default_filter`)
/// plus the "has credentials available" check the caller provides. All rows
/// have [ModelAvailability.unknown] — call [mergeOllamaDiscovery] afterwards
/// to attach availability hints for Ollama.
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
        availability: ModelAvailability.unknown,
      ));
    }
  }
  return rows;
}

/// Merge Ollama's `/api/tags` output into a flat catalog row list.
///
/// - Rows whose provider is `ollama` get [ModelAvailability.installed] if
///   the catalog id matches a pulled tag, else [ModelAvailability.notInstalled].
/// - Pulled tags that have no catalog entry are appended as synthesised
///   rows with [ModelAvailability.installedOnly]; they use the tag as both
///   id and display name, carry no capability claims, and render with the
///   `[local]` marker.
/// - Non-Ollama rows are returned unchanged.
/// - [installedTags] being empty (daemon down, timeout) leaves catalog
///   rows untouched — no false "not pulled" markers when we don't know.
List<CatalogRow> mergeOllamaDiscovery(
  List<CatalogRow> rows,
  List<OllamaInstalledModel> installedTags, {
  String providerName = 'Ollama',
}) {
  if (installedTags.isEmpty) return rows;
  final installed = {for (final m in installedTags) m.tag};

  final out = <CatalogRow>[];
  final catalogued = <String>{};

  for (final row in rows) {
    if (row.providerId != 'ollama') {
      out.add(row);
      continue;
    }
    catalogued.add(row.model.id);
    out.add((
      providerId: row.providerId,
      providerName: row.providerName,
      model: row.model,
      availability: installed.contains(row.model.id)
          ? ModelAvailability.installed
          : ModelAvailability.notInstalled,
    ));
  }

  for (final tag in installedTags) {
    if (catalogued.contains(tag.tag)) continue;
    out.add((
      providerId: 'ollama',
      providerName: providerName,
      model: ModelDef(
        id: tag.tag,
        name: tag.tag,
        notes: 'Installed locally.',
      ),
      availability: ModelAvailability.installedOnly,
    ));
  }
  return out;
}

String _renderNotesWithAvailability(CatalogRow row) {
  final notes = row.model.notes ?? '';
  final prefix = switch (row.availability) {
    ModelAvailability.notInstalled => '[pull] ',
    ModelAvailability.installedOnly => '[local] ',
    ModelAvailability.installed || ModelAvailability.unknown => '',
  };
  return '$prefix$notes'.styled.dim.toString();
}
