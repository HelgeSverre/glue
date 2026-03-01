import 'dart:math';

import 'package:test/test.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/config/model_registry.dart';
import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/ui/model_panel_formatter.dart';

/// Build a [ModelEntry] with the given overrides.
ModelEntry _entry({
  String displayName = 'Test Model',
  String modelId = 'test-model',
  LlmProvider provider = LlmProvider.anthropic,
  String tagline = 'A tagline',
  CostTier cost = CostTier.medium,
  SpeedTier speed = SpeedTier.standard,
  bool isDefault = false,
}) =>
    ModelEntry(
      displayName: displayName,
      modelId: modelId,
      provider: provider,
      capabilities: const {},
      cost: cost,
      speed: speed,
      tagline: tagline,
      isDefault: isDefault,
    );

/// Computes the expected marker column based on the entries' provider names.
int _expectedMarkerCol(List<ModelEntry> entries) {
  final maxProvider =
      entries.fold<int>(0, (m, e) => max(m, e.provider.name.length));
  return maxProvider + 2; // provider padded to max + 2-char gap
}

void main() {
  group('formatModelPanelLines', () {
    test('empty entries returns empty result', () {
      final result = formatModelPanelLines([], currentModelId: 'x');
      expect(result.lines, isEmpty);
      expect(result.entries, isEmpty);
      expect(result.initialIndex, 0);
    });

    test('single entry produces one line', () {
      final result = formatModelPanelLines(
        [_entry()],
        currentModelId: 'other',
      );
      expect(result.lines, hasLength(1));
      expect(result.entries, hasLength(1));
      expect(result.initialIndex, 0);
    });

    test('current model is marked with bullet', () {
      final entries = [
        _entry(modelId: 'a', displayName: 'Alpha'),
        _entry(modelId: 'b', displayName: 'Beta'),
      ];
      final result = formatModelPanelLines(
        entries,
        currentModelId: 'b',
      );
      final markerCol = _expectedMarkerCol(entries);
      final plainA = stripAnsi(result.lines[0]);
      final plainB = stripAnsi(result.lines[1]);
      // Non-current entry has spaces at marker column.
      expect(plainA.substring(markerCol, markerCol + 2), '  ');
      // Current entry has bullet at marker column.
      expect(plainB.substring(markerCol, markerCol + 2), '\u25cf ');
      expect(result.initialIndex, 1);
    });

    test('no current model match yields initialIndex 0', () {
      final result = formatModelPanelLines(
        [_entry(modelId: 'a'), _entry(modelId: 'b')],
        currentModelId: 'nonexistent',
      );
      expect(result.initialIndex, 0);
    });

    group('column alignment', () {
      /// Verify all lines have the same visible width.
      void expectEqualVisibleWidth(List<String> lines) {
        final widths = lines.map(visibleLength).toSet();
        expect(widths, hasLength(1),
            reason: 'All lines should have the same visible width.\n'
                'Got widths: ${lines.map(visibleLength).toList()}\n'
                'Lines:\n${lines.map(stripAnsi).join('\n')}');
      }

      test('lines have equal visible width with the real registry', () {
        final result = formatModelPanelLines(
          ModelRegistry.models,
          currentModelId: 'claude-sonnet-4-6',
        );
        expectEqualVisibleWidth(result.lines);
      });

      test('lines align with very long display names', () {
        final entries = [
          _entry(
            displayName: 'Short',
            modelId: 'short',
            tagline: 'Fast',
          ),
          _entry(
            displayName: 'Extremely Long Model Display Name v42',
            modelId: 'long',
            tagline: 'Fast',
          ),
        ];
        final result =
            formatModelPanelLines(entries, currentModelId: 'none');
        expectEqualVisibleWidth(result.lines);
      });

      test('lines align with very long taglines', () {
        final entries = [
          _entry(displayName: 'A', tagline: 'Short'),
          _entry(
            displayName: 'B',
            tagline: 'An extraordinarily verbose tagline that far exceeds '
                'any reasonable column width',
          ),
        ];
        final result =
            formatModelPanelLines(entries, currentModelId: 'none');
        expectEqualVisibleWidth(result.lines);
      });

      test('lines align across different provider groups', () {
        // Provider names have different lengths: anthropic=9, openai=6.
        final entries = [
          _entry(
            provider: LlmProvider.anthropic,
            displayName: 'Claude Sonnet 4.6',
            modelId: 'claude-sonnet-4-6',
            tagline: 'Balanced power and speed',
          ),
          _entry(
            provider: LlmProvider.anthropic,
            displayName: 'Claude Haiku 3.5',
            modelId: 'claude-haiku-3-5',
            tagline: 'Fast and cheap',
          ),
          _entry(
            provider: LlmProvider.openai,
            displayName: 'GPT-4.1',
            modelId: 'gpt-4.1',
            tagline: 'Latest flagship',
          ),
          _entry(
            provider: LlmProvider.ollama,
            displayName: 'Llama 3.2',
            modelId: 'llama3.2',
            tagline: 'Local and free',
            cost: CostTier.free,
          ),
        ];
        final result =
            formatModelPanelLines(entries, currentModelId: 'none');
        expectEqualVisibleWidth(result.lines);

        // Verify the marker column is at the expected position for all lines.
        final markerCol = _expectedMarkerCol(entries); // 9 + 2 = 11
        for (final line in result.lines) {
          final plain = stripAnsi(line);
          // Every line should have 2 spaces (no bullet) at the marker column
          // since currentModelId='none' matches nothing.
          expect(plain.substring(markerCol, markerCol + 2), '  ',
              reason: 'Marker column should be at position $markerCol.\n'
                  'Line: $plain');
        }
      });

      test('continuation rows align with header row within a group', () {
        // Two entries from same provider: first shows header, second shows spaces.
        final entries = [
          _entry(
            provider: LlmProvider.anthropic,
            displayName: 'Model A',
            modelId: 'a',
            tagline: 'Tag A',
          ),
          _entry(
            provider: LlmProvider.anthropic,
            displayName: 'Model B',
            modelId: 'b',
            tagline: 'Tag B',
          ),
        ];
        final result =
            formatModelPanelLines(entries, currentModelId: 'none');
        expectEqualVisibleWidth(result.lines);

        // Provider header row and continuation row should have equal length.
        expect(visibleLength(result.lines[0]),
            visibleLength(result.lines[1]));
      });

      test('all cost tiers produce equal-width lines', () {
        final entries = CostTier.values.map((c) {
          return _entry(
            modelId: 'model-${c.name}',
            cost: c,
            tagline: 'Same tagline',
          );
        }).toList();
        final result =
            formatModelPanelLines(entries, currentModelId: 'none');
        expectEqualVisibleWidth(result.lines);
      });
    });

    group('stress: many entries', () {
      test('50 models across all providers maintain alignment', () {
        final entries = <ModelEntry>[];
        final providers = LlmProvider.values;
        for (var i = 0; i < 50; i++) {
          final p = providers[i % providers.length];
          entries.add(_entry(
            provider: p,
            displayName: 'Model ${i.toString().padLeft(2, '0')}',
            modelId: 'model-$i',
            tagline: 'Tagline for model $i',
            cost: CostTier.values[i % CostTier.values.length],
            speed: SpeedTier.values[i % SpeedTier.values.length],
          ));
        }
        final result =
            formatModelPanelLines(entries, currentModelId: 'model-25');
        expect(result.lines, hasLength(50));
        expect(result.initialIndex, 25);

        // All lines same visible width.
        final widths = result.lines.map(visibleLength).toSet();
        expect(widths, hasLength(1),
            reason: 'All 50 lines should have equal visible width');
      });
    });

    group('stress: extreme content', () {
      test('single-char display name and tagline', () {
        final entries = [
          _entry(displayName: 'X', tagline: 'Y', modelId: 'x'),
          _entry(displayName: 'AB', tagline: 'CD', modelId: 'ab'),
        ];
        final result =
            formatModelPanelLines(entries, currentModelId: 'none');
        final widths = result.lines.map(visibleLength).toSet();
        expect(widths, hasLength(1));
      });

      test('100-char display name does not crash', () {
        final longName = 'A' * 100;
        final entries = [
          _entry(displayName: longName, modelId: 'long'),
          _entry(displayName: 'Short', modelId: 'short'),
        ];
        final result =
            formatModelPanelLines(entries, currentModelId: 'none');
        expect(result.lines, hasLength(2));
        final widths = result.lines.map(visibleLength).toSet();
        expect(widths, hasLength(1));
        // The long name should appear in full (not truncated — panel handles that).
        expect(stripAnsi(result.lines[0]), contains(longName));
      });

      test('empty tagline still aligns', () {
        final entries = [
          _entry(displayName: 'Alpha', tagline: '', modelId: 'a'),
          _entry(
              displayName: 'Beta', tagline: 'Has a tagline', modelId: 'b'),
        ];
        final result =
            formatModelPanelLines(entries, currentModelId: 'none');
        final widths = result.lines.map(visibleLength).toSet();
        expect(widths, hasLength(1));
      });
    });

    group('provider header', () {
      test('first entry of each provider shows provider name', () {
        final entries = [
          _entry(provider: LlmProvider.anthropic, modelId: 'a'),
          _entry(provider: LlmProvider.openai, modelId: 'b'),
        ];
        final result =
            formatModelPanelLines(entries, currentModelId: 'none');
        expect(stripAnsi(result.lines[0]), startsWith('anthropic'));
        expect(stripAnsi(result.lines[1]), startsWith('openai'));
      });

      test('continuation entry shows spaces instead of provider name', () {
        final entries = [
          _entry(
              provider: LlmProvider.anthropic,
              modelId: 'a',
              displayName: 'First'),
          _entry(
              provider: LlmProvider.anthropic,
              modelId: 'b',
              displayName: 'Second'),
        ];
        final result =
            formatModelPanelLines(entries, currentModelId: 'none');
        final plain0 = stripAnsi(result.lines[0]);
        final plain1 = stripAnsi(result.lines[1]);
        // First line shows provider.
        expect(plain0, startsWith('anthropic'));
        // Second line starts with spaces of equal width.
        expect(plain1, startsWith(' ' * ('anthropic'.length)));
        // But both have same total width.
        expect(visibleLength(result.lines[0]),
            visibleLength(result.lines[1]));
      });

      test('provider name is padded to widest provider', () {
        // anthropic=9, ollama=6 → both padded to 9.
        final entries = [
          _entry(provider: LlmProvider.anthropic, modelId: 'a'),
          _entry(provider: LlmProvider.ollama, modelId: 'b'),
        ];
        final result =
            formatModelPanelLines(entries, currentModelId: 'none');
        // Both lines should have equal visible width.
        expect(visibleLength(result.lines[0]),
            visibleLength(result.lines[1]));
        // The ollama line should have the provider name padded to 9 chars
        // (matching anthropic).
        final plain1 = stripAnsi(result.lines[1]);
        // "ollama" (6) + 3 pad + 2 gap = 11 leading chars before marker.
        expect(plain1.substring(0, 9 + 2), 'ollama' + ' ' * 5);
      });
    });

    group('entries mapping', () {
      test('entries list matches input order', () {
        final e1 = _entry(modelId: 'first');
        final e2 = _entry(modelId: 'second');
        final result =
            formatModelPanelLines([e1, e2], currentModelId: 'none');
        expect(result.entries[0].modelId, 'first');
        expect(result.entries[1].modelId, 'second');
      });
    });
  });
}
