import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:glue/src/web/browser/browser_endpoint.dart';

/// Anchor Browser cloud browser provider.
class AnchorProvider implements BrowserEndpointProvider {
  final String? apiKey;
  final http.Client _client;

  static const _baseUrl = 'https://api.anchorbrowser.io/v1';

  AnchorProvider({
    required this.apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get name => 'anchor';

  @override
  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;

  @override
  Future<BrowserEndpoint> provision() async {
    if (!isConfigured) throw StateError('Anchor API key not configured');

    final response = await _client
        .post(
          Uri.parse('$_baseUrl/sessions'),
          headers: {
            'anchor-api-key': apiKey!,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(
        'Anchor API error ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    final sessionId = data['id'] as String?;
    final cdpUrl = data['cdp_url'] as String?;
    final liveViewUrl = data['live_view_url'] as String?;

    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('Anchor API response missing data.id');
    }
    if (cdpUrl == null || cdpUrl.isEmpty) {
      throw StateError('Anchor API response missing data.cdp_url');
    }

    return BrowserEndpoint(
      cdpWsUrl: cdpUrl,
      backendName: name,
      viewUrl: liveViewUrl,
      onClose: () async {
        try {
          await _client.delete(
            Uri.parse('$_baseUrl/sessions/$sessionId'),
            headers: {'anchor-api-key': apiKey!},
          );
        } catch (_) {}
      },
    );
  }
}
