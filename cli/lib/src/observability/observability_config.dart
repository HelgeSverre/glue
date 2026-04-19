/// Observability configuration. Local-only after external sinks were removed.
class ObservabilityConfig {
  final bool debug;

  const ObservabilityConfig({
    this.debug = false,
  });
}
