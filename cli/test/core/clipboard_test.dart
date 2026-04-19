/// Clipboard helper — injectable runner so tests don't spawn real
/// `pbcopy` / `clip` / `wl-copy`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:glue/src/core/clipboard.dart';
import 'package:test/test.dart';

// ignore_for_file: close_sinks

class _FakeStdin implements IOSink {
  final BytesBuilder buffer = BytesBuilder();
  bool closed = false;

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) => buffer.add(data);

  @override
  void write(Object? obj) => buffer.add(utf8.encode(obj.toString()));

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> get done async {}

  @override
  Future<void> flush() async {}

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? obj = '']) {}
}

ClipboardProcess _proc({required int exit}) {
  final stdin = _FakeStdin();
  return ClipboardProcess(stdin: stdin, exitCode: Future.value(exit));
}

void main() {
  group('copyToClipboard', () {
    test('returns true when first command exits 0', () async {
      var calls = 0;
      final ok = await copyToClipboard(
        'ABCD-1234',
        runner: (exe, args) async {
          calls++;
          return _proc(exit: 0);
        },
      );
      expect(ok, isTrue);
      expect(calls, 1);
    });

    test('writes the provided text to the process stdin and closes it',
        () async {
      _FakeStdin? capturedStdin;
      await copyToClipboard(
        'hello',
        runner: (exe, args) async {
          final stdin = _FakeStdin();
          capturedStdin = stdin;
          return ClipboardProcess(stdin: stdin, exitCode: Future.value(0));
        },
      );
      expect(utf8.decode(capturedStdin!.buffer.toBytes()), 'hello');
      expect(capturedStdin!.closed, isTrue);
    });

    test(
      'falls back to the next command on non-zero exit',
      () async {
        if (!Platform.isLinux) return;
        var calls = 0;
        final ok = await copyToClipboard(
          'X',
          runner: (exe, args) async {
            calls++;
            return _proc(exit: calls == 1 ? 1 : 0);
          },
        );
        expect(ok, isTrue);
        expect(calls, greaterThan(1));
      },
    );

    test('returns false when every command throws', () async {
      final ok = await copyToClipboard(
        'X',
        runner: (_, __) async => throw const ProcessException('nope', []),
      );
      expect(ok, isFalse);
    });

    test('returns false when every command exits non-zero', () async {
      final ok = await copyToClipboard(
        'X',
        runner: (_, __) async => _proc(exit: 1),
      );
      expect(ok, isFalse);
    });
  });
}
