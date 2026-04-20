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
  ModelAvailability availability = ModelAvailability.unknown,
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
      availability: availability,
    );

ModelRef _ref(String s) => ModelRef.parse(s);

void main() {
  group('buildModelPanel', () {
    final entry = _row(
      notes: 'A fairly long notes column to compress on narrow terminals',
    );

    test('renders wider output at a wider content width', () {
      final builder = buildModelPanel(
        [entry],
        currentRef: _ref('anthropic/claude-sonnet-4.6'),
      );
      final wide = builder.renderRow(0, 80);
      final narrow = builder.renderRow(0, 28);
      expect(
        stripAnsi(wide).length,
        greaterThanOrEqualTo(stripAnsi(narrow).length),
      );
    });

    test('initialIndex points to the current model', () {
      final entries = [
        entry,
        _row(modelId: 'haiku', modelName: 'Haiku'),
      ];
      final builder = buildModelPanel(
        entries,
        currentRef: _ref('anthropic/haiku'),
      );
      expect(builder.initialIndex, 1);
    });

    test('empty entries still produces a valid builder', () {
      final builder = buildModelPanel(
        const [],
        currentRef: _ref('x/y'),
      );
      expect(builder.rowCount, 0);
      expect(builder.initialIndex, 0);
    });

    test('provider header appears only on the first row of each group', () {
      final entries = [
        entry,
        _row(modelId: 'haiku', modelName: 'Haiku'),
      ];
      final builder = buildModelPanel(
        entries,
        currentRef: _ref('x/y'),
      );
      final row0 = stripAnsi(builder.renderRow(0, 80));
      final row1 = stripAnsi(builder.renderRow(1, 80));
      expect(row0, contains('Anthropic'));
      // Row 1 should NOT contain the provider name (it was blanked out).
      expect(row1.contains('Anthropic'), isFalse);
    });

    test('provider header appears on first row of each distinct group', () {
      final entries = <CatalogRow>[
        (
          providerId: 'anthropic',
          providerName: 'Anthropic',
          model: const ModelDef(
            id: 'sonnet',
            name: 'Sonnet',
            capabilities: {'chat'},
          ),
          availability: ModelAvailability.unknown,
        ),
        (
          providerId: 'anthropic',
          providerName: 'Anthropic',
          model: const ModelDef(
            id: 'haiku',
            name: 'Haiku',
            capabilities: {'chat'},
          ),
          availability: ModelAvailability.unknown,
        ),
        (
          providerId: 'openai',
          providerName: 'OpenAI',
          model: const ModelDef(
            id: 'gpt-4',
            name: 'GPT-4',
            capabilities: {'chat'},
          ),
          availability: ModelAvailability.unknown,
        ),
      ];
      final builder = buildModelPanel(
        entries,
        currentRef: const ModelRef(providerId: 'x', modelId: 'y'),
      );
      final row0 = stripAnsi(builder.renderRow(0, 80));
      final row1 = stripAnsi(builder.renderRow(1, 80));
      final row2 = stripAnsi(builder.renderRow(2, 80));
      expect(row0, contains('Anthropic'));
      // Row 1: same provider as row 0, header suppressed.
      expect(row1.contains('Anthropic'), isFalse);
      // Row 2: new provider, header re-appears.
      expect(row2, contains('OpenAI'));
    });

    test('renderHeader returns a non-empty list', () {
      final builder = buildModelPanel(
        [
          (
            providerId: 'anthropic',
            providerName: 'Anthropic',
            model: const ModelDef(
              id: 'sonnet',
              name: 'Sonnet',
              capabilities: {'chat'},
            ),
            availability: ModelAvailability.unknown,
          ),
        ],
        currentRef: const ModelRef(providerId: 'x', modelId: 'y'),
      );
      expect(builder.renderHeader(80), isNotEmpty);
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
