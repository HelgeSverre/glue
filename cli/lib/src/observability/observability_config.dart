enum TelemetryProvider { langfuse, otel }

class LangfuseConfig {
  final bool enabled;
  final String? baseUrl;
  final String? publicKey;
  final String? secretKey;

  const LangfuseConfig({
    this.enabled = false,
    this.baseUrl,
    this.publicKey,
    this.secretKey,
  });

  bool get isConfigured => enabled && publicKey != null && secretKey != null;
}

class OtelConfig {
  final bool enabled;
  final String? endpoint;
  final Map<String, String> headers;

  const OtelConfig({
    this.enabled = false,
    this.endpoint,
    this.headers = const {},
  });

  bool get isConfigured => enabled && endpoint != null;
}

class ObservabilityConfig {
  final bool debug;
  final LangfuseConfig langfuse;
  final OtelConfig otel;
  final int flushIntervalSeconds;

  const ObservabilityConfig({
    this.debug = false,
    this.langfuse = const LangfuseConfig(),
    this.otel = const OtelConfig(),
    this.flushIntervalSeconds = 30,
  });
}
