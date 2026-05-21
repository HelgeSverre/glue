import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue_runtimes/src/common/runtime_exception.dart';
import 'package:glue_runtimes/src/modal/config.dart';
import 'package:glue_runtimes/src/modal/running_command.dart';
import 'package:glue_runtimes/src/modal/sidecar_source.g.dart';

/// Result of a synchronous exec via the modal sidecar.
class ModalExecResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  ModalExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

/// Filesystem entry returned by `listDir`.
class ModalFsEntry {
  final String name;
  final bool isDirectory;
  final int size;

  ModalFsEntry({required this.name, required this.isDirectory, this.size = 0});
}

/// File stat result.
class ModalStat {
  final int size;
  final bool isDirectory;

  ModalStat({required this.size, required this.isDirectory});
}

/// Contract over the Python sidecar that holds the modal sandbox.
/// Mockable from tests via [FakeModalSidecar].
///
/// **Naming/test-seam pattern:** Modal's sandbox lives behind a
/// Python child process speaking JSON-RPC over stdin/stdout, so
/// there's no equivalent of `http.Client` for tests to inject. The
/// seam is this `*Base` abstract class + `FakeModalSidecar` in tests.
/// Same pattern as [SpritesCliBase] (subprocess-based). Daytona uses
/// `http.Client` injection instead.
abstract class ModalSidecarBase {
  /// True when the sidecar is ready to receive requests.
  bool get isReady;

  Future<bool> isAvailable();
  Future<void> start();
  Future<void> shutdown();

  Future<ModalExecResult> execCapture(String command, {Duration? timeout});

  Future<List<int>> readFile(String path);
  Future<void> writeFile(String path, List<int> bytes);

  Future<bool> exists(String path);
  Future<bool> isDirectory(String path);
  Future<List<ModalFsEntry>> listDir(String path);
  Future<ModalStat?> stat(String path);

  /// Starts a streaming exec and returns a [ModalRunningCommand] that
  /// receives async output via the sidecar's `stream_data` events.
  Future<ModalRunningCommand> startStream(String command);
}

/// Concrete sidecar that spawns the embedded Python script and
/// dispatches JSON-RPC requests to it.
class ModalSidecar implements ModalSidecarBase {
  final ModalConfig config;

  Process? _proc;
  int _nextId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final Map<String, ModalRunningCommand> _streams = {};
  final Completer<String> _readyCompleter = Completer();
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  String? _sandboxId;
  bool _shuttingDown = false;
  File? _scriptFile;

  ModalSidecar(this.config);

  @override
  bool get isReady => _proc != null && _readyCompleter.isCompleted;

  /// The sandbox id once the sidecar has reported `ready`.
  String? get sandboxId => _sandboxId;

  @override
  Future<bool> isAvailable() async {
    final python = await _resolvePython();
    if (python == null) return false;
    try {
      final res = await Process.run(python, [
        '-c',
        'import modal; print(modal.__version__)',
      ]);
      return res.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<void> start() async {
    if (_proc != null) return;
    final python = await _resolvePython();
    if (python == null) {
      throw const RuntimeApiException(
        runtimeId: 'modal',
        endpoint: 'start',
        message:
            'no python interpreter with the modal package found — set '
            '`MODAL_PYTHON` or `modal.python_path` in config.',
      );
    }

    // Materialize the embedded sidecar script to a temp file so the
    // python interpreter can load it. Cached per process so repeated
    // sidecar restarts reuse the same path.
    final dir = await Directory.systemTemp.createTemp('glue_modal_');
    _scriptFile = File('${dir.path}/modal_sidecar.py')
      ..writeAsStringSync(modalSidecarSource);

    final args = [
      _scriptFile!.path,
      config.appName,
      '--timeout',
      config.sandboxTimeoutSeconds.toString(),
      if (config.image != null) ...['--image', config.image!],
    ];
    _proc = await Process.start(python, args);

    _stdoutSub = _proc!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onError: _onStreamError);
    // Forward stderr to the host stderr so sidecar boot failures
    // and deprecation warnings are visible. Modal's Python SDK
    // prints deprecation warnings here that aren't actionable.
    _stderrSub = _proc!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => stderr.writeln('[modal sidecar] $line'));

    _proc!.exitCode.then((code) {
      // Process exited; complete any outstanding requests with an
      // error so callers don't hang forever.
      if (_shuttingDown) return;
      final err = RuntimeApiException(
        runtimeId: 'modal',
        endpoint: 'sidecar',
        message: 'sidecar exited unexpectedly (code=$code)',
      );
      for (final c in _pending.values) {
        if (!c.isCompleted) c.completeError(err);
      }
      _pending.clear();
    });

    // Wait for the `ready` envelope before returning so callers can
    // start sending exec requests immediately.
    final id = await _readyCompleter.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw const RuntimeApiException(
        runtimeId: 'modal',
        endpoint: 'start',
        message: 'sidecar startup timed out',
      ),
    );
    _sandboxId = id;
  }

  void _onLine(String line) {
    if (line.isEmpty) return;
    final Map<String, dynamic> obj;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) return;
      obj = decoded;
    } catch (_) {
      return; // ignore non-JSON noise
    }
    // Startup envelope: {"id": null, "ok": true, "ready": true, "sandbox_id": "sb-..."}
    if (obj['ready'] == true && !_readyCompleter.isCompleted) {
      _readyCompleter.complete((obj['sandbox_id'] as String?) ?? '');
      return;
    }
    // Async stream event from a previously-started stream_start.
    final event = obj['event'];
    if (event is String) {
      final sid = obj['stream_id'] as String?;
      if (sid == null) return;
      final cmd = _streams[sid];
      if (cmd == null) return;
      switch (event) {
        case 'stream_data':
          cmd.onData(
            (obj['stream'] ?? 'stdout') as String,
            (obj['data'] ?? '') as String,
          );
        case 'stream_exit':
          final ec = obj['exit_code'];
          cmd.onExit(ec is int ? ec : null);
          _streams.remove(sid);
      }
      return;
    }
    // Response to a previously-sent request.
    final id = obj['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null) return;
    completer.complete(obj);
  }

  void _onStreamError(Object error, StackTrace st) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(error, st);
    }
    _pending.clear();
  }

  Future<Map<String, dynamic>> _send(
    String op,
    Map<String, dynamic> extra, {
    Duration? timeout,
  }) async {
    if (_proc == null) {
      throw const RuntimeApiException(
        runtimeId: 'modal',
        endpoint: 'send',
        message: 'sidecar not started',
      );
    }
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final req = jsonEncode({'id': id, 'op': op, ...extra});
    _proc!.stdin.writeln(req);
    await _proc!.stdin.flush();
    final res = timeout == null
        ? await completer.future
        : await completer.future.timeout(timeout);
    if (res['ok'] != true) {
      throw RuntimeApiException(
        runtimeId: 'modal',
        endpoint: op,
        message: (res['error'] ?? 'unknown') as String,
        traceback: res['traceback'] as String?,
      );
    }
    return res;
  }

  @override
  Future<ModalExecResult> execCapture(
    String command, {
    Duration? timeout,
  }) async {
    final res = await _send('exec', {
      'command': command,
      if (timeout != null) 'timeout': timeout.inSeconds,
    }, timeout: timeout == null ? null : timeout + const Duration(seconds: 30));
    return ModalExecResult(
      exitCode: (res['exit_code'] ?? -1) as int,
      stdout: (res['stdout'] ?? '') as String,
      stderr: (res['stderr'] ?? '') as String,
    );
  }

  @override
  Future<List<int>> readFile(String path) async {
    final res = await _send('read_file', {'path': path});
    final b64 = (res['content_b64'] ?? '') as String;
    return base64Decode(b64);
  }

  @override
  Future<void> writeFile(String path, List<int> bytes) async {
    await _send('write_file', {
      'path': path,
      'content_b64': base64Encode(bytes),
    });
  }

  @override
  Future<bool> exists(String path) async {
    final res = await _send('exists', {'path': path});
    return (res['exists'] ?? false) as bool;
  }

  @override
  Future<bool> isDirectory(String path) async {
    final res = await _send('is_directory', {'path': path});
    return (res['is_directory'] ?? false) as bool;
  }

  @override
  Future<List<ModalFsEntry>> listDir(String path) async {
    final res = await _send('list_dir', {'path': path});
    final entries = (res['entries'] as List?) ?? const [];
    return entries
        .whereType<Map<String, dynamic>>()
        .map(
          (e) => ModalFsEntry(
            name: (e['name'] ?? '') as String,
            isDirectory: (e['is_dir'] ?? false) as bool,
            size: (e['size'] ?? 0) as int,
          ),
        )
        .toList();
  }

  @override
  Future<ModalStat?> stat(String path) async {
    final res = await _send('stat', {'path': path});
    if (res['not_found'] == true) return null;
    final s = (res['stat'] as Map?) ?? const {};
    return ModalStat(
      size: (s['size'] ?? 0) as int,
      isDirectory: (s['is_directory'] ?? false) as bool,
    );
  }

  @override
  Future<ModalRunningCommand> startStream(String command) async {
    final res = await _send('stream_start', {'command': command});
    final sid = (res['stream_id'] ?? '') as String;
    if (sid.isEmpty) {
      throw const RuntimeApiException(
        runtimeId: 'modal',
        endpoint: 'stream_start',
        message: 'sidecar returned empty stream_id',
      );
    }
    late final ModalRunningCommand cmd;
    cmd = ModalRunningCommand(
      streamId: sid,
      killer: () => _killStream(sid),
      forceShutdown: shutdown,
    );
    _streams[sid] = cmd;
    return cmd;
  }

  Future<void> _killStream(String streamId) async {
    try {
      await _send('stream_kill', {'stream_id': streamId});
    } catch (_) {
      // Sidecar may have torn down already; the stream_exit event
      // (if it ever arrives) will close the handle. If not, glue's
      // shutdown will.
    }
  }

  @override
  Future<void> shutdown() async {
    if (_proc == null) return;
    _shuttingDown = true;
    try {
      // Best-effort: send shutdown and wait briefly. If the sidecar
      // is already dead the request future may complete with an
      // error — swallow it.
      try {
        await _send('shutdown', {}).timeout(const Duration(seconds: 10));
      } catch (_) {
        /* fallthrough to forced cleanup */
      }
    } finally {
      try {
        _proc!.stdin.close();
      } catch (_) {}
      await _stdoutSub?.cancel();
      await _stderrSub?.cancel();
      // Give the sandbox.terminate() in the sidecar's finally block
      // a moment to land, then SIGTERM if still alive.
      await _proc!.exitCode.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _proc!.kill();
          return -1;
        },
      );
      _proc = null;
      // Any still-open streaming handles need to know the sidecar is
      // gone — synthesize a stream_exit so their exitCode future
      // resolves instead of hanging.
      for (final cmd in _streams.values) {
        cmd.onExit(-1);
      }
      _streams.clear();
      try {
        await _scriptFile?.parent.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Locates a python interpreter that has the `modal` package
  /// installed. Order: `config.pythonPath` → `MODAL_PYTHON` env →
  /// shebang of the `modal` CLI binary → `python3` from PATH.
  Future<String?> _resolvePython() async {
    if (config.pythonPath != null && config.pythonPath!.isNotEmpty) {
      return config.pythonPath;
    }
    final fromEnv = Platform.environment['MODAL_PYTHON'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    // Follow the `modal` binary's shebang — `uv tool install modal`
    // and `pipx install modal` both produce a launcher script whose
    // first line points at the venv python. `LineSplitter` ensures
    // we read just the shebang line (not the first stdout chunk,
    // which is what `.openRead().first` returns).
    try {
      final which = await Process.run('which', [config.modalCliPath]);
      if (which.exitCode == 0) {
        final modalPath = (which.stdout as String).trim();
        if (modalPath.isNotEmpty) {
          final firstLine = await File(modalPath)
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first;
          if (firstLine.startsWith('#!')) {
            final python = firstLine.substring(2).trim().split(' ').first;
            if (await File(python).exists()) return python;
          }
        }
      }
    } catch (_) {
      /* fall through */
    }
    // Last resort: hope a system python has the package.
    return 'python3';
  }
}
