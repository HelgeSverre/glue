import 'dart:io';

import 'package:glue_strategies/src/mcp_client/oauth.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('runOAuthAuthorizationCodeFlow callback page (L1)', () {
    test('reflected error param is HTML-escaped, not injected raw', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirectUri = Uri.parse('http://127.0.0.1:${server.port}/callback');

      final flow = runOAuthAuthorizationCodeFlow(
        endpoints: OAuthEndpoints(
          authorizationEndpoint: Uri.parse('https://auth.example/authorize'),
          tokenEndpoint: Uri.parse('https://auth.example/token'),
        ),
        client: const OAuthClient(clientId: 'cid'),
        preboundServer: server,
        preboundRedirectUri: redirectUri,
        onAuthUrl: (_) {},
        timeout: const Duration(seconds: 5),
      );

      const payload = '<script>alert(1)</script>';
      final resp = await http.get(
        redirectUri.replace(queryParameters: {'error': payload}),
      );

      expect(
        resp.body,
        isNot(contains(payload)),
        reason: 'raw attacker-controlled markup must not be reflected',
      );
      expect(resp.body, contains('&lt;script&gt;'));

      await expectLater(flow, throwsA(isA<OAuthFlowException>()));
    });
  });
}
