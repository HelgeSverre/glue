import 'package:glue_runtimes/src/common/bootstrap.dart';
import 'package:glue_runtimes/src/common/runtime_exception.dart';
import 'package:glue_runtimes/src/daytona/client.dart';

export 'package:glue_runtimes/src/common/bootstrap.dart' show BootstrapResult;

/// Daytona-specific glue around the shared [WorkspaceBootstrap]:
/// adapts [DaytonaClient] to the [BootstrapBundleTransport] contract
/// (multipart upload for the bundle path + exec for the clone) and
/// adds the `sudo mkdir`/`chown` prep step that Daytona's default
/// snapshot needs (sandbox runs as user `daytona` but `/` is
/// root-owned, so an un-prep'd clone errors with `Permission denied`).
class DaytonaBootstrap {
  final DaytonaClient client;
  final DaytonaSandbox sandbox;
  final String sessionId;

  DaytonaBootstrap({
    required this.client,
    required this.sandbox,
    required this.sessionId,
  });

  Future<BootstrapResult> bootstrap({
    required String hostCwd,
    required String runtimeCwd,
  }) async {
    final ws = WorkspaceBootstrap(
      exec: _DaytonaBootstrapTransport(client: client, sandbox: sandbox),
      sessionId: sessionId,
      prepCommand:
          'sudo mkdir -p $runtimeCwd && '
          'sudo chown "\$(id -u):\$(id -g)" $runtimeCwd',
    );
    try {
      return await ws.bootstrap(hostCwd: hostCwd, runtimeCwd: runtimeCwd);
    } on BootstrapException catch (e) {
      // Re-raise as a runtime-typed exception so callers don't have
      // to know about BootstrapException specifically.
      throw RuntimeApiException(
        runtimeId: 'daytona',
        statusCode: e.exitCode ?? 0,
        endpoint: 'bootstrap_${e.stage}',
        message: e.message,
        body: e.output,
      );
    }
  }
}

class _DaytonaBootstrapTransport implements BootstrapBundleTransport {
  final DaytonaClient client;
  final DaytonaSandbox sandbox;
  _DaytonaBootstrapTransport({required this.client, required this.sandbox});

  @override
  Future<BootstrapExecResult> run(String shellCommand) async {
    final r = await client.execCapture(sandbox, shellCommand);
    return BootstrapExecResult(exitCode: r.exitCode, output: r.result);
  }

  @override
  Future<void> uploadBytes(String runtimePath, List<int> bytes) =>
      client.writeFile(sandbox, runtimePath, bytes);

  // Daytona's multipart upload handles large files comfortably; the
  // toolbox proxy has been observed to accept >200 MB in a single
  // POST. Pick a conservative cap that still covers any realistic
  // bundle.
  @override
  int get bundleSizeCapBytes => 200 * 1024 * 1024;
}
