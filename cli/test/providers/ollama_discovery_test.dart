/// OllamaDiscovery tests — fake http.Client, no network.
library;

import 'dart:async';
import 'dart:convert';

import 'package:glue/src/providers/ollama_discovery.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _FakeHttp extends http.BaseClient {
  _FakeHttp(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest req) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

http.StreamedResponse _jsonResponse(int status, Object body) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    status,
    headers: {'content-type': 'application/json'},
  );
}

http.StreamedResponse _rawResponse(int status, String body) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  setUp(OllamaDiscovery.resetCacheForTesting);
  _extraTests();

  group('OllamaDiscovery.listInstalled', () {
    test('parses /api/tags into OllamaInstalledModel list', () async {
      Uri? captured;
      final client = _FakeHttp((req) async {
        captured = req.url;
        return _jsonResponse(200, {
          'models': [
            {
              'name': 'qwen3-coder:30b',
              'size': 20000000000,
              'modified_at': '2026-04-20T01:00:00Z',
            },
            {
              'name': 'gemma4:latest',
              'size': 9600000000,
              'modified_at': '2026-04-19T03:00:00Z',
            },
          ],
        });
      });

      final discovery = OllamaDiscovery(
        baseUrl: Uri.parse('http://localhost:11434/v1'),
        clientFactory: () => client,
      );
      final models = await discovery.listInstalled();

      // Strips the OpenAI-compat /v1 suffix when hitting /api/tags.
      expect(captured.toString(), 'http://localhost:11434/api/tags');
      expect(models.length, 2);
      expect(models[0].tag, 'qwen3-coder:30b');
      expect(models[0].sizeBytes, 20000000000);
      expect(models[1].tag, 'gemma4:latest');
    });

    test('timeout yields empty list, never throws', () async {
      final client = _FakeHttp((req) async {
        // Simulate a request that never completes in time.
        await Future<void>.delayed(const Duration(seconds: 5));
        return _jsonResponse(200, {'models': []});
      });
      final discovery = OllamaDiscovery(
        baseUrl: Uri.parse('http://localhost:11434'),
        clientFactory: () => client,
        timeout: const Duration(milliseconds: 50),
      );
      expect(await discovery.listInstalled(), isEmpty);
    });

    test('non-200 yields empty list', () async {
      final client = _FakeHttp(
        (req) async => _jsonResponse(503, {'error': 'maintenance'}),
      );
      final discovery = OllamaDiscovery(
        baseUrl: Uri.parse('http://localhost:11434'),
        clientFactory: () => client,
      );
      expect(await discovery.listInstalled(), isEmpty);
    });

    test('malformed JSON yields empty list', () async {
      final client = _FakeHttp(
        (req) async => _rawResponse(200, '<<not json>>'),
      );
      final discovery = OllamaDiscovery(
        baseUrl: Uri.parse('http://localhost:11434'),
        clientFactory: () => client,
      );
      expect(await discovery.listInstalled(), isEmpty);
    });

    test('connection error (client throws) yields empty list', () async {
      final client = _FakeHttp(
        (req) async => throw const FakeSocketException(),
      );
      final discovery = OllamaDiscovery(
        baseUrl: Uri.parse('http://localhost:11434'),
        clientFactory: () => client,
      );
      expect(await discovery.listInstalled(), isEmpty);
    });

    test('skips malformed entries, keeps valid ones', () async {
      final client = _FakeHttp((req) async => _jsonResponse(200, {
            'models': [
              {'name': 'good:1b', 'size': 100},
              {'no_name': true},
              'not-a-map',
              {'name': 'also-good:2b', 'size': 200},
            ],
          }));
      final discovery = OllamaDiscovery(
        baseUrl: Uri.parse('http://localhost:11434'),
        clientFactory: () => client,
      );
      final models = await discovery.listInstalled();
      expect(models.map((m) => m.tag).toList(), ['good:1b', 'also-good:2b']);
    });
  });

  group('OllamaDiscovery cache', () {
    test('second call within TTL hits cache, no new HTTP', () async {
      var calls = 0;
      final client = _FakeHttp((req) async {
        calls++;
        return _jsonResponse(200, {
          'models': [
            {'name': 'foo:1b', 'size': 0},
          ],
        });
      });
      final discovery = OllamaDiscovery(
        baseUrl: Uri.parse('http://localhost:11434'),
        clientFactory: () => client,
      );
      await discovery.listInstalled();
      await discovery.listInstalled();
      expect(calls, 1);
    });

    test('cache expires after TTL', () async {
      var calls = 0;
      var clock = DateTime(2026, 4, 20, 12);
      final client = _FakeHttp((req) async {
        calls++;
        return _jsonResponse(200, {
          'models': [
            {'name': 'foo:1b', 'size': 0},
          ],
        });
      });
      final discovery = OllamaDiscovery(
        baseUrl: Uri.parse('http://localhost:11434'),
        clientFactory: () => client,
        cacheTtl: const Duration(seconds: 30),
        now: () => clock,
      );
      await discovery.listInstalled();
      clock = clock.add(const Duration(seconds: 31));
      await discovery.listInstalled();
      expect(calls, 2);
    });

    test('invalidateCache forces refetch', () async {
      var calls = 0;
      final client = _FakeHttp((req) async {
        calls++;
        return _jsonResponse(200, {'models': []});
      });
      final discovery = OllamaDiscovery(
        baseUrl: Uri.parse('http://localhost:11434'),
        clientFactory: () => client,
      );
      await discovery.listInstalled();
      discovery.invalidateCache();
      await discovery.listInstalled();
      expect(calls, 2);
    });
  });
}

class FakeSocketException implements Exception {
  const FakeSocketException();
}

http.StreamedResponse _ndjsonStream(
    int status, List<Map<String, Object?>> frames) {
  final bytes = utf8.encode(frames.map(jsonEncode).join('\n'));
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    status,
    headers: {'content-type': 'application/x-ndjson'},
  );
}

void _extraTests() {
  group('OllamaDiscovery.pullModel', () {
    test('streams progress and completes on success frame', () async {
      http.BaseRequest? captured;
      final client = _FakeHttp((req) async {
        captured = req;
        return _ndjsonStream(200, [
          {'status': 'pulling manifest'},
          {
            'status': 'downloading',
            'digest': 'sha256:abc',
            'total': 1000,
            'completed': 250,
          },
          {
            'status': 'downloading',
            'digest': 'sha256:abc',
            'total': 1000,
            'completed': 1000,
          },
          {'status': 'success'},
        ]);
      });
      final discovery = OllamaDiscovery(
        baseUrl: Uri.parse('http://localhost:11434/v1'),
        clientFactory: () => client,
      );
      final frames = await discovery.pullModel('qwen3:8b').toList();
      expect(captured?.url.toString(), 'http://localhost:11434/api/pull');
      expect(frames.last.isSuccess, isTrue);
      expect(frames.map((f) => f.status).toList(), [
        'pulling manifest',
        'downloading',
        'downloading',
        'success',
      ]);
      expect(frames[1].fraction, 0.25);
      expect(frames[2].fraction, 1.0);
    });

    test('non-200 yields a single error frame', () async {
      final client = _FakeHttp(
        (req) async => _jsonResponse(404, {'error': 'not found'}),
      );
      final discovery = OllamaDiscovery(
        baseUrl: Uri.parse('http://localhost:11434'),
        clientFactory: () => client,
      );
      final frames = await discovery.pullModel('missing:1b').toList();
      expect(frames.length, 1);
      expect(frames.single.hasError, isTrue);
      expect(frames.single.error, contains('404'));
    });

    test('server error frame inline is surfaced', () async {
      final client = _FakeHttp(
        (req) async => _ndjsonStream(200, [
          {'status': 'pulling manifest'},
          {'error': 'pull canceled'},
        ]),
      );
      final discovery = OllamaDiscovery(
        baseUrl: Uri.parse('http://localhost:11434'),
        clientFactory: () => client,
      );
      final frames = await discovery.pullModel('x:1b').toList();
      expect(frames.last.hasError, isTrue);
      expect(frames.last.error, 'pull canceled');
    });
  });
}
