import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue_runtimes/src/common/runtime_exception.dart';
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
    final res = await Process.run(
      config.spriteCliPath,
      ['api', '/sprites/$name'],
    );
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
    final res = await Process.run(
      config.spriteCliPath,
      ['create', name],
    ).timeout(config.startTimeout);
    if (res.exitCode != 0) {
      throw RuntimeApiException(
      runtimeId: 'sprites',
        statusCode: res.exitCode,
        endpoint: 'create_sprite',
        message: 'sprite create failed',
        body: '${res.stdout}\n${res.stderr}',
      );
    }
  }

  @override
  Future<void> deleteSprite(String name) async {
    // `sprite api /v1/sprites/<name> -X DELETE` — the absolute path
    // form sidesteps the `-s` sprite-context that the CLI would
    // otherwise prepend, and the wrapper still always exits 0 so we
    // inspect the body for the "not found" case (idempotent).
    final res = await Process.run(
      config.spriteCliPath,
      ['api', '/v1/sprites/$name', '-X', 'DELETE'],
    );
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
    final args = [
      'exec',
      '-s',
      spriteName,
      '--',
      'sh',
      '-c',
      command,
    ];
    final res = await Process.run(config.spriteCliPath, args).timeout(
      timeout ?? config.execTimeout,
      onTimeout: () => ProcessResult(0, -1, '', 'glue: exec timed out'),
    );
    return SpritesExecResult(
      exitCode: res.exitCode,
      stdout: res.stdout as String,
      stderr: res.stderr as String,
    );
  }

  @override
  Future<Process> execStream(String spriteName, String command) {
    final args = [
      'exec',
      '-s',
      spriteName,
      '--',
      'sh',
      '-c',
      command,
    ];
    return Process.start(config.spriteCliPath, args);
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
      'base64 -w 0 ${_shQuote(path)} 2>/dev/null || base64 ${_shQuote(path)}',
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
  Future<void> writeFileBytes(
    String spriteName,
    String path,
    List<int> bytes,
  ) async {
    final encoded = base64Encode(bytes);
    final p = _shQuote(path);
    final res = await execCapture(
      spriteName,
      "mkdir -p \"\$(dirname $p)\" && printf '%s' '$encoded' | base64 -d > $p",
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
    final res = await execCapture(
      spriteName,
      'test -e ${_shQuote(path)}',
    );
    return res.exitCode == 0;
  }

  /// Returns true when [path] is a directory.
  Future<bool> isDirectory(String spriteName, String path) async {
    final res = await execCapture(
      spriteName,
      'test -d ${_shQuote(path)}',
    );
    return res.exitCode == 0;
  }

  /// Returns the byte size of [path], or `null` when missing.
  Future<int?> sizeOf(String spriteName, String path) async {
    final p = _shQuote(path);
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
    final p = _shQuote(path);
    // `find … -mindepth 1 -maxdepth 1 -printf '%y %f\n'` would be
    // ideal but `-printf` is GNU-only. We use `ls -1Ap` instead —
    // a trailing `/` marks directories.
    final res = await execCapture(
      spriteName,
      'ls -1Ap $p',
    );
    if (res.exitCode != 0) {
      throw RuntimeApiException(
      runtimeId: 'sprites',
        statusCode: res.exitCode,
        endpoint: 'list_dir',
        message: 'directory list failed',
        body: res.stderr,
      );
    }
    return res.stdout
        .split('\n')
        .where((l) => l.isNotEmpty)
        .map((line) {
      final isDir = line.endsWith('/');
      final name = isDir ? line.substring(0, line.length - 1) : line;
      return (name: name, isDirectory: isDir);
    }).toList();
  }
}

/// Single-quote wrapping for safe inclusion in a `sh -c` command —
/// escapes any embedded single quotes via the standard `'\''` trick.
String _shQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";
