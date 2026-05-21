import 'dart:io';

import 'package:glue_strategies/src/credentials/credential_store.dart';
import 'package:glue_strategies/src/mcp_client/oauth.dart';
import 'package:test/test.dart';

CredentialStore _store() => CredentialStore(
      path: '${Directory.systemTemp.createTempSync('oauth_invalidate_').path}/creds.json',
      env: const {},
    );

void main() {
  group('invalidateMcpAuth', () {
    late CredentialStore store;

    setUp(() {
      store = _store();
      store.setFields('mcp:foo', {
        'oauth_access': 'A',
        'oauth_refresh': 'R',
        'oauth_expires_at': '2030-01-01',
        'oauth_scope': 'read',
        'oauth_client_id': 'C',
        'oauth_client_secret': 'S',
      });
    });

    test('tokens scope clears tokens but keeps client_id/secret', () {
      invalidateMcpAuth(
        serverId: 'foo',
        scope: McpAuthInvalidation.tokens,
        credentials: store,
      );
      final fields = store.getFields('mcp:foo');
      expect(fields['oauth_access'], isNull);
      expect(fields['oauth_refresh'], isNull);
      expect(fields['oauth_expires_at'], isNull);
      expect(fields['oauth_scope'], isNull);
      expect(fields['oauth_client_id'], 'C');
      expect(fields['oauth_client_secret'], 'S');
    });

    test('client scope clears client_id/secret but keeps tokens', () {
      invalidateMcpAuth(
        serverId: 'foo',
        scope: McpAuthInvalidation.client,
        credentials: store,
      );
      final fields = store.getFields('mcp:foo');
      expect(fields['oauth_client_id'], isNull);
      expect(fields['oauth_client_secret'], isNull);
      expect(fields['oauth_access'], 'A');
      expect(fields['oauth_refresh'], 'R');
    });

    test('all scope clears everything oauth-related', () {
      invalidateMcpAuth(
        serverId: 'foo',
        scope: McpAuthInvalidation.all,
        credentials: store,
      );
      final fields = store.getFields('mcp:foo');
      expect(fields, isEmpty);
    });

    test('discovery scope is a no-op at the credentials level', () {
      invalidateMcpAuth(
        serverId: 'foo',
        scope: McpAuthInvalidation.discovery,
        credentials: store,
      );
      final fields = store.getFields('mcp:foo');
      // All oauth fields still present.
      expect(fields['oauth_access'], 'A');
      expect(fields['oauth_client_id'], 'C');
    });
  });
}
