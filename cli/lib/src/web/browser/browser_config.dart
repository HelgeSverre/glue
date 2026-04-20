import 'package:glue/src/config/constants.dart';

/// Supported browser execution backends.
///
/// We use "backend" here to describe the runtime environment where the browser
/// session is provisioned (local process, docker container, or cloud service).
enum BrowserBackend {
  local,
  docker,
  steel,
  browserbase,
  browserless,
  anchor,
  hyperbrowser,
}

/// Configuration for the web_browser tool.
class BrowserConfig {
  final BrowserBackend backend;
  final bool headed;
  final int navigationTimeoutSeconds;
  final int actionTimeoutSeconds;

  // Docker-specific settings.
  final String dockerImage;
  final int dockerPort;

  // Cloud provider credentials.
  final String? steelApiKey;
  final String? browserbaseApiKey;
  final String? browserbaseProjectId;
  final String? browserlessBaseUrl;
  final String? browserlessApiKey;
  final String? anchorApiKey;
  final String? hyperbrowserApiKey;

  const BrowserConfig({
    this.backend = BrowserBackend.local,
    this.headed = false,
    this.navigationTimeoutSeconds =
        AppConstants.browserNavigationTimeoutSeconds,
    this.actionTimeoutSeconds = AppConstants.browserActionTimeoutSeconds,
    this.dockerImage = AppConstants.browserDockerImage,
    this.dockerPort = AppConstants.browserDockerPort,
    this.steelApiKey,
    this.browserbaseApiKey,
    this.browserbaseProjectId,
    this.browserlessBaseUrl,
    this.browserlessApiKey,
    this.anchorApiKey,
    this.hyperbrowserApiKey,
  });

  /// Whether the selected backend has valid credentials/configuration.
  bool get isConfigured => switch (backend) {
        BrowserBackend.local => true,
        BrowserBackend.docker => true,
        BrowserBackend.steel => steelApiKey != null && steelApiKey!.isNotEmpty,
        BrowserBackend.browserbase => browserbaseApiKey != null &&
            browserbaseApiKey!.isNotEmpty &&
            browserbaseProjectId != null &&
            browserbaseProjectId!.isNotEmpty,
        BrowserBackend.browserless =>
          browserlessApiKey != null && browserlessApiKey!.isNotEmpty,
        BrowserBackend.anchor =>
          anchorApiKey != null && anchorApiKey!.isNotEmpty,
        BrowserBackend.hyperbrowser =>
          hyperbrowserApiKey != null && hyperbrowserApiKey!.isNotEmpty,
      };
}
