/// Token manager tests — fake http.Client, no network.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue/src/credentials/credential_store.dart';
import 'package:glue/src/providers/copilot_token_manager.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _FakeHttp extends http.BaseClient {
  _FakeHttp(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest req) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

http.StreamedResponse _jsonResponse(int status, Map<String, dynamic> body) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    status,
    headers: {'content-type': 'application/json'},
  );
}

Directory _scratch() =>
    Directory.systemTemp.createTempSync('glue_copilot_token_test_');

void main() {
  group('exchangeGithubTokenForCopilotToken', () {
    test('POSTs the github token and returns Copilot token + expiry', () async {
      http.BaseRequest? captured;
      final client = _FakeHttp((req) async {
        captured = req;
        return _jsonResponse(200, {
          'token': 'tid=abc;exp=123',
          'expires_at': 1800000000,
        });
      });

      final result =
          await exchangeGithubTokenForCopilotToken('gho_xxx', client: client);

      expect(captured!.headers['authorization'], 'token gho_xxx');
      expect(result.token, 'tid=abc;exp=123');
      expect(
        result.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000, isUtc: true),
      );
    });

    test('throws on non-200', () async {
      final client = _FakeHttp(
        (req) async => _jsonResponse(401, {'message': 'bad token'}),
      );
      expect(
        () => exchangeGithubTokenForCopilotToken('gho_bad', client: client),
        throwsA(isA<CopilotAuthException>()),
      );
    });
  });

  group('freshCopilotToken', () {
    test('returns cached token when not near expiry', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );
      final future = DateTime.now().toUtc().add(const Duration(minutes: 20));
      store.setFields('copilot', {
        'github_token': 'gho_xxx',
        'copilot_token': 'tid=cached',
        'copilot_token_expires_at': future.toIso8601String(),
      });

      final client = _FakeHttp(
        (req) async => throw StateError('should not be called'),
      );
      final token = await freshCopilotToken(store, client: client);
      expect(token, 'tid=cached');
    });

    test('re-exchanges when token is past expiry', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );
      final past = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      store.setFields('copilot', {
        'github_token': 'gho_xxx',
        'copilot_token': 'tid=stale',
        'copilot_token_expires_at': past.toIso8601String(),
      });

      var callCount = 0;
      final client = _FakeHttp((req) async {
        callCount++;
        return _jsonResponse(200, {
          'token': 'tid=fresh',
          'expires_at': DateTime.now()
                  .add(const Duration(minutes: 30))
                  .millisecondsSinceEpoch ~/
              1000,
        });
      });

      final token = await freshCopilotToken(store, client: client);
      expect(token, 'tid=fresh');
      expect(callCount, 1);
      expect(store.getField('copilot', 'copilot_token'), 'tid=fresh');
    });

    test('re-exchanges when no copilot_token is stored yet', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );
      store.setFields('copilot', {'github_token': 'gho_xxx'});

      final client = _FakeHttp((req) async {
        return _jsonResponse(200, {
          'token': 'tid=initial',
          'expires_at': DateTime.now()
                  .add(const Duration(minutes: 30))
                  .millisecondsSinceEpoch ~/
              1000,
        });
      });

      final token = await freshCopilotToken(store, client: client);
      expect(token, 'tid=initial');
    });

    test('throws when no github_token is stored', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );
      final client = _FakeHttp(
        (req) async => throw StateError('no call expected'),
      );
      expect(
        () => freshCopilotToken(store, client: client),
        throwsA(isA<CopilotAuthException>()),
      );
    });
  });
}
