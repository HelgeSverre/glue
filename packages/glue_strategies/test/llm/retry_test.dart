import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/src/llm/retry.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('retryStream (M6)', () {
    test('passes values through when the first attempt succeeds', () async {
      var attempts = 0;
      final sleeps = <Duration>[];
      final out = await retryStream<int>(
        () {
          attempts++;
          return Stream.fromIterable([1, 2, 3]);
        },
        sleep: (d) async => sleeps.add(d),
        random: Random(1),
      ).toList();

      expect(out, [1, 2, 3]);
      expect(attempts, 1);
      expect(sleeps, isEmpty);
    });

    test('retries a transient failure then succeeds', () async {
      var attempts = 0;
      final sleeps = <Duration>[];
      final out = await retryStream<int>(
        () {
          attempts++;
          if (attempts == 1) {
            return Stream.error(const SocketException('conn reset'));
          }
          return Stream.fromIterable([7]);
        },
        sleep: (d) async => sleeps.add(d),
        random: Random(1),
      ).toList();

      expect(out, [7]);
      expect(attempts, 2);
      expect(sleeps, hasLength(1));
    });

    test('fails fast on a non-transient error (no retry)', () async {
      var attempts = 0;
      await expectLater(
        retryStream<int>(
          () {
            attempts++;
            return Stream.error(Exception('OpenAI API error 400: bad request'));
          },
          sleep: (_) async {},
          random: Random(1),
        ).toList(),
        throwsA(isA<Exception>()),
      );
      expect(attempts, 1);
    });

    test('does not retry once the stream has yielded output', () async {
      var attempts = 0;
      final collected = <int>[];
      await expectLater(
        retryStream<int>(
          () {
            attempts++;
            return () async* {
              yield 1;
              throw const SocketException('mid-stream');
            }();
          },
          sleep: (_) async {},
          random: Random(1),
        ).forEach(collected.add),
        throwsA(isA<SocketException>()),
      );
      expect(collected, [1]);
      expect(attempts, 1);
    });

    test('gives up after maxAttempts transient failures', () async {
      var attempts = 0;
      await expectLater(
        retryStream<int>(
          () {
            attempts++;
            return Stream.error(const SocketException('always'));
          },
          maxAttempts: 3,
          sleep: (_) async {},
          random: Random(1),
        ).toList(),
        throwsA(isA<SocketException>()),
      );
      expect(attempts, 3);
    });
  });

  group('isTransientLlmError', () {
    test('429 message is transient', () {
      expect(
        isTransientLlmError(Exception('OpenAI API error 429: slow down')),
        isTrue,
      );
    });

    test('5xx message is transient', () {
      expect(
        isTransientLlmError(Exception('Anthropic API error 503: overloaded')),
        isTrue,
      );
    });

    test('4xx (non-429) message is not transient', () {
      expect(
        isTransientLlmError(Exception('OpenAI API error 400: bad request')),
        isFalse,
      );
      expect(
        isTransientLlmError(Exception('OpenAI API error 401: unauthorized')),
        isFalse,
      );
    });

    test('network exceptions are transient', () {
      expect(isTransientLlmError(const SocketException('down')), isTrue);
      expect(isTransientLlmError(http.ClientException('reset')), isTrue);
      expect(isTransientLlmError(TimeoutException('slow')), isTrue);
    });

    test('ToolsNotSupportedException is not transient', () {
      expect(
        isTransientLlmError(const ToolsNotSupportedException('qwen2.5:7b')),
        isFalse,
      );
    });
  });
}
