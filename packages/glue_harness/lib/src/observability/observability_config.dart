/// Standard OTLP tracing export configuration.
class OtelConfig {
  final bool enabled;
  final String? endpoint;
  final Map<String, String> headers;
  final String serviceName;
  final Map<String, String> resourceAttributes;
  final int timeoutMilliseconds;

  const OtelConfig({
    this.enabled = false,
    this.endpoint,
    this.headers = const {},
    this.serviceName = 'glue',
    this.resourceAttributes = const {},
    this.timeoutMilliseconds = 10000,
  });

  bool get isConfigured =>
      enabled && endpoint != null && endpoint!.trim().isNotEmpty;
}

/// Observability configuration.
class ObservabilityConfig {
  final bool debug;

  /// Maximum bytes captured per HTTP request/response body, tool input, or
  /// tool output. Anything over the cap is truncated with a marker. Applied
  /// only when debug logging is on.
  final int maxBodyBytes;

  /// When false, skip body/URL/header scrubbing. Off is only safe for local
  /// reproduction — never ship with this disabled.
  final bool redact;

  /// OTLP-compatible trace export. This is independent of debug mode.
  final OtelConfig otel;

  const ObservabilityConfig({
    this.debug = false,
    this.maxBodyBytes = 65536,
    this.redact = true,
    this.otel = const OtelConfig(),
  });
}
