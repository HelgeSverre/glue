/// Glue runtime adapter for Daytona cloud sandboxes.
///
/// Implements the strategy contracts from `glue_strategies`
/// ([CommandExecutor] + [Workspace]) by routing through the Daytona
/// REST API (control plane + per-sandbox toolbox). Register from
/// your startup code:
///
/// ```dart
/// import 'package:glue_runtimes/daytona.dart';
///
/// void main() async {
///   registerDaytonaRuntime();
///   await runGlue();
/// }
/// ```
///
/// Internal types (`DaytonaClient`, `DaytonaSandbox`, `DaytonaExecutor`,
/// `DaytonaWorkspace`, `DaytonaFsTransport`, `DaytonaRunningCommand`,
/// `DaytonaBootstrap`) are implementation details — import directly
/// from `src/daytona/...` if you need them in tests, but don't rely
/// on their shape across glue versions.
library;

// Public surface — keep small.
export 'package:glue_runtimes/src/common/runtime_exception.dart';
export 'package:glue_runtimes/src/daytona/config.dart';
export 'package:glue_runtimes/src/daytona/runtime_adapter.dart';
// RuntimeSession is the umbrella type adapter consumers ultimately
// receive from RuntimeFactory — re-exported here so callers don't
// have to add a glue_strategies import for the type check.
export 'package:glue_strategies/glue_strategies.dart' show RuntimeSession;
