import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue_runtimes/src/common/runtime_exception.dart';
import 'package:glue_runtimes/src/common/shell_quote.dart';
import 'package:glue_runtimes/src/sprites/config.dart';

/// Result of a synchronous exec via the sprite CLI.
class SpritesExecResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  SpritesExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

/// Minimal contract over the `sprite` CLI. All operations route
/// through subprocess invocations; concrete implementation is
/// [SpritesCli], and tests substitute a fake.
///
/// **Naming/test-seam pattern:** Sprites integrates by shelling out
/// to a CLI binary, so there's no equivalent of `http.Client` for
/// tests to inject. The seam is this `*Base` abstract class +
/// `FakeSpritesCli` in tests. Same pattern as [ModalSidecarBase]
/// (subprocess-based). Daytona uses `http.Client` injection instead.
abstract class SpritesCliBase {
  /// Returns true when the `sprite` binary is on `$PATH` and
  /// `sprite list` succeeds (i.e. the user is authenticated).
  Future<bool> isAvailable();

  /// Returns true if a sprite with [name] exists on the user's
  /// account.
  Future<bool> spriteExists(String name);

  /// Creates a sprite with [name].
  Future<void> createSprite(String name);

  /// Deletes [name]. Idempotent — missing sprite is treated as success.
  Future<void> deleteSprite(String name);

  /// Runs [command] inside the sprite and waits for completion.
  /// Uses the CLI's default WebSocket exec mode for reliable exit
  /// codes (the experimental `--http-post` mode drops them).
  Future<SpritesExecResult> execCapture(
    String spriteName,
    String command, {
    Duration? timeout,
  });

  /// Like [execCapture] but streams [stdinBytes] to the command's
  /// standard input instead of relying on the caller to inline data in
  /// the command string. Used to ship large payloads (e.g. a base64
  /// bundle piped into `base64 -d`) without hitting the single-argv
  /// `ARG_MAX`/`MAX_ARG_STRLEN` (E2BIG) ceiling — and without exposing
  /// the payload in the host's `ps` listing.
  Future<SpritesExecResult> execCaptureStdin(
    String spriteName,
    String command,
    List<int> stdinBytes, {
    Duration? timeout,
  });

  /// Starts [command] and returns a streaming [Process]. The caller
  /// is responsible for closing stdin / waiting on exitCode.
  Future<Process> execStream(String spriteName, String command);
}

/// Concrete [SpritesCliBase] that shells out to the `sprite` binary.
class SpritesCli implements SpritesCliBase {
  final SpritesConfig config;

  SpritesCli(this.config);

  @override
  Future<bool> isAvailable() async {
    try {
      final res = await Process.run(config.spriteCliPath, ['list']);
      return res.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<bool> spriteExists(String name) async {
    // `sprite api /sprites/<name>` always exits 0 regardless of the
    // HTTP status — the success signal lives in the body. The
    // wrapper interleaves curl progress output with the JSON
    // response on stdout (no newline between them), so we have to
    // scan for a balanced JSON object instead of trimming.
    final res = await Process.run(config.spriteCliPath, [
      'api',
      '/sprites/$name',
    ]);
    final json = _extractFirstJsonObject(res.stdout as String);
    if (json is Map) {
      if (json.containsKey('name')) return true;
      final err = json['error']?.toString().toLowerCase();
      if (err != null && err.contains('not found')) return false;
    }
    throw RuntimeApiException(
      runtimeId: 'sprites',
      statusCode: res.exitCode,
      endpoint: 'sprite_exists',
      message: 'unexpected response',
      body: '${res.stdout}\n${res.stderr}',
    );
  }

  /// Scans [body] for the first balanced `{...}` JSON object and
  /// returns the decoded value (or `null` if none found / parse fails).
  /// Naïve but sufficient — the responses we care about contain a
  /// single top-level object surrounded by curl progress noise.
  Object? _extractFirstJsonObject(String body) {
    var depth = 0;
    var start = -1;
    var inString = false;
    var escape = false;
    for (var i = 0; i < body.length; i++) {
      final c = body[i];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (c == r'\') {
          escape = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
        continue;
      }
      if (c == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0 && start >= 0) {
          try {
            return jsonDecode(body.substring(start, i + 1));
          } catch (_) {
            // Reset and keep scanning.
            start = -1;
          }
        }
      }
    }
    return null;
  }

  @override
  Future<void> createSprite(String name) async {
    // The CLI's `create` subcommand handles capacity-wait + URL
    // settings consistently. We pin auth=sprite so glue isn't
    // accidentally exposing a public-by-default URL.
    final r = await _runWithTimeout([
      'create',
      name,
    ], limit: config.startTimeout);
    if (r.timedOut) {
      // A plain `Process.run(...).timeout(...)` would throw a raw
      // TimeoutException and leave the `sprite create` child running.
      // _runWithTimeout kills it; surface the typed exception callers
      // expect.
      throw RuntimeApiException(
        runtimeId: 'sprites',
        statusCode: -1,
        endpoint: 'create_sprite',
        message:
            'sprite create timed out after '
            '${config.startTimeout.inSeconds}s',
        body: '${r.result.stdout}\n${r.result.stderr}',
      );
    }
    if (r.result.exitCode != 0) {
      throw RuntimeApiException(
        runtimeId: 'sprites',
        statusCode: r.result.exitCode,
        endpoint: 'create_sprite',
        message: 'sprite create failed',
        body: '${r.result.stdout}\n${r.result.stderr}',
      );
    }
  }

  @override
  Future<void> deleteSprite(String name) async {
    // `sprite api /v1/sprites/<name> -X DELETE` — the absolute path
    // form sidesteps the `-s` sprite-context that the CLI would
    // otherwise prepend, and the wrapper still always exits 0 so we
    // inspect the body for the "not found" case (idempotent).
    final res = await Process.run(config.spriteCliPath, [
      'api',
      '/v1/sprites/$name',
      '-X',
      'DELETE',
    ]);
    final out = '${res.stdout}${res.stderr}'.toLowerCase();
    if (out.contains('not found') || out.contains('404')) return;
    // A successful DELETE returns 204 with empty body; the wrapper
    // produces only its progress-bar lines (no JSON). If we see
    // an `"error"` JSON key, propagate it.
    if (out.contains('"error"')) {
      throw RuntimeApiException(
        runtimeId: 'sprites',
        statusCode: res.exitCode,
        endpoint: 'delete_sprite',
        message: 'sprite delete failed',
        body: '${res.stdout}\n${res.stderr}',
      );
    }
  }

  @override
  Future<SpritesExecResult> execCapture(
    String spriteName,
    String command, {
    Duration? timeout,
  }) async {
    final args = ['exec', '-s', spriteName, '--', 'sh', '-c', command];
    final r = await _runWithTimeout(args, limit: timeout ?? config.execTimeout);
    return r.result;
  }

  @override
  Future<SpritesExecResult> execCaptureStdin(
    String spriteName,
    String command,
    List<int> stdinBytes, {
    Duration? timeout,
  }) async {
    final args = ['exec', '-s', spriteName, '--', 'sh', '-c', command];
    final r = await _runWithTimeout(
      args,
      limit: timeout ?? config.execTimeout,
      stdinBytes: stdinBytes,
    );
    return r.result;
  }

  @override
  Future<Process> execStream(String spriteName, String command) {
    final args = ['exec', '-s', spriteName, '--', 'sh', '-c', command];
    return Process.start(config.spriteCliPath, args);
  }

  /// Starts the `sprite` CLI with [args], optionally streaming
  /// [stdinBytes] to the child's stdin, and waits with a [limit] that
  /// **kills the child** on expiry. `Process.run(...).timeout(...)`
  /// only abandons the Dart future — the subprocess (and the remote
  /// command it drives) keeps running. Returns the collected result
  /// plus whether the timeout fired.
  Future<({SpritesExecResult result, bool timedOut})> _runWithTimeout(
    List<String> args, {
    required Duration limit,
    List<int>? stdinBytes,
  }) async {
    final process = await Process.start(config.spriteCliPath, args);
    if (stdinBytes != null) {
      process.stdin.add(stdinBytes);
    }
    // Close stdin so readers (e.g. `base64 -d`) see EOF. Ignore a
    // broken pipe if the child has already exited.
    unawaited(process.stdin.close().catchError((Object _) {}));
    // Lenient decode: matches the old `Process.run` behaviour and
    // avoids crashing exec on a stray non-UTF-8 byte in child output.
    const decoder = Utf8Decoder(allowMalformed: true);
    final stdoutF = process.stdout.transform(decoder).join();
    final stderrF = process.stderr.transform(decoder).join();
    var timedOut = false;
    final code = await process.exitCode.timeout(
      limit,
      onTimeout: () {
        timedOut = true;
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    final out = await stdoutF;
    final err = await stderrF;
    return (
      result: SpritesExecResult(
        exitCode: timedOut ? -1 : code,
        stdout: out,
        stderr: timedOut
            ? (err.isEmpty
                  ? 'glue: exec timed out'
                  : '$err\nglue: exec timed out')
            : err,
      ),
      timedOut: timedOut,
    );
  }
}

/// Convenience helpers for filesystem ops layered on top of exec.
/// Sprites has no stable REST filesystem endpoint at this API
/// version, so reads/writes/lists all route through shell commands
/// inside the sprite. Workable; slower than a native API; will be
/// swapped out when sprites ships a stable `/filesystem` endpoint.
extension SpritesFs on SpritesCliBase {
  /// Reads [path]'s bytes via `base64 -w 0`. Base64 avoids any
  /// terminal munging of binary bytes (NUL, CR, etc.) on the way
  /// back through the WS framing.
  Future<List<int>> readFileBytes(String spriteName, String path) async {
    final res = await execCapture(
      spriteName,
      'base64 -w 0 ${shQuote(path)} 2>/dev/null || base64 ${shQuote(path)}',
    );
    if (res.exitCode != 0) {
      throw RuntimeApiException(
        runtimeId: 'sprites',
        statusCode: res.exitCode,
        endpoint: 'read_file',
        message: 'file read failed',
        body: res.stderr,
      );
    }
    // The CLI prints a trailing newline; strip whitespace before
    // decoding so base64 doesn't choke on it.
    return base64Decode(res.stdout.replaceAll(RegExp(r'\s+'), ''));
  }

  /// Writes [bytes] to [path] by piping a base64 payload into `base64
  /// -d`. We invoke `sh -c "mkdir -p $(dirname …) && base64 -d > …"`
  /// to be parent-dir-creating, matching the host workspace's
  /// behaviour.
  ///
  /// The base64 payload is streamed via **stdin**, not inlined into the
  /// command string. Inlining put the whole payload into a single argv
  /// value, which hit `ARG_MAX`/`MAX_ARG_STRLEN` (E2BIG) far below the
  /// advertised 3 MB bundle cap, and leaked the bytes (incl. any secret
  /// a `write_file` is delivering) into the host's `ps` output. base64
  /// text is ASCII, so it survives the CLI's WebSocket framing intact.
  Future<void> writeFileBytes(
    String spriteName,
    String path,
    List<int> bytes,
  ) async {
    final encoded = base64Encode(bytes);
    final p = shQuote(path);
    final res = await execCaptureStdin(
      spriteName,
      'mkdir -p "\$(dirname $p)" && base64 -d > $p',
      utf8.encode(encoded),
    );
    if (res.exitCode != 0) {
      throw RuntimeApiException(
        runtimeId: 'sprites',
        statusCode: res.exitCode,
        endpoint: 'write_file',
        message: 'file write failed',
        body: res.stderr,
      );
    }
  }

  /// Returns true when [path] exists.
  Future<bool> pathExists(String spriteName, String path) async {
    final res = await execCapture(spriteName, 'test -e ${shQuote(path)}');
    return res.exitCode == 0;
  }

  /// Returns true when [path] is a directory.
  Future<bool> isDirectory(String spriteName, String path) async {
    final res = await execCapture(spriteName, 'test -d ${shQuote(path)}');
    return res.exitCode == 0;
  }

  /// Returns the byte size of [path], or `null` when missing.
  Future<int?> sizeOf(String spriteName, String path) async {
    final p = shQuote(path);
    // GNU and BSD `stat` take different flags; the wc -c fallback
    // works everywhere but reads the full file.
    final res = await execCapture(
      spriteName,
      'stat -c %s $p 2>/dev/null || stat -f %z $p 2>/dev/null || wc -c < $p',
    );
    if (res.exitCode != 0) return null;
    return int.tryParse(res.stdout.trim());
  }

  /// Returns immediate children of [path] as a list of
  /// `(name, isDirectory)` records.
  Future<List<({String name, bool isDirectory})>> listDir(
    String spriteName,
    String path,
  ) async {
    final p = shQuote(path);
    // `find … -mindepth 1 -maxdepth 1 -printf '%y %f\n'` would be
    // ideal but `-printf` is GNU-only. We use `ls -1Ap` instead —
    // a trailing `/` marks directories.
    final res = await execCapture(spriteName, 'ls -1Ap $p');
    if (res.exitCode != 0) {
      throw RuntimeApiException(
        runtimeId: 'sprites',
        statusCode: res.exitCode,
        endpoint: 'list_dir',
        message: 'directory list failed',
        body: res.stderr,
      );
    }
    return res.stdout.split('\n').where((l) => l.isNotEmpty).map((line) {
      final isDir = line.endsWith('/');
      final name = isDir ? line.substring(0, line.length - 1) : line;
      return (name: name, isDirectory: isDir);
    }).toList();
  }
}
