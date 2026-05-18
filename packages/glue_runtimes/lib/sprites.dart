/// Glue runtime adapter for Sprites (Fly.io stateful sandboxes).
///
/// Implements the strategy contracts from `glue_strategies`
/// ([CommandExecutor] + [Workspace]) by shelling out to the
/// official `sprite` CLI (the API's wire protocol is in active RC
/// flux and there's no stable `/filesystem` REST endpoint today —
/// see comments in `SpritesConfig`). Register from your startup
/// code:
///
/// ```dart
/// import 'package:glue_runtimes/sprites.dart';
///
/// void main() async {
///   registerSpritesRuntime();
///   await runGlue();
/// }
/// ```
///
/// Internal types (`SpritesCli`, `SpritesExecutor`, `SpritesWorkspace`,
/// `SpritesFsTransport`, `SpritesBootstrap`) are implementation
/// details — import from `src/sprites/...` if you need them in
/// tests.
library;

export 'package:glue_runtimes/src/common/runtime_exception.dart';
export 'package:glue_runtimes/src/sprites/config.dart';
export 'package:glue_runtimes/src/sprites/runtime_adapter.dart';
export 'package:glue_strategies/glue_strategies.dart' show RuntimeSession;
