/// A provisioned browser endpoint with CDP WebSocket URL.
class BrowserEndpoint {
  final String cdpWsUrl;
  final String backendName;
  final bool headed;
  final String? viewUrl;
  final Future<void> Function()? _onClose;

  BrowserEndpoint({
    required this.cdpWsUrl,
    required this.backendName,
    this.headed = false,
    this.viewUrl,
    Future<void> Function()? onClose,
  }) : _onClose = onClose;

  /// Release the browser endpoint (stop container, close session, etc.).
  Future<void> close() async {
    if (_onClose != null) await _onClose();
  }

  /// Debug footer for tool results.
  String get debugFooter {
    final parts = <String>['---', 'Backend: $backendName'];
    if (headed) parts.add('Mode: headed');
    if (viewUrl != null) parts.add('View session: $viewUrl');
    return parts.join('\n');
  }
}

/// Interface for provisioning browser endpoints.
///
/// "Provider" here is the concrete provisioning implementation for the chosen
/// browser backend (local/docker/cloud).
abstract class BrowserEndpointProvider {
  String get name;
  bool get isConfigured;

  @Deprecated('Use isConfigured instead.')
  bool get isAvailable => isConfigured;
  Future<BrowserEndpoint> provision();
}
