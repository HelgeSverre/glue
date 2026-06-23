import 'package:glue_strategies/src/web/browser/providers/http_session_browser_provider.dart';

/// Steel.dev cloud browser provider.
class SteelProvider extends HttpSessionBrowserProvider {
  SteelProvider({required super.apiKey, super.client});

  static const _baseUrl = 'https://api.steel.dev/v1';

  @override
  String get name => 'steel';

  @override
  String get label => 'Steel';

  @override
  HttpSessionRequest createRequest() {
    return HttpSessionRequest(
      method: 'POST',
      url: Uri.parse('$_baseUrl/sessions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: const {'projectId': 'default'},
    );
  }

  @override
  HttpSessionResult mapResponse(Map<String, dynamic> json) {
    final sessionId = json['id'] as String;
    final wsUrl = json['websocketUrl'] as String;
    final viewUrl = json['viewerUrl'] as String?;

    return HttpSessionResult(
      cdpWsUrl: wsUrl,
      viewUrl: viewUrl ?? 'https://app.steel.dev/sessions/$sessionId',
      closeRequest: HttpSessionRequest(
        method: 'DELETE',
        url: Uri.parse('$_baseUrl/sessions/$sessionId'),
        headers: {'Authorization': 'Bearer $apiKey'},
      ),
    );
  }
}
