import 'dart:developer' as developer;

import 'package:glue/src/observability/observability.dart';

/// An [ObservabilitySink] that bridges spans to `dart:developer` for DevTools.
///
/// Maps completed spans to:
/// - `developer.log()` for the DevTools Logging view
/// - `developer.postEvent()` for a custom DevTools extension
///
/// All `dart:developer` APIs are no-ops in AOT binaries, so this sink
/// adds zero overhead in production.
class DevToolsSink extends ObservabilitySink {
  @override
  void onSpan(ObservabilitySpan span) {
    _emitLog(span);
    _emitPostEvent(span);
  }

  void _emitLog(ObservabilitySpan span) {
    final category = switch (span.kind) {
      'llm' => 'llm.stream',
      'tool' => 'tool.exec',
      'http' => 'http.request',
      _ => 'glue.${span.name}',
    };
    final durationMs = span.duration.inMilliseconds;
    final message = switch (span.kind) {
      'llm' =>
        '${span.attributes['gen_ai.request.model'] ?? 'unknown'} completed in ${durationMs}ms',
      'tool' =>
        '${span.attributes['tool.name'] ?? span.name} completed in ${durationMs}ms',
      'http' =>
        '${span.attributes['http.method'] ?? ''} ${span.attributes['http.url'] ?? ''} => ${span.attributes['http.status_code'] ?? '?'}',
      _ => '${span.name} completed in ${durationMs}ms',
    };
    final level = span.attributes.containsKey('error') ? 1000 : 0;
    developer.log(message, name: category, level: level);
  }

  /// Posts structured events for consumption by a custom DevTools extension.
  ///
  /// Attribute keys read from spans (set by [ObservedLlmClient] and
  /// [ObservedTool]):
  /// - `gen_ai.system`, `gen_ai.request.model` — provider/model
  /// - `llm.ttfb_ms` — time to first TextDelta (omitted if no text streamed)
  /// - `input_tokens`, `output_tokens` — token counts (short-form keys)
  /// - `tool.name`, `tool.result_length` — tool metadata
  void _emitPostEvent(ObservabilitySpan span) {
    switch (span.kind) {
      case 'llm':
        final event = <String, dynamic>{
          'provider': span.attributes['gen_ai.system'] ?? '',
          'model': span.attributes['gen_ai.request.model'] ?? '',
          'streamDurationMs': span.duration.inMilliseconds,
          'inputTokens': span.attributes['input_tokens'] ?? 0,
          'outputTokens': span.attributes['output_tokens'] ?? 0,
        };
        final ttfb = span.attributes['llm.ttfb_ms'];
        if (ttfb != null) event['ttfbMs'] = ttfb;
        developer.postEvent('glue.llmRequest', event);
      case 'tool':
        developer.postEvent('glue.toolExec', {
          'tool': span.attributes['tool.name'] ?? span.name,
          'durationMs': span.duration.inMilliseconds,
          'resultSizeBytes': span.attributes['tool.result_length'] ?? 0,
        });
      default:
        break;
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
