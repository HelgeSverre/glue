import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/providers/ollama_discovery.dart';
import 'package:glue/src/catalog/model_panel_formatter.dart';
import 'package:test/test.dart';

CatalogRow _ollamaRow(String id) => (
      providerId: 'ollama',
      providerName: 'Ollama',
      model: ModelDef(id: id, name: id, capabilities: const {'chat', 'tools'}),
      availability: ModelAvailability.unknown,
    );

CatalogRow _anthropicRow() => (
      providerId: 'anthropic',
      providerName: 'Anthropic',
      model: const ModelDef(
        id: 'claude-sonnet-4-6',
        name: 'Claude Sonnet 4.6',
        capabilities: {'chat', 'tools'},
      ),
      availability: ModelAvailability.unknown,
    );

OllamaInstalledModel _tag(String t) => OllamaInstalledModel(
      tag: t,
      sizeBytes: 0,
      modifiedAt: null,
    );

void main() {
  group('mergeOllamaDiscovery', () {
    test('empty discovery leaves rows untouched (daemon down)', () {
      final rows = [_ollamaRow('qwen3-coder:30b'), _anthropicRow()];
      final merged = mergeOllamaDiscovery(rows, const []);
      expect(merged, rows);
    });

    test('catalogued + pulled → installed marker', () {
      final merged = mergeOllamaDiscovery(
        [_ollamaRow('qwen3-coder:30b')],
        [_tag('qwen3-coder:30b')],
      );
      expect(merged.length, 1);
      expect(merged[0].availability, ModelAvailability.installed);
    });

    test('catalogued but not pulled → notInstalled marker', () {
      final merged = mergeOllamaDiscovery(
        [_ollamaRow('qwen3-coder:30b')],
        [_tag('some-other-tag:latest')],
      );
      // The catalog entry is now marked notInstalled, and the tag-only
      // model is appended as installedOnly.
      expect(merged.length, 2);
      expect(
        merged.singleWhere((r) => r.model.id == 'qwen3-coder:30b').availability,
        ModelAvailability.notInstalled,
      );
      expect(
        merged
            .singleWhere((r) => r.model.id == 'some-other-tag:latest')
            .availability,
        ModelAvailability.installedOnly,
      );
    });

    test('pulled tag not in catalog is synthesised as a row', () {
      final merged = mergeOllamaDiscovery(
        [_anthropicRow()],
        [_tag('experimental:42b')],
      );
      final synth = merged.singleWhere((r) => r.model.id == 'experimental:42b');
      expect(synth.providerId, 'ollama');
      expect(synth.availability, ModelAvailability.installedOnly);
      expect(synth.model.notes, 'Installed locally.');
    });

    test('non-Ollama rows are never touched', () {
      final merged = mergeOllamaDiscovery(
        [_anthropicRow()],
        [_tag('qwen3-coder:30b')],
      );
      // The anthropic row keeps unknown; the tag becomes a synthetic Ollama row.
      expect(
        merged.singleWhere((r) => r.providerId == 'anthropic').availability,
        ModelAvailability.unknown,
      );
    });

    test('four availability buckets coexist on a mixed input', () {
      final rows = [
        _anthropicRow(), // unknown (non-Ollama)
        _ollamaRow('qwen3-coder:30b'), // installed
        _ollamaRow('gemma4:26b'), // notInstalled
      ];
      final merged = mergeOllamaDiscovery(
        rows,
        [_tag('qwen3-coder:30b'), _tag('random:7b')],
      );

      final buckets = {for (final r in merged) r.model.id: r.availability};
      expect(buckets['claude-sonnet-4-6'], ModelAvailability.unknown);
      expect(buckets['qwen3-coder:30b'], ModelAvailability.installed);
      expect(buckets['gemma4:26b'], ModelAvailability.notInstalled);
      expect(buckets['random:7b'], ModelAvailability.installedOnly);
    });
  });
}
