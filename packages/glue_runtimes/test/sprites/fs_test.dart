import 'dart:convert';

import 'package:glue_runtimes/src/common/runtime_exception.dart';
import 'package:glue_runtimes/src/sprites/cli.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  group('SpritesFs.writeFileBytes (H15)', () {
    test('streams the base64 payload via stdin, not inline in argv', () async {
      final cli = FakeSpritesCli();
      final bytes = utf8.encode('super-secret-token-value');
      final encoded = base64Encode(bytes);

      await cli.writeFileBytes('my-sprite', '/workspace/.env', bytes);

      expect(
        cli.stdinCommands,
        hasLength(1),
        reason: 'the write must route through the stdin-streaming exec',
      );
      final call = cli.stdinCommands.single;

      // The payload must NOT appear in the command string: inlining it
      // there blew past ARG_MAX (E2BIG) and exposed secrets in `ps`.
      expect(
        call.command,
        isNot(contains(encoded)),
        reason: 'payload must not be inlined into the argv command',
      );
      expect(call.command, contains('base64 -d'));
      // The base64 text rides on stdin instead.
      expect(utf8.decode(call.stdin), encoded);
    });

    test('round-trips arbitrary bytes through stdin base64', () async {
      final cli = FakeSpritesCli();
      final bytes = [for (var i = 0; i < 256; i++) i];
      await cli.writeFileBytes('my-sprite', '/workspace/blob.bin', bytes);
      final decoded = base64Decode(utf8.decode(cli.stdinCommands.single.stdin));
      expect(decoded, bytes);
    });

    test('surfaces a non-zero write as RuntimeApiException', () async {
      final cli = FakeSpritesCli()..failStdinWrites = true;
      await expectLater(
        cli.writeFileBytes('my-sprite', '/workspace/x', [1, 2, 3]),
        throwsA(
          isA<RuntimeApiException>().having(
            (e) => e.endpoint,
            'endpoint',
            'write_file',
          ),
        ),
      );
    });
  });
}
