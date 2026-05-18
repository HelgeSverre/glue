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
  RuntimeFactory.register(
    'modal',
    ({required cwd, required options, eventSink}) async {
      final config = modalConfigFromOptions(options);
      return ModalRuntime.start(
        config: config,
        hostCwd: cwd,
        eventSink: eventSink,
      );
    },
  );
}
