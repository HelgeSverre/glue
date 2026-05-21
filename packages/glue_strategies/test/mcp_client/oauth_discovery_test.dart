import 'package:glue_strategies/src/mcp_client/oauth.dart';
import 'package:test/test.dart';

void main() {
  group('parseWwwAuthenticate', () {
    test('extracts resource_metadata and scope from Bearer challenge', () {
      final challenge = parseWwwAuthenticate(
        'Bearer resource_metadata="https://example.com/.well-known/oauth-protected-resource", '
        'scope="read write"',
      );
      expect(challenge?.scheme, 'Bearer');
      expect(challenge?.resourceMetadata,
          Uri.parse('https://example.com/.well-known/oauth-protected-resource'));
      expect(challenge?.scope, ['read', 'write']);
    });

    test('handles quoted commas inside a parameter value', () {
      final challenge = parseWwwAuthenticate(
        'Bearer error="invalid_token", error_description="token expired, please refresh"',
      );
      expect(challenge?.scheme, 'Bearer');
      expect(challenge?.parameters['error_description'],
          'token expired, please refresh');
    });

    test('returns null when scheme is not Bearer', () {
      expect(parseWwwAuthenticate('Basic realm="foo"'), isNull);
    });

    test('returns null on empty/missing header', () {
      expect(parseWwwAuthenticate(null), isNull);
      expect(parseWwwAuthenticate(''), isNull);
    });

    test('handles missing resource_metadata gracefully', () {
      final challenge = parseWwwAuthenticate('Bearer realm="api"');
      expect(challenge?.scheme, 'Bearer');
      expect(challenge?.resourceMetadata, isNull);
      expect(challenge?.scope, isEmpty);
    });
  });
}
