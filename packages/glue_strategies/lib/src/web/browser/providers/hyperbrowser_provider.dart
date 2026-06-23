import 'package:glue_strategies/src/web/browser/providers/http_session_browser_provider.dart';

/// Hyperbrowser cloud browser provider.
class HyperbrowserProvider extends HttpSessionBrowserProvider {
  HyperbrowserProvider({required super.apiKey, super.client});

  static const _baseUrl = 'https://api.hyperbrowser.ai/api';

  @override
  String get name => 'hyperbrowser';

  @override
  String get label => 'Hyperbrowser';

  @override
  HttpSessionRequest createRequest() {
    return HttpSessionRequest(
      method: 'POST',
      url: Uri.parse('$_baseUrl/session'),
      headers: {'x-api-key': apiKey!, 'Content-Type': 'application/json'},
      body: const {},
    );
  }

  @override
  HttpSessionResult mapResponse(Map<String, dynamic> json) {
    final sessionId = json['id'] as String?;
    final cdpUrl = json['wsEndpoint'] as String?;
    final liveViewUrl = json['liveUrl'] as String?;

    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('Hyperbrowser API response missing id');
    }
    if (cdpUrl == null || cdpUrl.isEmpty) {
      throw StateError('Hyperbrowser API response missing wsEndpoint');
    }

    return HttpSessionResult(
      cdpWsUrl: cdpUrl,
      viewUrl: liveViewUrl,
      closeRequest: HttpSessionRequest(
        method: 'PUT',
        url: Uri.parse('$_baseUrl/session/$sessionId/stop'),
        headers: {'x-api-key': apiKey!},
      ),
    );
  }
}
