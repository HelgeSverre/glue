/// Glue runtime adapter for Modal (https://modal.com) sandboxes.
///
/// Modal exposes its sandbox primitive only through the Python SDK,
/// so glue ships a small Python sidecar (embedded in the binary)
/// that holds a long-lived `Sandbox.create("sleep", "infinity")`
/// keepalive and services exec / file ops over JSON-RPC on
/// stdin/stdout. Register from your startup code:
///
/// ```dart
/// import 'package:glue_runtimes/modal.dart';
///
/// void main() async {
///   registerModalRuntime();
///   await runGlue();
/// }
/// ```
///
/// Internal types (`ModalSidecar`, `ModalExecutor`, `ModalWorkspace`,
/// `ModalFsTransport`, `ModalRunningCommand`, `ModalBootstrap`,
/// `modalSidecarSource`) are implementation details — import from
/// `src/modal/...` if you need them in tests.
library;

export 'package:glue_runtimes/src/common/runtime_exception.dart';
export 'package:glue_runtimes/src/modal/config.dart';
export 'package:glue_runtimes/src/modal/runtime_adapter.dart';
export 'package:glue_strategies/glue_strategies.dart' show RuntimeSession;
