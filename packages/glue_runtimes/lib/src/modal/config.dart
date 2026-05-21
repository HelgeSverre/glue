/// Configuration for the Modal runtime adapter.
///
/// Modal exposes its sandbox primitive only through the Python SDK
/// (`modal.Sandbox.create(...)`) — there's no `modal sandbox` CLI
/// subcommand and no public REST endpoint for sandbox lifecycle.
/// Glue's modal adapter wraps a small Python sidecar (shipped
/// embedded in the binary) that holds a long-lived
/// `Sandbox.create("sleep", "infinity")` keepalive and services
/// glue's exec / file ops over JSON-RPC on stdin/stdout.
///
/// Trade-off: requires the `modal` Python package available to the
/// configured python interpreter and the user authenticated
/// (`modal token set` once). `glue doctor` surfaces both.
class ModalConfig {
  /// Path to a Python interpreter that has the `modal` package
  /// importable. When `null`, glue tries to resolve from
  /// `MODAL_PYTHON` env or, failing that, by following the `modal`
  /// CLI's shebang. Override when modal is installed in a venv glue
  /// can't auto-detect.
  final String? pythonPath;

  /// Path to the `modal` CLI binary — used only for `glue doctor`'s
  /// auth check. Defaults to `modal` on `$PATH`.
  final String modalCliPath;

  /// Name of the modal App that hosts the glue sandbox. Reusing the
  /// same app across sessions is cheap; sandboxes inside are still
  /// disposable per-session.
  final String appName;

  /// Optional registry image tag (e.g. `python:3.12-slim`). When
  /// `null`, modal uses the default Debian-based image.
  final String? image;

  /// Max sandbox lifetime in seconds. The sandbox auto-terminates
  /// after this many seconds of wall-clock time, even if glue
  /// doesn't shut it down cleanly — caps runaway billing.
  final int sandboxTimeoutSeconds;

  /// When `true` (default), glue terminates the sandbox on session
  /// close. Set to `false` to leave it running until [sandboxTimeoutSeconds]
  /// (useful for debugging — `modal container list` will show it).
  final bool deleteOnClose;

  const ModalConfig({
    this.pythonPath,
    this.modalCliPath = 'modal',
    this.appName = 'glue',
    this.image,
    this.sandboxTimeoutSeconds = 1800,
    this.deleteOnClose = true,
  });

  ModalConfig copyWith({
    String? pythonPath,
    String? modalCliPath,
    String? appName,
    String? image,
    int? sandboxTimeoutSeconds,
    bool? deleteOnClose,
  }) => ModalConfig(
    pythonPath: pythonPath ?? this.pythonPath,
    modalCliPath: modalCliPath ?? this.modalCliPath,
    appName: appName ?? this.appName,
    image: image ?? this.image,
    sandboxTimeoutSeconds: sandboxTimeoutSeconds ?? this.sandboxTimeoutSeconds,
    deleteOnClose: deleteOnClose ?? this.deleteOnClose,
  );
}
