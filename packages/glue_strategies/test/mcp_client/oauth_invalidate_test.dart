import 'dart:io';

import 'package:glue_strategies/src/credentials/credential_store.dart';
import 'package:glue_strategies/src/mcp_client/oauth.dart';
import 'package:test/test.dart';

CredentialStore _store() => CredentialStore(
  path:
      '${Directory.systemTemp.createTempSync('oauth_invalidate_').path}/creds.json',
  env: const {},
);

void main() {
  group('invalidateMcpTokens', () {
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

    test('clears tokens but keeps client_id/secret', () {
      invalidateMcpTokens(serverId: 'foo', credentials: store);
      final fields = store.getFields('mcp:foo');
      expect(fields['oauth_access'], isNull);
      expect(fields['oauth_refresh'], isNull);
      expect(fields['oauth_expires_at'], isNull);
      expect(fields['oauth_scope'], isNull);
      expect(fields['oauth_client_id'], 'C');
      expect(fields['oauth_client_secret'], 'S');
    });
  });
}
