import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/ui/model_panel_formatter.dart';
import 'package:test/test.dart';

CatalogRow _row({
  String providerId = 'anthropic',
  String providerName = 'Anthropic',
  String modelId = 'claude-sonnet-4.6',
  String modelName = 'Claude Sonnet 4.6',
  String? notes,
  String? cost,
  String? speed,
}) =>
    (
      providerId: providerId,
      providerName: providerName,
      model: ModelDef(
        id: modelId,
        name: modelName,
        notes: notes,
        cost: cost,
        speed: speed,
      ),
    );

ModelRef _ref(String s) => ModelRef.parse(s);

void main() {
  group('formatModelPanelLines', () {
    test('empty entries returns empty result', () {
      final result = formatModelPanelLines(
        const [],
        currentRef: _ref('anthropic/x'),
      );
      expect(result.lines, isEmpty);
      expect(result.entries, isEmpty);
      expect(result.initialIndex, 0);
    });

    test('single entry produces one line', () {
      final rows = [_row()];
      final result = formatModelPanelLines(
        rows,
        currentRef: _ref('other/x'),
      );
      expect(result.lines, hasLength(1));
      expect(stripAnsi(result.lines.first), contains('Claude Sonnet 4.6'));
    });

    test('marks the current model with a filled dot', () {
      final rows = [
        _row(),
        _row(modelId: 'claude-haiku-4-5', modelName: 'Haiku')
      ];
      final result = formatModelPanelLines(
        rows,
        currentRef: _ref('anthropic/claude-haiku-4-5'),
      );
      expect(result.initialIndex, 1);
      final activeLine = stripAnsi(result.lines[1]);
      expect(activeLine, contains('\u25cf'));
    });

    test('provider header only shown on first row per provider', () {
      final rows = [
        _row(modelId: 'a1'),
        _row(modelId: 'a2'),
        _row(providerId: 'openai', providerName: 'OpenAI', modelId: 'o1'),
      ];
      final result = formatModelPanelLines(
        rows,
        currentRef: _ref('anthropic/a1'),
      );
      final lines = result.lines.map(stripAnsi).toList();
      expect(lines[0], contains('Anthropic'));
      expect(lines[1], isNot(contains('Anthropic')));
      expect(lines[2], contains('OpenAI'));
    });
  });

  group('flattenCatalog', () {
    test('walks providers + models with optional filter', () {
      const catalog = ModelCatalog(
        version: 1,
        updatedAt: '2026-04-19',
        defaults: DefaultsConfig(model: 'anthropic/claude-sonnet-4.6'),
        capabilities: {},
        providers: {
          'anthropic': ProviderDef(
            id: 'anthropic',
            name: 'Anthropic',
            adapter: 'anthropic',
            auth: AuthSpec(kind: AuthKind.apiKey, envVar: 'ANTHROPIC_API_KEY'),
            models: {
              'claude-sonnet-4.6': ModelDef(
                id: 'claude-sonnet-4.6',
                name: 'Claude Sonnet',
              ),
            },
          ),
          'disabled': ProviderDef(
            id: 'disabled',
            name: 'Disabled',
            adapter: 'openai',
            enabled: false,
            auth: AuthSpec(kind: AuthKind.none),
            models: {'x': ModelDef(id: 'x', name: 'X')},
          ),
        },
      );
      final rows = flattenCatalog(catalog);
      expect(rows, hasLength(1));
      expect(rows.first.providerId, 'anthropic');
    });
  });
}
