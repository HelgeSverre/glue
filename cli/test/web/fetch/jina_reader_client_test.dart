import 'package:test/test.dart';
import 'package:glue/src/web/fetch/jina_reader_client.dart';

void main() {
  group('JinaReaderClient', () {
    test('builds correct reader URL', () {
      final client = JinaReaderClient(baseUrl: 'https://r.jina.ai');
      expect(
        client.buildReaderUrl('https://example.com/page'),
        Uri.parse('https://r.jina.ai/https://example.com/page'),
      );
    });

    test('builds correct reader URL with API key header name', () {
      final client = JinaReaderClient(
        baseUrl: 'https://r.jina.ai',
        apiKey: 'jina_test_key',
      );
      expect(client.headers, contains('Authorization'));
      expect(client.headers['Authorization'], 'Bearer jina_test_key');
    });

    test('headers omit auth when no API key', () {
      final client = JinaReaderClient(baseUrl: 'https://r.jina.ai');
      expect(client.headers, isNot(contains('Authorization')));
    });
  });
}
