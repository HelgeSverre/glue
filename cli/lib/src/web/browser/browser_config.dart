import 'package:glue/src/config/constants.dart';

/// Supported browser execution backends.
///
/// We use "backend" here to describe the runtime environment where the browser
/// session is provisioned (local process, docker container, or cloud service).
enum BrowserBackend { local, docker, steel, browserbase, browserless }

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
      };
}
