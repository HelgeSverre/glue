/// Configuration for the Daytona runtime adapter.
///
/// Daytona has two regional control planes (US and EU) and returns a
/// per-sandbox toolbox URL on create — so the user only configures
/// the control plane, and the toolbox URL is resolved per sandbox at
/// runtime:
///
///   - **Control plane** ([apiBaseUrl]) for sandbox lifecycle
///     (create, stop, list). Defaults to the US region
///     (`https://app.daytona.io/api`); set to
///     `https://app-eu.daytona.io/api` for EU accounts (or pass
///     `runtime: daytona` + `daytona.api_base_url: …` in config).
///   - **Toolbox** for the per-sandbox surface (exec, files,
///     sessions) — the URL is returned by the create-sandbox response
///     as `toolboxProxyUrl` (e.g.
///     `https://proxy.app-eu.daytona.io/toolbox`), and glue uses it
///     automatically. An optional [toolboxBaseUrlOverride] is
///     available for staging / proxy testing.
///
/// Both bases accept the same `Authorization: Bearer <apiKey>` header.
class DaytonaConfig {
  /// API token used as the `Authorization: Bearer <apiKey>` header on
  /// every request. Required; without it [DaytonaRuntime.start] throws.
  final String apiKey;

  /// Base URL for the Daytona REST control-plane API. Defaults to the
  /// US region — override for EU (`https://app-eu.daytona.io/api`) or
  /// for self-hosted / staging deployments.
  final String apiBaseUrl;

  /// Optional override for the toolbox URL. When `null` (default),
  /// glue uses the per-sandbox `toolboxProxyUrl` returned by the
  /// create-sandbox call, which routes to the correct region
  /// automatically. Set this only when you need to force traffic
  /// through a proxy or staging endpoint.
  final String? toolboxBaseUrlOverride;

  /// Pre-built snapshot id the new sandbox should be based on. When
  /// `null`, Daytona uses the org's default snapshot (currently
  /// `daytonaio/sandbox:0.7.0`) — usually what you want.
  final String? snapshot;

  /// How long to wait for the sandbox to become responsive after
  /// creation before giving up.
  final Duration startTimeout;

  /// Cap on how long a single exec call may run before the executor
  /// times it out. Per-call timeouts can override via the optional
  /// `timeout` parameter; this is just the upper bound.
  final Duration execTimeout;

  const DaytonaConfig({
    required this.apiKey,
    this.apiBaseUrl = 'https://app.daytona.io/api',
    this.toolboxBaseUrlOverride,
    this.snapshot,
    this.startTimeout = const Duration(minutes: 2),
    this.execTimeout = const Duration(minutes: 30),
  });

  DaytonaConfig copyWith({
    String? apiKey,
    String? apiBaseUrl,
    String? toolboxBaseUrlOverride,
    String? snapshot,
    Duration? startTimeout,
    Duration? execTimeout,
  }) =>
      DaytonaConfig(
        apiKey: apiKey ?? this.apiKey,
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        toolboxBaseUrlOverride:
            toolboxBaseUrlOverride ?? this.toolboxBaseUrlOverride,
        snapshot: snapshot ?? this.snapshot,
        startTimeout: startTimeout ?? this.startTimeout,
        execTimeout: execTimeout ?? this.execTimeout,
      );
}
