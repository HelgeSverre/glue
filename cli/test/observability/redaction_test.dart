import 'package:glue/src/observability/redaction.dart';
import 'package:test/test.dart';

void main() {
  group('redactHeaders', () {
    test('keeps allowlisted headers intact', () {
      final result = redactHeaders({
        'content-type': 'application/json',
        'accept': '*/*',
        'user-agent': 'glue/0.1',
      });
      expect(result['content-type'], 'application/json');
      expect(result['accept'], '*/*');
      expect(result['user-agent'], 'glue/0.1');
    });

    test('masks unknown headers', () {
      final result = redactHeaders({
        'x-api-key': 'sk-secret',
        'authorization': 'Bearer xxx',
        'anchor-api-key': 'yyy',
      });
      expect(result['x-api-key'], '****');
      expect(result['authorization'], '****');
      expect(result['anchor-api-key'], '****');
    });

    test('is case insensitive on header names', () {
      final result = redactHeaders({
        'Content-Type': 'application/json',
        'X-API-KEY': 'sk-secret',
      });
      expect(result['Content-Type'], 'application/json');
      expect(result['X-API-KEY'], '****');
    });

    test('preserves original-case keys in output', () {
      final result = redactHeaders({'Content-Type': 'text/plain'});
      expect(result.keys, contains('Content-Type'));
    });
  });

  group('redactUrl', () {
    test('leaves url without query params alone', () {
      final result = redactUrl(Uri.parse('https://example.com/path'));
      expect(result, 'https://example.com/path');
    });

    test('masks sensitive query params', () {
      final result =
          redactUrl(Uri.parse('https://example.com/x?api_key=abc&q=cats'));
      expect(result, contains('api_key=****'));
      expect(result, contains('q=cats'));
    });

    test('masks access_token and token params', () {
      final result = redactUrl(
          Uri.parse('https://x.com/y?access_token=abc&token=def&other=ok'));
      expect(result, contains('access_token=****'));
      expect(result, contains('token=****'));
      expect(result, contains('other=ok'));
    });
  });

  group('redactBody', () {
    test('masks api_key JSON field', () {
      final result = redactBody('{"api_key":"sk-abc123","query":"cats"}');
      expect(result, contains('"api_key":"****"'));
      expect(result, contains('"query":"cats"'));
    });

    test('masks Bearer tokens in text bodies', () {
      final result = redactBody('curl -H "Authorization: Bearer abcdef123456"');
      expect(result, isNot(contains('abcdef123456')));
      expect(result, contains('****'));
    });

    test('masks sk-… and sk-ant-… API keys', () {
      final openai = redactBody('key=sk-abcdefghij1234567890');
      expect(openai, isNot(contains('sk-abcdefghij1234567890')));

      final anthropic = redactBody('key=sk-ant-api03-abcdefghij1234567890');
      expect(anthropic, isNot(contains('sk-ant-api03-abcdefghij1234567890')));
    });

    test('masks JWTs', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkw.SflKxwRJSMeKKF2QT4';
      final result = redactBody('token=$jwt rest');
      expect(result, isNot(contains(jwt)));
      expect(result, contains('rest'));
    });

    test('truncates bodies over maxBytes', () {
      final big = 'A' * 100;
      final result = redactBody(big, maxBytes: 20);
      expect(result, startsWith('A' * 20));
      expect(result, contains('truncated'));
    });

    test('preserves short bodies verbatim', () {
      final result = redactBody('hello world', maxBytes: 1024);
      expect(result, 'hello world');
    });
  });
}
