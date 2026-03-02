import 'dart:convert';
import 'dart:developer' as developer;

/// DevTools-specific utilities for Glue.
///
/// Contains features unique to `dart:developer` that have no equivalent in
/// the observability span system: CPU profiler tags, Timeline helpers,
/// service extensions, and the DevTools URL helper.
///
/// Tracing, logging, and event posting are handled by [DevToolsSink] via
/// the observability infrastructure — not by this class.
///
/// Everything here is a no-op in AOT-compiled binaries.
class GlueDev {
  GlueDev._();

  // -- UserTags for CPU profiler filtering --

  static final tagRender = developer.UserTag('Render');
  static final tagLlmStream = developer.UserTag('LlmStream');
  static final tagToolExec = developer.UserTag('ToolExec');
  static final tagAgentLoop = developer.UserTag('AgentLoop');

  // -- Timeline helpers --

  /// Wrap a synchronous operation in a Timeline span.
  static T timeSync<T>(
    String name,
    T Function() fn, {
    Map<String, dynamic>? args,
  }) {
    return developer.Timeline.timeSync(name, fn, arguments: args);
  }

  /// Start an async timeline task. Caller must call `.finish()` on the
  /// returned task when the operation completes.
  static developer.TimelineTask startAsync(
    String name, {
    Map<String, dynamic>? args,
  }) {
    final task = developer.TimelineTask();
    task.start(name, arguments: args);
    return task;
  }

  // -- DevTools URL --

  /// Returns the DevTools URL if the VM service is running, null otherwise.
  static Future<Uri?> getDevToolsUrl() async {
    final info = await developer.Service.getInfo();
    final uri = info.serverUri;
    if (uri == null) return null;
    return uri
        .resolve('devtools/?uri=ws://${uri.host}:${uri.port}${uri.path}ws');
  }

  // -- Service extensions --

  /// Register all Glue service extensions. Call once at startup.
  ///
  /// [stateProvider] is a callback that returns a JSON-serializable map
  /// for a given extension name.
  static void registerExtensions(
    Map<String, dynamic> Function(String) stateProvider,
  ) {
    for (final name in [
      'getAgentState',
      'getConfig',
      'getSessionInfo',
      'getToolHistory',
    ]) {
      try {
        developer.registerExtension('ext.glue.$name', (method, params) async {
          try {
            final data = stateProvider(name);
            return developer.ServiceExtensionResponse.result(jsonEncode(data));
          } catch (e) {
            return developer.ServiceExtensionResponse.error(
              developer.ServiceExtensionResponse.extensionError,
              e.toString(),
            );
          }
        });
      } on StateError {
        // Already registered (e.g., test reuse or hot restart).
      }
    }
  }
}
