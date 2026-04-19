@Tags(['ollama_registry'])
library;

import 'dart:io';

import 'package:glue/src/catalog/catalog_parser.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// Verifies every Ollama tag declared in `docs/reference/models.yaml`
/// resolves in the Ollama registry. Guards against catalog drift when
/// model authors rename or retire tags.
///
/// Network test, skipped by default. Run with:
///   dart test --run-skipped -t ollama_registry
void main() {
  final yaml = File('../docs/reference/models.yaml').readAsStringSync();
  final catalog = parseCatalogYaml(yaml);
  final ollama = catalog.providers['ollama']!;

  group('Ollama registry — every catalog tag must resolve', () {
    for (final modelId in ollama.models.keys) {
      test(modelId, () async {
        final colon = modelId.indexOf(':');
        final model = colon < 0 ? modelId : modelId.substring(0, colon);
        final tag = colon < 0 ? 'latest' : modelId.substring(colon + 1);
        final url = Uri.parse(
          'https://registry.ollama.ai/v2/library/$model/manifests/$tag',
        );
        final response =
            await http.head(url).timeout(const Duration(seconds: 10));
        expect(
          response.statusCode,
          200,
          reason: '$modelId → ${response.statusCode} from Ollama registry',
        );
      });
    }
  });
}
