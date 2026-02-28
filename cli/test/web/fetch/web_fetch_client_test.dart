import 'package:test/test.dart';
import 'package:glue/src/web/fetch/web_fetch_client.dart';
import 'package:glue/src/web/web_config.dart';

void main() {
  group('WebFetchClient', () {
    late WebFetchClient client;

    setUp(() {
      client = WebFetchClient(
        config: const WebFetchConfig(allowJinaFallback: false),
      );
    });

    test('rejects invalid URLs', () async {
      final result = await client.fetch('not-a-url');
      expect(result.error, isNotNull);
      expect(result.error, contains('Invalid URL'));
    });

    test('rejects non-http schemes', () async {
      final result = await client.fetch('ftp://files.example.com/doc');
      expect(result.error, isNotNull);
    });

    test('result model has expected fields', () {
      final result = WebFetchResult(
        url: 'https://example.com',
        markdown: '# Hello',
        title: 'Example',
      );
      expect(result.url, 'https://example.com');
      expect(result.markdown, '# Hello');
      expect(result.title, 'Example');
      expect(result.error, isNull);
    });

    test('error result', () {
      final result = WebFetchResult.withError(
        url: 'https://bad.com',
        error: 'Connection failed',
      );
      expect(result.markdown, isNull);
      expect(result.error, 'Connection failed');
    });
  });
}
