import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue_strategies/glue_strategies.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// A scripted HTTP client: returns a canned [http.Response] per request and
/// records every URL it was asked to hit. Lets the SSRF tests run offline and
/// prove which hops did (and did not) reach the network.
class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this._handler);

  final http.Response Function(http.Request request) _handler;
  final sent = <Uri>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(request.url);
    final resp = _handler(request as http.Request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(resp.body)),
      resp.statusCode,
      headers: resp.headers,
      reasonPhrase: resp.reasonPhrase,
      request: request,
    );
  }
}

/// A deterministic DNS resolver for tests: [map] host → IP literal, defaulting
/// to a public address for anything unmapped.
HostResolver _resolver(Map<String, String> map) =>
    (host) async => [InternetAddress(map[host] ?? '93.184.216.34')];

void main() {
  group('isBlockedAddress', () {
    for (final ip in [
      '127.0.0.1',
      '127.10.20.30',
      '10.0.0.1',
      '172.16.0.1',
      '172.31.255.255',
      '192.168.1.1',
      '169.254.169.254', // cloud metadata endpoint
      '0.0.0.0',
      '100.64.0.1', // CGNAT
      '224.0.0.1', // multicast
    ]) {
      test('blocks IPv4 $ip', () {
        expect(isBlockedAddress(InternetAddress(ip)), isTrue);
      });
    }

    for (final ip in ['8.8.8.8', '93.184.216.34', '172.15.0.1', '172.32.0.1']) {
      test('allows public IPv4 $ip', () {
        expect(isBlockedAddress(InternetAddress(ip)), isFalse);
      });
    }

    for (final ip in [
      '::1', // loopback
      '::', // unspecified
      'fe80::1', // link-local
      'fc00::1', // ULA
      'fd00::1', // ULA
      'ff02::1', // multicast
      '::ffff:127.0.0.1', // IPv4-mapped loopback
      '::ffff:169.254.169.254', // IPv4-mapped metadata
    ]) {
      test('blocks IPv6 $ip', () {
        expect(isBlockedAddress(InternetAddress(ip)), isTrue);
      });
    }

    test('allows public IPv6', () {
      expect(isBlockedAddress(InternetAddress('2606:2800:220:1::1')), isFalse);
    });
  });

  group('SsrfGuard.validate', () {
    test('rejects literal loopback without DNS', () async {
      final guard = SsrfGuard(resolver: _resolver({}));
      await expectLater(
        guard.validate(Uri.parse('http://127.0.0.1/')),
        throwsA(isA<SsrfBlockedException>()),
      );
    });

    test('rejects the cloud metadata endpoint', () async {
      final guard = SsrfGuard(resolver: _resolver({}));
      await expectLater(
        guard.validate(
          Uri.parse('http://169.254.169.254/latest/meta-data/iam/'),
        ),
        throwsA(isA<SsrfBlockedException>()),
      );
    });

    test('rejects a hostname that resolves to a private address', () async {
      final guard = SsrfGuard(resolver: _resolver({'intra.corp': '10.1.2.3'}));
      await expectLater(
        guard.validate(Uri.parse('http://intra.corp/admin')),
        throwsA(isA<SsrfBlockedException>()),
      );
    });

    test('rejects non-http schemes', () async {
      final guard = SsrfGuard(resolver: _resolver({}));
      await expectLater(
        guard.validate(Uri.parse('file:///etc/passwd')),
        throwsA(isA<SsrfBlockedException>()),
      );
    });

    test('allows a public host', () async {
      final guard = SsrfGuard(
        resolver: _resolver({'example.com': '93.184.216.34'}),
      );
      await guard.validate(Uri.parse('https://example.com/page'));
    });
  });

  group('SsrfGuard.safeGet redirect re-validation', () {
    test('rejects a 302 that redirects to an internal address', () async {
      final client = _ScriptedClient((req) {
        return http.Response(
          '',
          302,
          headers: {'location': 'http://169.254.169.254/latest/meta-data/'},
        );
      });
      final guard = SsrfGuard(
        resolver: _resolver({'safe.example': '93.184.216.34'}),
      );
      await expectLater(
        guard.safeGet(client, Uri.parse('http://safe.example/redir')),
        throwsA(isA<SsrfBlockedException>()),
      );
      // The internal target must never be contacted.
      expect(client.sent, [Uri.parse('http://safe.example/redir')]);
    });

    test('follows a public redirect and returns the final response', () async {
      final client = _ScriptedClient((req) {
        if (req.url.path == '/redir') {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://final.example/ok'},
          );
        }
        return http.Response('done', 200);
      });
      final guard = SsrfGuard(
        resolver: _resolver({
          'safe.example': '93.184.216.34',
          'final.example': '93.184.216.34',
        }),
      );
      final resp = await guard.safeGet(
        client,
        Uri.parse('https://safe.example/redir'),
      );
      expect(resp.statusCode, 200);
      expect(resp.body, 'done');
    });

    test('returns a plain 200 without following anything', () async {
      final client = _ScriptedClient((req) => http.Response('hi', 200));
      final guard = SsrfGuard(resolver: _resolver({'x.example': '1.2.3.4'}));
      final resp = await guard.safeGet(client, Uri.parse('http://x.example/'));
      expect(resp.body, 'hi');
      expect(client.sent.length, 1);
    });
  });

  group('WebFetchClient SSRF guard', () {
    test('blocks the cloud metadata endpoint', () async {
      final client = _ScriptedClient((req) => http.Response('secret', 200));
      final fetcher = WebFetchClient(
        config: const WebFetchConfig(allowJinaFallback: false),
        client: client,
        guard: SsrfGuard(resolver: _resolver({})),
      );
      final result = await fetcher.fetch(
        'http://169.254.169.254/latest/meta-data/iam/security-credentials/',
      );
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('Blocked'));
      expect(client.sent, isEmpty);
    });

    test('blocks loopback', () async {
      final client = _ScriptedClient((req) => http.Response('x', 200));
      final fetcher = WebFetchClient(
        config: const WebFetchConfig(allowJinaFallback: false),
        client: client,
        guard: SsrfGuard(resolver: _resolver({})),
      );
      final result = await fetcher.fetch('http://127.0.0.1:8080/');
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('Blocked'));
      expect(client.sent, isEmpty);
    });

    test('blocks a 302 redirect to an internal address', () async {
      final client = _ScriptedClient((req) {
        return http.Response(
          '',
          302,
          headers: {'location': 'http://169.254.169.254/latest/meta-data/'},
        );
      });
      final fetcher = WebFetchClient(
        config: const WebFetchConfig(allowJinaFallback: false),
        client: client,
        guard: SsrfGuard(
          resolver: _resolver({'evil.example': '93.184.216.34'}),
        ),
      );
      final result = await fetcher.fetch('http://evil.example/redir');
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('Blocked'));
      // Only the public first hop was contacted; the internal one was not.
      expect(client.sent, [Uri.parse('http://evil.example/redir')]);
    });

    test('fetches a normal public URL', () async {
      final client = _ScriptedClient(
        (req) => http.Response(
          '# Hello from the public web',
          200,
          headers: {'content-type': 'text/markdown'},
        ),
      );
      final fetcher = WebFetchClient(
        config: const WebFetchConfig(allowJinaFallback: false),
        client: client,
        guard: SsrfGuard(resolver: _resolver({'example.com': '93.184.216.34'})),
      );
      final result = await fetcher.fetch('https://example.com/');
      expect(result.isSuccess, isTrue);
      expect(result.markdown, contains('Hello from the public web'));
      expect(client.sent, [Uri.parse('https://example.com/')]);
    });
  });

  group('JinaReaderClient SSRF guard', () {
    test('refuses to proxy an internal target URL', () async {
      final client = _ScriptedClient((req) => http.Response('proxied', 200));
      final jina = JinaReaderClient(
        client: client,
        guard: SsrfGuard(resolver: _resolver({})),
      );
      final out = await jina.fetch('http://169.254.169.254/latest/meta-data/');
      expect(out, isNull);
      expect(client.sent, isEmpty);
    });

    test('proxies a public target URL', () async {
      final client = _ScriptedClient(
        (req) => http.Response('reader body', 200),
      );
      final jina = JinaReaderClient(
        client: client,
        guard: SsrfGuard(resolver: _resolver({'example.com': '93.184.216.34'})),
      );
      final out = await jina.fetch('https://example.com/page');
      expect(out, 'reader body');
      // The request goes to the (public) Jina reader host.
      expect(client.sent.single.host, 'r.jina.ai');
    });
  });
}
