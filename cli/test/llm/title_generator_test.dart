import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:glue/src/llm/title_generator.dart';

/// Helper to build a mock Anthropic Messages API response body.
String _apiResponse(String text) => jsonEncode({
      'content': [
        {'type': 'text', 'text': text}
      ],
    });

void main() {
  group('TitleGenerator.generate', () {
    test('returns title from successful API response', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/messages');
        expect(request.headers['x-api-key'], 'test-key');
        return http.Response(_apiResponse('Fix auth bug'), 200);
      });

      final generator = TitleGenerator(
        httpClient: client,
        apiKey: 'test-key',
        model: 'claude-haiku-4-5-20251001',
      );

      final title = await generator.generate('The login is broken');
      expect(title, 'Fix auth bug');
    });

    test('returns null on API error', () async {
      final client = MockClient((_) async => http.Response('error', 500));

      final generator = TitleGenerator(
        httpClient: client,
        apiKey: 'test-key',
        model: 'claude-haiku-4-5-20251001',
      );

      expect(await generator.generate('test'), isNull);
    });

    test('returns null on network exception', () async {
      final client = MockClient((_) async => throw Exception('network error'));

      final generator = TitleGenerator(
        httpClient: client,
        apiKey: 'test-key',
        model: 'claude-haiku-4-5-20251001',
      );

      expect(await generator.generate('test'), isNull);
    });

    test('returns null on empty content array', () async {
      final client = MockClient((_) async {
        return http.Response(jsonEncode({'content': []}), 200);
      });

      final generator = TitleGenerator(
        httpClient: client,
        apiKey: 'test-key',
        model: 'claude-haiku-4-5-20251001',
      );

      expect(await generator.generate('test'), isNull);
    });
  });

  group('TitleGenerator.sanitize', () {
    test('passes through clean ASCII text', () {
      expect(TitleGenerator.sanitize('Fix auth bug'), 'Fix auth bug');
    });

    test('strips emoji', () {
      expect(TitleGenerator.sanitize('Fix auth bug \u{1F41B}'), 'Fix auth bug');
    });

    test('strips zalgo combining marks', () {
      // "Fix" with combining marks
      expect(
        TitleGenerator.sanitize('F\u0300\u0301ix auth'),
        'Fix auth',
      );
    });

    test('collapses whitespace', () {
      expect(TitleGenerator.sanitize('Fix   auth   bug'), 'Fix auth bug');
    });

    test('returns null for empty input', () {
      expect(TitleGenerator.sanitize(''), isNull);
    });

    test('returns null for null input', () {
      expect(TitleGenerator.sanitize(null), isNull);
    });

    test('returns null when only non-ASCII remains', () {
      expect(TitleGenerator.sanitize('\u{1F600}\u{1F601}'), isNull);
    });

    test('truncates to 60 chars', () {
      final long = 'A' * 100;
      final result = TitleGenerator.sanitize(long);
      expect(result!.length, 60);
    });

    test('trims leading and trailing whitespace', () {
      expect(TitleGenerator.sanitize('  Fix bug  '), 'Fix bug');
    });
  });
}
