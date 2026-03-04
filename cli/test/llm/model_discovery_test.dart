import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/config/model_registry.dart';
import 'package:glue/src/llm/model_discovery.dart';
import 'package:glue/src/llm/model_lister.dart';

void main() {
  late Directory tempDir;
  late String cacheDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('model_discovery_test_');
    cacheDir = p.join(tempDir.path, 'cache');
    Directory(cacheDir).createSync(recursive: true);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Config with all API keys set.
  GlueConfig allKeysConfig() => GlueConfig(
        anthropicApiKey: 'ak-test',
        openaiApiKey: 'ok-test',
        mistralApiKey: 'mk-test',
      );

  /// Config with only Ollama (no API keys).
  GlueConfig ollamaOnlyConfig() => GlueConfig();

  /// Writes a cache file for a provider.
  void writeCache(
    LlmProvider provider,
    List<Map<String, dynamic>> models, {
    DateTime? fetchedAt,
  }) {
    final ts = (fetchedAt ?? DateTime.now().toUtc()).toIso8601String();
    final file = File(p.join(cacheDir, 'models_${provider.name}.json'));
    file.writeAsStringSync(jsonEncode({
      'fetched_at': ts,
      'models': models,
    }));
  }

  /// Reads a cache file for a provider.
  Map<String, dynamic>? readCache(LlmProvider provider) {
    final file = File(p.join(cacheDir, 'models_${provider.name}.json'));
    if (!file.existsSync()) return null;
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  /// Mock HTTP client that dispatches based on host/path.
  http_testing.MockClient mockClient({
    List<Map<String, dynamic>> ollamaModels = const [],
    List<Map<String, dynamic>> openaiModels = const [],
    List<Map<String, dynamic>> anthropicModels = const [],
    List<Map<String, dynamic>> mistralModels = const [],
    bool ollamaFails = false,
    bool openaiFails = false,
    bool anthropicFails = false,
    bool mistralFails = false,
  }) {
    return http_testing.MockClient((req) async {
      if (req.url.host == 'localhost' && req.url.path == '/api/tags') {
        if (ollamaFails) return http.Response('error', 500);
        return http.Response(jsonEncode({'models': ollamaModels}), 200);
      }
      if (req.url.host == 'api.openai.com') {
        if (openaiFails) return http.Response('error', 500);
        return http.Response(jsonEncode({'data': openaiModels}), 200);
      }
      if (req.url.host == 'api.anthropic.com') {
        if (anthropicFails) return http.Response('error', 500);
        return http.Response(jsonEncode({'data': anthropicModels}), 200);
      }
      if (req.url.host == 'api.mistral.ai') {
        if (mistralFails) return http.Response('error', 500);
        return http.Response(jsonEncode({'data': mistralModels}), 200);
      }
      return http.Response('not found', 404);
    });
  }

  group('ModelDiscovery', () {
    test('fresh cache — no HTTP call, cached models returned', () async {
      writeCache(LlmProvider.ollama, [
        {'id': 'gemma3:latest', 'size': '3.3 GB'},
        {'id': 'llama3.2:7b', 'size': '4.0 GB'},
      ]);

      var httpCalled = false;
      final client = http_testing.MockClient((req) async {
        httpCalled = true;
        return http.Response('should not be called', 500);
      });

      final discovery = ModelDiscovery(
        cacheDir: cacheDir,
        lister: ModelLister(httpClient: client),
      );
      final entries = await discovery.discoverAll(ollamaOnlyConfig());

      expect(httpCalled, isFalse);
      // Should include registry Ollama entries + cached discovered ones.
      final ollamaEntries =
          entries.where((e) => e.provider == LlmProvider.ollama);
      expect(
        ollamaEntries.map((e) => e.modelId),
        containsAll(['gemma3:latest', 'llama3.2:7b']),
      );
    });

    test('stale cache — API called, cache updated', () async {
      final staleTime =
          DateTime.now().toUtc().subtract(const Duration(hours: 7));
      writeCache(
          LlmProvider.ollama,
          [
            {'id': 'old-model:latest', 'size': '1.0 GB'},
          ],
          fetchedAt: staleTime);

      final client = mockClient(ollamaModels: [
        {'name': 'new-model:latest', 'size': 2147483648},
      ]);

      final discovery = ModelDiscovery(
        cacheDir: cacheDir,
        lister: ModelLister(httpClient: client),
      );
      final entries = await discovery.discoverAll(ollamaOnlyConfig());

      // Should have the new model, not the old one.
      final ollamaDiscovered = entries
          .where((e) => e.provider == LlmProvider.ollama)
          .where(
              (e) => !ModelRegistry.models.any((r) => r.modelId == e.modelId));
      expect(
          ollamaDiscovered.map((e) => e.modelId), contains('new-model:latest'));
      expect(
        ollamaDiscovered.map((e) => e.modelId),
        isNot(contains('old-model:latest')),
      );

      // Cache file should be updated.
      final cache = readCache(LlmProvider.ollama)!;
      final models = (cache['models'] as List).cast<Map<String, dynamic>>();
      expect(models.first['id'], 'new-model:latest');
    });

    test('missing cache — API called, cache created', () async {
      final client = mockClient(ollamaModels: [
        {'name': 'gemma3:latest', 'size': 3543348019},
      ]);

      final discovery = ModelDiscovery(
        cacheDir: cacheDir,
        lister: ModelLister(httpClient: client),
      );
      await discovery.discoverAll(ollamaOnlyConfig());

      // Cache should now exist.
      final cache = readCache(LlmProvider.ollama);
      expect(cache, isNotNull);
      final models = (cache!['models'] as List).cast<Map<String, dynamic>>();
      expect(models.first['id'], 'gemma3:latest');
    });

    test('multiple stale providers — parallel fetch', () async {
      final staleTime =
          DateTime.now().toUtc().subtract(const Duration(hours: 7));
      for (final provider in LlmProvider.values) {
        writeCache(provider, [], fetchedAt: staleTime);
      }

      final requestedHosts = <String>[];
      final client = http_testing.MockClient((req) async {
        requestedHosts.add(req.url.host);
        if (req.url.host == 'localhost') {
          return http.Response(jsonEncode({'models': []}), 200);
        }
        return http.Response(jsonEncode({'data': []}), 200);
      });

      final discovery = ModelDiscovery(
        cacheDir: cacheDir,
        lister: ModelLister(httpClient: client),
      );
      await discovery.discoverAll(allKeysConfig());

      // All four providers should have been fetched.
      expect(
          requestedHosts,
          containsAll([
            'localhost',
            'api.openai.com',
            'api.anthropic.com',
            'api.mistral.ai',
          ]));
    });

    test('API failure — falls back to stale cache', () async {
      final staleTime =
          DateTime.now().toUtc().subtract(const Duration(hours: 7));
      writeCache(
          LlmProvider.ollama,
          [
            {'id': 'cached-model:latest', 'size': '2.0 GB'},
          ],
          fetchedAt: staleTime);

      final client = mockClient(ollamaFails: true);

      final discovery = ModelDiscovery(
        cacheDir: cacheDir,
        lister: ModelLister(httpClient: client),
      );
      final entries = await discovery.discoverAll(ollamaOnlyConfig());

      // Should have the stale cached model.
      expect(
        entries.map((e) => e.modelId),
        contains('cached-model:latest'),
      );
    });

    test('API failure + no cache — returns static registry entries only',
        () async {
      final client = mockClient(ollamaFails: true);

      final discovery = ModelDiscovery(
        cacheDir: cacheDir,
        lister: ModelLister(httpClient: client),
      );
      final entries = await discovery.discoverAll(ollamaOnlyConfig());

      // Should only have registry Ollama entries.
      final ollamaEntries =
          entries.where((e) => e.provider == LlmProvider.ollama);
      expect(
        ollamaEntries.map((e) => e.modelId).toSet(),
        equals(ModelRegistry.forProvider(LlmProvider.ollama)
            .map((e) => e.modelId)
            .toSet()),
      );
    });

    test('de-duplication: registry entry wins over API duplicate', () async {
      final client = mockClient(ollamaModels: [
        {'name': 'llama3.2', 'size': 2147483648},
      ]);

      final discovery = ModelDiscovery(
        cacheDir: cacheDir,
        lister: ModelLister(httpClient: client),
      );
      final entries = await discovery.discoverAll(ollamaOnlyConfig());

      // The registry entry for llama3.2 should be present, not a duplicate.
      final llama = entries.where((e) => e.modelId == 'llama3.2').toList();
      expect(llama, hasLength(1));
      // Registry entry has isDefault=true and tagline='Local and free'.
      expect(llama.first.tagline, 'Local and free');
      expect(llama.first.isDefault, isTrue);
    });

    test('only configured providers queried', () async {
      final requestedHosts = <String>[];
      final client = http_testing.MockClient((req) async {
        requestedHosts.add(req.url.host);
        if (req.url.host == 'localhost') {
          return http.Response(jsonEncode({'models': []}), 200);
        }
        return http.Response(jsonEncode({'data': []}), 200);
      });

      final discovery = ModelDiscovery(
        cacheDir: cacheDir,
        lister: ModelLister(httpClient: client),
      );
      // Only Ollama configured (no API keys).
      await discovery.discoverAll(ollamaOnlyConfig());

      expect(requestedHosts, equals(['localhost']));
      expect(requestedHosts, isNot(contains('api.openai.com')));
      expect(requestedHosts, isNot(contains('api.anthropic.com')));
      expect(requestedHosts, isNot(contains('api.mistral.ai')));
    });

    test('Ollama display names strip :latest suffix', () async {
      final client = mockClient(ollamaModels: [
        {'name': 'gemma3:latest', 'size': 3543348019},
        {'name': 'qwen2.5:7b', 'size': 4831838208},
      ]);

      final discovery = ModelDiscovery(
        cacheDir: cacheDir,
        lister: ModelLister(httpClient: client),
      );
      final entries = await discovery.discoverAll(ollamaOnlyConfig());

      final gemma = entries.firstWhere((e) => e.modelId == 'gemma3:latest');
      expect(gemma.displayName, 'gemma3');

      final qwen = entries.firstWhere((e) => e.modelId == 'qwen2.5:7b');
      expect(qwen.displayName, 'qwen2.5:7b');
    });

    test('Ollama tagline uses "Local · size" format', () async {
      final client = mockClient(ollamaModels: [
        {'name': 'gemma3:latest', 'size': 3543348019},
      ]);

      final discovery = ModelDiscovery(
        cacheDir: cacheDir,
        lister: ModelLister(httpClient: client),
      );
      final entries = await discovery.discoverAll(ollamaOnlyConfig());

      final gemma = entries.firstWhere((e) => e.modelId == 'gemma3:latest');
      expect(gemma.tagline, startsWith('Local \u00b7 '));
    });

    test('cloud provider tagline uses "Provider API" format', () async {
      final client = mockClient(openaiModels: [
        {'id': 'gpt-5-turbo'},
      ]);

      final discovery = ModelDiscovery(
        cacheDir: cacheDir,
        lister: ModelLister(httpClient: client),
      );
      final config = GlueConfig(openaiApiKey: 'ok-test');
      final entries = await discovery.discoverAll(config);

      final gpt5 = entries.firstWhere((e) => e.modelId == 'gpt-5-turbo');
      expect(gpt5.tagline, 'OpenAI API');
      expect(gpt5.cost, CostTier.medium);
      expect(gpt5.speed, SpeedTier.standard);
    });

    test('registry entries appear before discovered entries per group',
        () async {
      final client = mockClient(ollamaModels: [
        {'name': 'llama3.2', 'size': 2147483648},
        {'name': 'custom-model:latest', 'size': 1073741824},
      ]);

      final discovery = ModelDiscovery(
        cacheDir: cacheDir,
        lister: ModelLister(httpClient: client),
      );
      final entries = await discovery.discoverAll(ollamaOnlyConfig());

      final ollamaEntries =
          entries.where((e) => e.provider == LlmProvider.ollama).toList();
      // First entry should be the registry entry (llama3.2).
      expect(ollamaEntries.first.modelId, 'llama3.2');
      expect(ollamaEntries.first.isDefault, isTrue);
      // custom-model should come after.
      expect(
        ollamaEntries.map((e) => e.modelId),
        contains('custom-model:latest'),
      );
    });
  });
}
