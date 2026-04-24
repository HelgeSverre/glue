import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:glue/src/web/browser/browser_endpoint.dart';
import 'package:glue/src/utils.dart';

/// Steel.dev cloud browser provider.
class SteelProvider implements BrowserEndpointProvider {
  final String? apiKey;
  final http.Client _client;
  static const _baseUrl = 'https://api.steel.dev/v1';

  SteelProvider({
    required this.apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get name => 'steel';

  @override
  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;

  @override
  @override
  Future<BrowserEndpoint> provision() async {
    if (!isConfigured) throw StateError('Steel API key not configured');

    final response = await _client
        .post(
          Uri.parse('$_baseUrl/sessions'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'projectId': 'default'}),
        )
        .timeout(30.seconds);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(
        'Steel API error ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final sessionId = json['id'] as String;
    final wsUrl = json['websocketUrl'] as String;
    final viewUrl = json['viewerUrl'] as String?;

    return BrowserEndpoint(
      cdpWsUrl: wsUrl,
      backendName: name,
      viewUrl: viewUrl ?? 'https://app.steel.dev/sessions/$sessionId',
      onClose: () async {
        try {
          await _client.delete(
            Uri.parse('$_baseUrl/sessions/$sessionId'),
            headers: {'Authorization': 'Bearer $apiKey'},
          );
        } catch (_) {}
      },
    );
  }
}
