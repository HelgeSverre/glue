import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:glue/src/web/browser/browser_endpoint.dart';

/// Browserbase cloud browser provider.
class BrowserbaseProvider implements BrowserEndpointProvider {
  final String? apiKey;
  final String? projectId;
  static const _baseUrl = 'https://www.browserbase.com/v1';

  BrowserbaseProvider({required this.apiKey, required this.projectId});

  @override
  String get name => 'browserbase';

  @override
  bool get isConfigured =>
      apiKey != null &&
      apiKey!.isNotEmpty &&
      projectId != null &&
      projectId!.isNotEmpty;

  @override
  @Deprecated('Use isConfigured instead.')
  bool get isAvailable => isConfigured;

  @override
  Future<BrowserEndpoint> provision() async {
    if (!isConfigured) {
      throw StateError('Browserbase API key or project ID not configured');
    }

    final response = await http
        .post(
          Uri.parse('$_baseUrl/sessions'),
          headers: {
            'X-BB-API-Key': apiKey!,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'projectId': projectId}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(
        'Browserbase API error ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final sessionId = json['id'] as String;
    final wsUrl =
        'wss://connect.browserbase.com?apiKey=$apiKey&sessionId=$sessionId';

    return BrowserEndpoint(
      cdpWsUrl: wsUrl,
      backendName: name,
      viewUrl: 'https://www.browserbase.com/sessions/$sessionId',
      onClose: () async {
        try {
          await http.post(
            Uri.parse('$_baseUrl/sessions/$sessionId/stop'),
            headers: {'X-BB-API-Key': apiKey!},
          );
        } catch (_) {}
      },
    );
  }
}
