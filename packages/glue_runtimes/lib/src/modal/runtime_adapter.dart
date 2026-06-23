import 'dart:io';

import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue_runtimes/src/modal/config.dart';
import 'package:glue_runtimes/src/modal/runtime.dart';

/// Builds a [ModalConfig] from a `runtime_options` map and the
/// process environment. The python interpreter resolution lives in
/// the sidecar; here we just thread the configurable knobs.
ModalConfig modalConfigFromOptions(
  Map<String, Object?> options, {
  Map<String, String>? env,
}) {
  final e = env ?? Platform.environment;
  return ModalConfig(
    pythonPath: (options['python_path'] as String?) ?? e['MODAL_PYTHON'],
    modalCliPath:
        (options['modal_cli'] as String?) ?? e['MODAL_CLI'] ?? 'modal',
    appName: (options['app_name'] as String?) ?? e['MODAL_APP'] ?? 'glue',
    image: (options['image'] as String?) ?? e['MODAL_IMAGE'],
    sandboxTimeoutSeconds:
        int.tryParse(options['sandbox_timeout_seconds']?.toString() ?? '') ??
        int.tryParse(e['MODAL_SANDBOX_TIMEOUT'] ?? '') ??
        1800,
    deleteOnClose: options['delete_on_close'] is bool
        ? options['delete_on_close'] as bool
        : (e['MODAL_DELETE_ON_CLOSE']?.toLowerCase() != 'false'),
  );
}

/// Registers the Modal adapter with [RuntimeFactory]. Call once at
/// startup before [ServiceLocator.create].
void registerModalRuntime() {
  RuntimeFactory.register('modal', ({
    required cwd,
    required options,
    eventSink,
  }) async {
    final config = modalConfigFromOptions(options);
    return ModalRuntime.start(
      config: config,
      hostCwd: cwd,
      eventSink: eventSink,
    );
  });
  RuntimeFactory.registerDiagnostics('modal', modalDiagnostics);
}

/// Modal readiness probe. Modal exposes sandboxes only via its Python
/// SDK; glue ships a Python sidecar that drives it, so the readiness
/// check is "the configured python interpreter can import modal", plus
/// an auth probe (`modal profile current`) and the resolved app name.
Iterable<RuntimeDiagnostic> modalDiagnostics(RuntimeDiagnosticContext ctx) {
  final out = <RuntimeDiagnostic>[];

  final cliPath = ctx.optionOrEnv('modal_cli', 'MODAL_CLI') ?? 'modal';
  String? python;
  String? failureReason;
  try {
    final which = Process.runSync('which', [cliPath]);
    if (which.exitCode != 0) {
      failureReason =
          '`$cliPath` not found on PATH — '
          '`uv tool install modal` (or `pipx install modal`)';
    } else {
      final modalPath = (which.stdout as String).trim();
      // Follow the shebang to find the venv python.
      final firstLine = File(modalPath).readAsStringSync().split('\n').first;
      if (firstLine.startsWith('#!')) {
        python = firstLine.substring(2).trim().split(' ').first;
      }
      python ??= ctx.optionOrEnv('python_path', 'MODAL_PYTHON') ?? 'python3';
      final import = Process.runSync(python, [
        '-c',
        'import modal; print(modal.__version__)',
      ]);
      if (import.exitCode != 0) {
        failureReason =
            'python at $python cannot import modal — install the package '
            'into that interpreter, or set MODAL_PYTHON / modal.python_path';
      }
    }
  } on ProcessException {
    failureReason = 'failed to probe modal — check $cliPath is executable';
  }
  out.add(
    failureReason == null
        ? RuntimeDiagnostic.ok('modal CLI + python ($python) ready')
        : RuntimeDiagnostic.error('modal: $failureReason'),
  );

  // Auth check: `modal profile current` exits 0 when logged in.
  try {
    final auth = Process.runSync(cliPath, ['profile', 'current']);
    out.add(
      auth.exitCode == 0
          ? RuntimeDiagnostic.ok(
              'modal profile: ${(auth.stdout as String).trim()}',
            )
          : const RuntimeDiagnostic.error(
              'modal not authenticated — run `modal token set`',
            ),
    );
  } on ProcessException {
    /* already covered by the import probe above */
  }

  final appName = ctx.optionOrEnv('app_name', 'MODAL_APP') ?? 'glue';
  out.add(RuntimeDiagnostic.info('modal app: $appName'));

  return out;
}
