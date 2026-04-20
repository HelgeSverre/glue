import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:glue/src/web/browser/browser_endpoint.dart';

/// Hyperbrowser cloud browser provider.
class HyperbrowserProvider implements BrowserEndpointProvider {
  final String? apiKey;
  final http.Client _client;

  static const _baseUrl = 'https://api.hyperbrowser.ai/api';

  HyperbrowserProvider({
    required this.apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get name => 'hyperbrowser';

  @override
  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;

  @override
  Future<BrowserEndpoint> provision() async {
    if (!isConfigured) throw StateError('Hyperbrowser API key not configured');

    final response = await _client
        .post(
          Uri.parse('$_baseUrl/session'),
          headers: {
            'x-api-key': apiKey!,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(
        'Hyperbrowser API error ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final sessionId = json['id'] as String?;
    final cdpUrl = json['wsEndpoint'] as String?;
    final liveViewUrl = json['liveUrl'] as String?;

    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('Hyperbrowser API response missing id');
    }
    if (cdpUrl == null || cdpUrl.isEmpty) {
      throw StateError('Hyperbrowser API response missing wsEndpoint');
    }

    return BrowserEndpoint(
      cdpWsUrl: cdpUrl,
      backendName: name,
      viewUrl: liveViewUrl,
      onClose: () async {
        try {
          await _client.put(
            Uri.parse('$_baseUrl/session/$sessionId/stop'),
            headers: {'x-api-key': apiKey!},
          );
        } catch (_) {}
      },
    );
  }
}
