import 'package:glue/src/boot/http.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/file_sink.dart';
import 'package:glue/src/observability/http_trace_sink.dart';
import 'package:glue/src/observability/logging_http_client.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/otlp_http_trace_sink.dart';
import 'package:glue/src/utils.dart';
import 'package:http/http.dart' as http;

class ObservabilityBundle {
  ObservabilityBundle({
    required this.observability,
    required this.debugController,
    required this.httpClient,
  });

  final Observability observability;
  final DebugController debugController;
  final HttpClientFactory httpClient;
}

ObservabilityBundle wireObservability({
  required GlueConfig config,
  required Environment environment,
  required bool debug,
}) {
  final debugController = DebugController(
    enabled: debug || config.observability.debug,
  );
  final observability = Observability(debugController: debugController);

  observability.addSink(FileSink(logsDir: environment.logsDir));
  if (config.observability.otel.isConfigured) {
    observability.addSink(
      OtlpHttpTraceSink(config: config.observability.otel),
    );
    observability.startAutoFlush(5.seconds);
  }
  if (debugController.enabled) {
    observability.addSink(HttpTraceSink(logsDir: environment.logsDir));
  }

  http.Client makeHttpClient(String spanKind) => debugController.enabled
      ? LoggingHttpClient(
          inner: http.Client(),
          observability: observability,
          spanKind: spanKind,
          maxBodyBytes: config.observability.maxBodyBytes,
        )
      : http.Client();

  return ObservabilityBundle(
    observability: observability,
    debugController: debugController,
    httpClient: makeHttpClient,
  );
}
