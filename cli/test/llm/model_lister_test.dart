import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:test/test.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/llm/model_lister.dart';

void main() {
  group('ModelLister', () {
    group('Ollama', () {
      test('parses /api/tags response', () async {
        final client = http_testing.MockClient((req) async {
          expect(req.url.path, '/api/tags');
          return http.Response(jsonEncode({
            'models': [
              {'name': 'llama3.2:latest', 'size': 2147483648},
              {'name': 'qwen2.5:7b', 'size': 4831838208},
            ]
          }), 200);
        });
        final lister = ModelLister(httpClient: client);
        final models = await lister.list(
          provider: LlmProvider.ollama,
          ollamaBaseUrl: 'http://localhost:11434',
        );
        expect(models, hasLength(2));
        expect(models[0].id, 'llama3.2:latest');
        expect(models[0].size, '2.0 GB');
        expect(models[1].id, 'qwen2.5:7b');
        expect(models[1].size, '4.5 GB');
      });

      test('returns empty list when no models', () async {
        final client = http_testing.MockClient((req) async {
          return http.Response(jsonEncode({'models': []}), 200);
        });
        final lister = ModelLister(httpClient: client);
        final models = await lister.list(provider: LlmProvider.ollama);
        expect(models, isEmpty);
      });
    });

    group('OpenAI', () {
      test('parses /v1/models response', () async {
        final client = http_testing.MockClient((req) async {
          expect(req.url.path, '/v1/models');
          expect(req.headers['Authorization'], 'Bearer test-key');
          return http.Response(jsonEncode({
            'data': [
              {'id': 'gpt-4.1'},
              {'id': 'gpt-4.1-mini'},
              {'id': 'gpt-3.5-turbo'},
            ]
          }), 200);
        });
        final lister = ModelLister(httpClient: client);
        final models = await lister.list(
          provider: LlmProvider.openai,
          apiKey: 'test-key',
        );
        expect(models, hasLength(3));
        // Sorted alphabetically
        expect(models[0].id, 'gpt-3.5-turbo');
        expect(models[1].id, 'gpt-4.1');
        expect(models[2].id, 'gpt-4.1-mini');
      });
    });

    group('Anthropic', () {
      test('parses /v1/models response', () async {
        final client = http_testing.MockClient((req) async {
          expect(req.url.path, '/v1/models');
          expect(req.headers['x-api-key'], 'test-key');
          expect(req.headers['anthropic-version'], '2023-06-01');
          return http.Response(jsonEncode({
            'data': [
              {'id': 'claude-sonnet-4-6'},
              {'id': 'claude-haiku-4'},
            ]
          }), 200);
        });
        final lister = ModelLister(httpClient: client);
        final models = await lister.list(
          provider: LlmProvider.anthropic,
          apiKey: 'test-key',
        );
        expect(models, hasLength(2));
        expect(models[0].id, 'claude-haiku-4');
        expect(models[1].id, 'claude-sonnet-4-6');
      });
    });

    test('throws on non-200 response', () {
      final client = http_testing.MockClient((req) async {
        return http.Response('Unauthorized', 401);
      });
      final lister = ModelLister(httpClient: client);
      expect(
        () => lister.list(provider: LlmProvider.ollama),
        throwsException,
      );
    });
  });
}
