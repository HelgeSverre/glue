/// Observability configuration. Local-only after external sinks were removed.
class ObservabilityConfig {
  final bool debug;

  /// Maximum bytes captured per HTTP request/response body, tool input, or
  /// tool output. Anything over the cap is truncated with a marker. Applied
  /// only when debug logging is on.
  final int maxBodyBytes;

  /// When false, skip body/URL/header scrubbing. Off is only safe for local
  /// reproduction — never ship with this disabled.
  final bool redact;

  const ObservabilityConfig({
    this.debug = false,
    this.maxBodyBytes = 65536,
    this.redact = true,
  });
}
