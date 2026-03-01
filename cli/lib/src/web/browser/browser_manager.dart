import 'dart:async';

import 'package:glue/src/web/browser/browser_endpoint.dart';

/// Session-scoped browser lifecycle manager.
class BrowserManager {
  final BrowserEndpointProvider provider;
  BrowserEndpoint? _endpoint;
  Future<BrowserEndpoint>? _pending;
  bool _isDisposed = false;

  BrowserManager({required this.provider});

  bool get isConnected => _endpoint != null;

  Future<BrowserEndpoint> getEndpoint() async {
    if (_endpoint != null) return _endpoint!;
    // Guard against concurrent provisions.
    _pending ??= _provision();
    return _pending!;
  }

  Future<BrowserEndpoint> _provision() async {
    _isDisposed = false;
    try {
      final ep = await provider.provision();
      if (_isDisposed) {
        // dispose() was called while we were provisioning.
        await ep.close();
        _endpoint = null;
      } else {
        _endpoint = ep;
      }
      return ep;
    } finally {
      _pending = null;
    }
  }

  Future<void> dispose() async {
    _isDisposed = true;
    if (_endpoint != null) {
      await _endpoint!.close();
      _endpoint = null;
    }
  }
}
