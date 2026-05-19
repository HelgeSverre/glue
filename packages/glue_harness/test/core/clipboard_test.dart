import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue_harness/src/core/clipboard.dart';
import 'package:test/test.dart';

void main() {
  // ── encodeOsc52 ─────────────────────────────────────────────────────

  group('encodeOsc52', () {
    test('emits the base OSC52 set-clipboard sequence with no TMUX', () {
      final out = encodeOsc52('hi', env: const {});
      expect(out, isNotNull);
      // \e]52;c;<base64-of-hi>\e\\
      expect(
          out, equals('\x1b]52;c;${base64.encode(utf8.encode('hi'))}\x1b\\'));
    });

    test('wraps the sequence in tmux passthrough when TMUX is set', () {
      final out = encodeOsc52('hi', env: const {'TMUX': '/tmp/tmux'});
      expect(out, isNotNull);
      // Outer envelope must be \ePtmux;…\e\\ and every inner ESC doubled.
      expect(out, startsWith('\x1bPtmux;'));
      expect(out, endsWith('\x1b\\'));
      // The original ESC bytes inside the OSC52 payload are doubled.
      final innerB64 = base64.encode(utf8.encode('hi'));
      expect(out, contains('\x1b\x1b]52;c;$innerB64\x1b\x1b\\'));
    });

    test('returns null for payloads larger than the size cap', () {
      // osc52MaxBytes worth of UTF-8 + 1 extra byte = over the cap.
      final big = 'a' * (osc52MaxBytes + 1);
      expect(encodeOsc52(big, env: const {}), isNull);
    });

    test('UTF-8 multibyte content is encoded faithfully', () {
      const source = '漢字 😀';
      final out = encodeOsc52(source, env: const {})!;
      const marker = '\x1b]52;c;';
      final start = out.indexOf(marker) + marker.length;
      final end = out.indexOf('\x1b\\', start);
      final decoded = utf8.decode(base64.decode(out.substring(start, end)));
      expect(decoded, equals(source));
    });
  });

  // ── copyToClipboard fallback ordering ───────────────────────────────

  group('copyToClipboard', () {
    test('prefers OSC52 when running inside tmux', () async {
      final emitted = <String>[];
      var hostCalled = false;
      final ok = await copyToClipboard(
        'tmux-text',
        environmentOverride: const {'TMUX': '/tmp/tmux'},
        osc52Writer: emitted.add,
        runner: (exe, args) async {
          hostCalled = true;
          throw StateError('host should not be invoked when TMUX is set');
        },
      );
      expect(ok, isTrue);
      expect(emitted, hasLength(1));
      expect(hostCalled, isFalse);
    });

    test('prefers OSC52 when running over SSH', () async {
      final emitted = <String>[];
      final ok = await copyToClipboard(
        'ssh-text',
        environmentOverride: const {'SSH_CONNECTION': '… 22 …'},
        osc52Writer: emitted.add,
        runner: (exe, args) async {
          throw StateError('host should not be invoked over SSH');
        },
      );
      expect(ok, isTrue);
      expect(emitted, hasLength(1));
    });

    test('falls back to OSC52 if host commands all fail', () async {
      final emitted = <String>[];
      final ok = await copyToClipboard(
        'fallback',
        environmentOverride: const {},
        osc52Writer: emitted.add,
        runner: (exe, args) async {
          // Simulate every host command failing with a non-zero exit.
          return ClipboardProcess(
            stdin: IOSink(_NoopSink()),
            exitCode: Future.value(1),
          );
        },
      );
      // On platforms with no host candidates configured (e.g. exotic OSes)
      // OSC52 still wins. On platforms with candidates, host fails then
      // OSC52 wins. Either way we expect success and at least one emit.
      expect(ok, isTrue);
      expect(emitted, hasLength(1));
    });

    test('returns false if every transport fails', () async {
      final ok = await copyToClipboard(
        'a' * (osc52MaxBytes + 1), // payload too large for OSC52
        environmentOverride: const {'TMUX': '/tmp/tmux'},
        osc52Writer: (_) {},
        runner: (exe, args) async => ClipboardProcess(
          stdin: IOSink(_NoopSink()),
          exitCode: Future.value(1),
        ),
      );
      expect(ok, isFalse);
    });
  });
}

/// Sink that swallows everything — used to stand in for a process's
/// stdin without spawning a real subprocess.
class _NoopSink implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }

  @override
  Future<void> close() async {}
}
