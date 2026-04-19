import 'dart:async';

import 'package:glue/src/web/browser/browser_endpoint.dart';

/// Browserless.io cloud browser provider.
class BrowserlessProvider implements BrowserEndpointProvider {
  final String? apiKey;
  final String baseUrl;

  BrowserlessProvider({required this.apiKey, required this.baseUrl});

  @override
  String get name => 'browserless';

  @override
  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;

  /// Build the WebSocket URL for CDP connection.
  String buildWsUrl() {
    var wsBase = baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    if (!wsBase.startsWith('ws')) {
      wsBase = 'wss://$wsBase';
    }
    return '$wsBase?token=$apiKey';
  }

  @override
  Future<BrowserEndpoint> provision() async {
    if (!isConfigured) {
      throw StateError('Browserless API key not configured');
    }

    return BrowserEndpoint(
      cdpWsUrl: buildWsUrl(),
      backendName: name,
    );
  }
}
