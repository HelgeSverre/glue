import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:glue_runtimes/src/common/runtime_exception.dart';
import 'package:glue_runtimes/src/daytona/config.dart';

/// Result of `createSandbox` — the bare minimum the rest of the
/// adapter needs to address the running sandbox.
///
/// [toolboxBaseUrl] is returned by Daytona per sandbox (e.g.
/// `https://proxy.app-eu.daytona.io/toolbox`) and is what makes
/// region routing transparent.
class DaytonaSandbox {
  final String id;
  final String? state;
  final String toolboxBaseUrl;

  DaytonaSandbox({required this.id, required this.toolboxBaseUrl, this.state});
}

/// Result of a synchronous `execCapture` call.
///
/// Daytona's `/process/execute` endpoint returns a single combined
/// `result` string (stdout + stderr interleaved) plus an `exitCode`.
/// There is no separate stderr field at this layer.
class DaytonaExecResult {
  final int exitCode;
  final String result;

  DaytonaExecResult({required this.exitCode, required this.result});
}

/// Identifier returned by the session-exec API. Used to fetch logs,
/// poll for completion, and cancel the running command later.
class DaytonaSessionCommand {
  final String sessionId;
  final String commandId;

  DaytonaSessionCommand({required this.sessionId, required this.commandId});
}

/// Filesystem entry returned by `listDir`.
class DaytonaFsEntry {
  final String name;
  final bool isDirectory;
  final int size;

  DaytonaFsEntry({
    required this.name,
    required this.isDirectory,
    this.size = 0,
  });
}

/// REST client for Daytona's sandbox + toolbox APIs.
///
/// Endpoint shapes match the live API as of May 2026 — see
/// https://www.daytona.io/docs/en/process-code-execution/ and
/// https://www.daytona.io/docs/en/file-system-operations/.
///
/// **Naming/test-seam pattern:** Daytona speaks plain HTTP, so the
/// concrete `DaytonaClient` accepts an `http.Client` for tests to
/// inject `MockClient`. No `*Base` abstract class is needed — the
/// transport is already a swappable type. Compare with
/// [SpritesCliBase] / [ModalSidecarBase], which abstract over
/// subprocess transports that have no equivalent mockable contract.
class DaytonaClient {
  final DaytonaConfig config;
  final http.Client _http;

  DaytonaClient({required this.config, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  // ─── Sandbox lifecycle (control plane) ─────────────────────────────────

  /// Creates a fresh sandbox.
  ///
  /// Endpoint: `POST <apiBaseUrl>/sandbox`
  /// Body: `{"snapshot": "<name>"}` when [DaytonaConfig.snapshot] is
  /// set, otherwise `{}` — letting Daytona apply the org's default
  /// snapshot. Sending `cpu`/`memory`/`disk` alongside a snapshot
  /// triggers a 400 ("Cannot specify Sandbox resources when using a
  /// snapshot"), so we don't.
  ///
  /// The response carries `toolboxProxyUrl` — the per-sandbox toolbox
  /// host (region-specific), which we use for every subsequent
  /// toolbox call unless [DaytonaConfig.toolboxBaseUrlOverride] is set.
  Future<DaytonaSandbox> createSandbox() async {
    final body = config.snapshot != null && config.snapshot!.isNotEmpty
        ? {'snapshot': config.snapshot}
        : <String, dynamic>{};
    final res = await _postApi(
      endpoint: 'create_sandbox',
      path: '/sandbox',
      body: body,
    );
    final json = _decodeJson(res, 'create_sandbox');
    final id = json['id'] ?? json['sandboxId'] ?? json['sandbox_id'];
    if (id is! String || id.isEmpty) {
      throw RuntimeApiException(
        runtimeId: 'daytona',
        statusCode: res.statusCode,
        endpoint: 'create_sandbox',
        message: 'response missing sandbox id',
        body: res.body,
      );
    }
    // The sandbox always carries the server-reported toolbox URL.
    // [_toolboxUri] applies any [DaytonaConfig.toolboxBaseUrlOverride]
    // at request time, so the override doesn't lose this info.
    final serverToolboxUrl = json['toolboxProxyUrl'] as String?;
    if (serverToolboxUrl == null || serverToolboxUrl.isEmpty) {
      throw RuntimeApiException(
        runtimeId: 'daytona',
        statusCode: res.statusCode,
        endpoint: 'create_sandbox',
        message: 'response missing toolboxProxyUrl',
        body: res.body,
      );
    }
    return DaytonaSandbox(
      id: id,
      toolboxBaseUrl: serverToolboxUrl,
      state: json['state']?.toString(),
    );
  }

  /// Stops a running sandbox and releases its resources.
  ///
  /// Endpoint: `DELETE <apiBaseUrl>/sandbox/{id}`
  Future<void> stopSandbox(String sandboxId) async {
    await _delete(
      endpoint: 'stop_sandbox',
      uri: Uri.parse('${config.apiBaseUrl}/sandbox/$sandboxId'),
    );
  }

  // ─── Execution (toolbox) ───────────────────────────────────────────────

  /// Runs [command] synchronously and waits for completion.
  ///
  /// Endpoint: `POST <toolboxBaseUrl>/{id}/process/execute`
  /// Body: `{"command": <cmd>, "cwd"?: <cwd>, "timeout"?: <ms>}`
  /// Response: `{"result": "...", "exitCode": N}`
  Future<DaytonaExecResult> execCapture(
    DaytonaSandbox sandbox,
    String command, {
    Duration? timeout,
    String? cwd,
  }) async {
    final body = <String, dynamic>{'command': command};
    if (cwd != null) body['cwd'] = cwd;
    if (timeout != null) body['timeout'] = timeout.inMilliseconds;
    final res = await _postToolbox(
      endpoint: 'execute',
      sandbox: sandbox,
      path: '/process/execute',
      body: body,
      timeout: timeout ?? config.execTimeout,
    );
    final json = _decodeJson(res, 'execute');
    final exitCode = (json['exitCode'] ?? json['exit_code'] ?? -1) as int;
    final result = (json['result'] ?? json['output'] ?? '').toString();
    return DaytonaExecResult(exitCode: exitCode, result: result);
  }

  /// Creates a long-lived process session inside the sandbox.
  ///
  /// Endpoint: `POST <toolboxBaseUrl>/{id}/process/session`
  /// Body: `{"sessionId": "<sid>"}`
  Future<void> createSession(DaytonaSandbox sandbox, String sessionId) async {
    await _postToolbox(
      endpoint: 'create_session',
      sandbox: sandbox,
      path: '/process/session',
      body: {'sessionId': sessionId},
    );
  }

  /// Starts a command inside an existing session. With [runAsync] true
  /// the call returns immediately with a [DaytonaSessionCommand]; the
  /// caller polls [getSessionCommandLogs] + [getSessionCommandStatus]
  /// for output and completion.
  ///
  /// Endpoint: `POST <toolboxBaseUrl>/{id}/process/session/{sid}/exec`
  /// Body: `{"command": <cmd>, "runAsync": true}`
  /// Response: 202 + `{"cmdId": "<id>", …}` (other fields are
  /// null until the command finishes).
  Future<DaytonaSessionCommand> executeSessionCommand(
    DaytonaSandbox sandbox,
    String sessionId,
    String command, {
    bool runAsync = true,
  }) async {
    final res = await _postToolbox(
      endpoint: 'session_exec',
      sandbox: sandbox,
      path: '/process/session/$sessionId/exec',
      body: {'command': command, 'runAsync': runAsync},
    );
    final json = _decodeJson(res, 'session_exec');
    final cmdId = (json['cmdId'] ?? json['commandId'] ?? json['id'])
        ?.toString();
    if (cmdId == null || cmdId.isEmpty) {
      throw RuntimeApiException(
        runtimeId: 'daytona',
        statusCode: res.statusCode,
        endpoint: 'session_exec',
        message: 'response missing cmdId',
        body: res.body,
      );
    }
    return DaytonaSessionCommand(sessionId: sessionId, commandId: cmdId);
  }

  /// Fetches the accumulated logs for a session command. The
  /// response is plain-text (stdout+stderr interleaved); there is no
  /// completion signal in this body — call
  /// [getSessionCommandStatus] for that.
  ///
  /// Endpoint: `GET <toolboxBaseUrl>/{id}/process/session/{sid}/command/{cmdId}/logs`
  Future<String> getSessionCommandLogs(
    DaytonaSandbox sandbox,
    String sessionId,
    String commandId,
  ) async {
    final uri = _toolboxUri(
      sandbox,
      '/process/session/$sessionId/command/$commandId/logs',
    );
    final res = await _http.get(uri, headers: _headers());
    _ensureOk(res, 'session_logs');
    return res.body;
  }

  /// Returns the current status of a session command, including the
  /// `exitCode` once finished (null while still running).
  ///
  /// Endpoint: `GET <toolboxBaseUrl>/{id}/process/session/{sid}/command/{cmdId}`
  Future<DaytonaSessionCommandStatus> getSessionCommandStatus(
    DaytonaSandbox sandbox,
    String sessionId,
    String commandId,
  ) async {
    final uri = _toolboxUri(
      sandbox,
      '/process/session/$sessionId/command/$commandId',
    );
    final res = await _http.get(uri, headers: _headers());
    _ensureOk(res, 'session_command_status');
    final json = _decodeJson(res, 'session_command_status');
    final exitCode = json['exitCode'];
    return DaytonaSessionCommandStatus(
      command: (json['command'] ?? '') as String,
      exitCode: exitCode is int ? exitCode : null,
    );
  }

  /// Cancels a running session command by deleting its parent session.
  ///
  /// Endpoint: `DELETE <toolboxBaseUrl>/{id}/process/session/{sid}`
  Future<void> deleteSession(DaytonaSandbox sandbox, String sessionId) async {
    await _delete(
      endpoint: 'delete_session',
      uri: _toolboxUri(sandbox, '/process/session/$sessionId'),
    );
  }

  // ─── Filesystem (toolbox) ──────────────────────────────────────────────

  /// Reads a file's raw bytes.
  ///
  /// Endpoint: `GET <toolboxBaseUrl>/{id}/files/download?path=<p>`
  Future<List<int>> readFile(DaytonaSandbox sandbox, String path) async {
    final uri = _toolboxUri(sandbox, '/files/download', {'path': path});
    final res = await _http.get(uri, headers: _headers());
    _ensureOk(res, 'download_file');
    return res.bodyBytes;
  }

  /// Writes [bytes] to [path] via multipart upload.
  ///
  /// Endpoint: `POST <toolboxBaseUrl>/{id}/files/upload?path=<p>`
  /// Body: multipart form with `file=<bytes>`
  Future<void> writeFile(
    DaytonaSandbox sandbox,
    String path,
    List<int> bytes,
  ) async {
    final uri = _toolboxUri(sandbox, '/files/upload', {'path': path});
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll(_headers());
    req.files.add(
      http.MultipartFile.fromBytes(
        'file',
        Uint8List.fromList(bytes),
        filename: _basename(path),
      ),
    );
    final streamed = await _http.send(req);
    final res = await http.Response.fromStream(streamed);
    _ensureOk(res, 'upload_file');
  }

  /// Lists the contents of a directory.
  ///
  /// Endpoint: `GET <toolboxBaseUrl>/{id}/files/?path=<p>`
  /// (trailing slash — the no-slash form 301-redirects).
  /// Response: JSON array of `{name, isDir, size, …}`.
  Future<List<DaytonaFsEntry>> listDir(
    DaytonaSandbox sandbox,
    String path,
  ) async {
    final uri = _toolboxUri(sandbox, '/files/', {'path': path});
    final res = await _http.get(uri, headers: _headers());
    _ensureOk(res, 'list_files');
    final decoded = jsonDecode(res.body);
    final list = decoded is List
        ? decoded
        : (decoded is Map ? (decoded['files'] ?? decoded['entries'] ?? []) : [])
              as List;
    return list.whereType<Map<String, dynamic>>().map(_parseFsEntry).toList();
  }

  /// Returns metadata for a single filesystem entry, or `null` when
  /// the entry doesn't exist.
  ///
  /// Endpoint: `GET <toolboxBaseUrl>/{id}/files/info?path=<p>`
  Future<DaytonaStat?> stat(DaytonaSandbox sandbox, String path) async {
    final uri = _toolboxUri(sandbox, '/files/info', {'path': path});
    final res = await _http.get(uri, headers: _headers());
    if (res.statusCode == 404) return null;
    _ensureOk(res, 'file_info');
    final json = _decodeJson(res, 'file_info');
    return DaytonaStat(
      size: (json['size'] ?? 0) as int,
      isDirectory:
          (json['isDir'] ??
                  json['is_directory'] ??
                  json['isDirectory'] ??
                  false)
              as bool,
    );
  }

  /// Closes the underlying HTTP client.
  void close() => _http.close();

  // ─── Internal HTTP plumbing ────────────────────────────────────────────

  Map<String, String> _headers({bool json = false}) {
    final h = <String, String>{'Authorization': 'Bearer ${config.apiKey}'};
    if (json) h['Content-Type'] = 'application/json';
    return h;
  }

  Uri _toolboxUri(
    DaytonaSandbox sandbox,
    String path, [
    Map<String, String>? query,
  ]) {
    final base = config.toolboxBaseUrlOverride ?? sandbox.toolboxBaseUrl;
    return Uri.parse(
      '$base/${sandbox.id}$path',
    ).replace(queryParameters: query);
  }

  Future<http.Response> _postApi({
    required String endpoint,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse('${config.apiBaseUrl}$path');
    final res = await _http.post(
      uri,
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    _ensureOk(res, endpoint);
    return res;
  }

  Future<http.Response> _postToolbox({
    required String endpoint,
    required DaytonaSandbox sandbox,
    required String path,
    required Map<String, dynamic> body,
    Duration? timeout,
  }) async {
    final uri = _toolboxUri(sandbox, path);
    Future<http.Response> req() =>
        _http.post(uri, headers: _headers(json: true), body: jsonEncode(body));
    final res = timeout == null ? await req() : await req().timeout(timeout);
    _ensureOk(res, endpoint);
    return res;
  }

  Future<http.Response> _delete({
    required String endpoint,
    required Uri uri,
  }) async {
    final res = await _http.delete(uri, headers: _headers());
    if (res.statusCode == 404) return res; // idempotent
    _ensureOk(res, endpoint);
    return res;
  }

  void _ensureOk(http.Response res, String endpoint) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw RuntimeApiException(
      runtimeId: 'daytona',
      statusCode: res.statusCode,
      endpoint: endpoint,
      message: 'HTTP ${res.statusCode}',
      body: res.body,
    );
  }

  Map<String, dynamic> _decodeJson(http.Response res, String endpoint) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw RuntimeApiException(
        runtimeId: 'daytona',
        statusCode: res.statusCode,
        endpoint: endpoint,
        message: 'expected JSON object, got ${decoded.runtimeType}',
        body: res.body,
      );
    } on FormatException catch (e) {
      throw RuntimeApiException(
        runtimeId: 'daytona',
        statusCode: res.statusCode,
        endpoint: endpoint,
        message: 'malformed JSON: $e',
        body: res.body,
      );
    }
  }

  DaytonaFsEntry _parseFsEntry(Map<String, dynamic> e) => DaytonaFsEntry(
    name: (e['name'] ?? '') as String,
    isDirectory:
        (e['isDir'] ?? e['is_directory'] ?? e['isDirectory'] ?? false) as bool,
    size: (e['size'] ?? 0) as int,
  );

  static String _basename(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}

class DaytonaStat {
  final int size;
  final bool isDirectory;

  DaytonaStat({required this.size, required this.isDirectory});
}

/// Status of a session command — the completion signal lives here,
/// not in the logs response.
class DaytonaSessionCommandStatus {
  final String command;

  /// `null` while the command is still running.
  final int? exitCode;

  DaytonaSessionCommandStatus({required this.command, required this.exitCode});
}
