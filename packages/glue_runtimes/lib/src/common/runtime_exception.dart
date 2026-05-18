/// Single exception type thrown by every runtime adapter when the
/// underlying transport (REST API, `sprite` CLI, Modal sidecar)
/// fails or behaves unexpectedly.
///
/// One typed exception per runtime would require callers handling
/// errors uniformly to catch three types — instead, adapters
/// distinguish themselves via [runtimeId] and supply transport-
/// specific context through [statusCode] (HTTP status / process
/// exit code / 0 for protocol violations), [body] (response body or
/// process output), and [traceback] (Python traceback when the
/// modal sidecar surfaces one).
class RuntimeApiException implements Exception {
  /// Adapter id: `'daytona'`, `'sprites'`, `'modal'`, … Distinguishes
  /// runtimes when consumers handle errors uniformly.
  final String runtimeId;

  /// Short label for the failing endpoint / operation
  /// (e.g. `'create_sandbox'`, `'exec'`, `'read_file'`,
  /// `'stream_kill'`).
  final String endpoint;

  /// Human-readable description.
  final String message;

  /// HTTP status code (Daytona REST), CLI exit code (Sprites
  /// subprocess), or `0` when the failure is at a layer with no
  /// such status (e.g. protocol decode failures, Modal sidecar
  /// errors).
  final int statusCode;

  /// Raw response body or process output when available — useful
  /// for diagnostics.
  final String? body;

  /// Python traceback when the Modal sidecar surfaces one over
  /// JSON-RPC. Always null for HTTP/subprocess transports.
  final String? traceback;

  const RuntimeApiException({
    required this.runtimeId,
    required this.endpoint,
    required this.message,
    this.statusCode = 0,
    this.body,
    this.traceback,
  });

  @override
  String toString() {
    final code = statusCode == 0 ? '' : ', status=$statusCode';
    final bodyPart = body == null ? '' : ' — $body';
    final tbPart = traceback == null ? '' : '\n$traceback';
    return 'RuntimeApiException($runtimeId/$endpoint$code): $message$bodyPart$tbPart';
  }
}
