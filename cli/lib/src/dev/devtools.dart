import 'dart:convert';
import 'dart:developer' as developer;

/// Centralized developer instrumentation for Glue.
///
/// All `dart:developer` usage goes through this module. Business logic
/// files call these lightweight methods -- no `dart:developer` imports
/// scattered across the codebase.
///
/// Everything here is a no-op in AOT-compiled binaries.
class GlueDev {
  GlueDev._();

  // -- UserTags for CPU profiler filtering --

  static final tagRender = developer.UserTag('Render');
  static final tagLlmStream = developer.UserTag('LlmStream');
  static final tagToolExec = developer.UserTag('ToolExec');
  static final tagAgentLoop = developer.UserTag('AgentLoop');

  // -- Structured logging --

  /// Emit a structured log event viewable in DevTools Logging view.
  ///
  /// [category] maps to the `name` field in DevTools (filterable).
  /// Categories: `llm.request`, `llm.stream`, `tool.exec`, `tool.bash`,
  /// `agent.loop`, `agent.subagent`, `render.frame`, `render.slow`,
  /// `shell.job`, `session.io`.
  ///
  /// [level] defaults to 0 (FINEST). Use 900 for WARNING, 1000 for SEVERE.
  static void log(
    String category,
    String message, {
    int level = 0,
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: category,
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
  }

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

  // -- Event posting (for custom DevTools extension) --

  /// Post a tool execution event.
  static void postToolExec({
    required String tool,
    required int durationMs,
    required int resultSizeBytes,
    String? argsSummary,
  }) {
    developer.postEvent('glue.toolExec', {
      'tool': tool,
      'durationMs': durationMs,
      'resultSizeBytes': resultSizeBytes,
      if (argsSummary != null) 'argsSummary': argsSummary,
    });
  }

  /// Post an agent step event (one ReAct iteration).
  static void postAgentStep({
    required int iteration,
    required List<String> toolsChosen,
    required int tokenDelta,
  }) {
    developer.postEvent('glue.agentStep', {
      'iteration': iteration,
      'toolsChosen': toolsChosen,
      'tokenDelta': tokenDelta,
    });
  }

  /// Post an LLM request completion event.
  static void postLlmRequest({
    required String provider,
    required String model,
    required int ttfbMs,
    required int streamDurationMs,
    required int inputTokens,
    required int outputTokens,
  }) {
    developer.postEvent('glue.llmRequest', {
      'provider': provider,
      'model': model,
      'ttfbMs': ttfbMs,
      'streamDurationMs': streamDurationMs,
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
    });
  }

  /// Post render metrics event.
  static void postRenderMetrics({
    required double frameMs,
    required int blockCount,
    required int lineCount,
    required bool overBudget,
  }) {
    developer.postEvent('glue.renderMetrics', {
      'frameMs': frameMs,
      'blockCount': blockCount,
      'lineCount': lineCount,
      'overBudget': overBudget,
    });
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
