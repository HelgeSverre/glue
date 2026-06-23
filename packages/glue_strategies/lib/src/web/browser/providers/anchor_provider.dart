import 'package:glue_strategies/src/web/browser/providers/http_session_browser_provider.dart';

/// Anchor Browser cloud browser provider.
class AnchorProvider extends HttpSessionBrowserProvider {
  AnchorProvider({required super.apiKey, super.client});

  static const _baseUrl = 'https://api.anchorbrowser.io/v1';

  @override
  String get name => 'anchor';

  @override
  String get label => 'Anchor';

  @override
  HttpSessionRequest createRequest() {
    return HttpSessionRequest(
      method: 'POST',
      url: Uri.parse('$_baseUrl/sessions'),
      headers: {'anchor-api-key': apiKey!, 'Content-Type': 'application/json'},
      body: const {},
    );
  }

  @override
  HttpSessionResult mapResponse(Map<String, dynamic> json) {
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

    return HttpSessionResult(
      cdpWsUrl: cdpUrl,
      viewUrl: liveViewUrl,
      closeRequest: HttpSessionRequest(
        method: 'DELETE',
        url: Uri.parse('$_baseUrl/sessions/$sessionId'),
        headers: {'anchor-api-key': apiKey!},
      ),
    );
  }
}
