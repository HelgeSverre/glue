import 'package:glue_strategies/src/web/browser/providers/http_session_browser_provider.dart';

/// Browserbase cloud browser provider.
class BrowserbaseProvider extends HttpSessionBrowserProvider {
  BrowserbaseProvider({
    required super.apiKey,
    required this.projectId,
    super.client,
  });

  final String? projectId;
  static const _baseUrl = 'https://www.browserbase.com/v1';

  @override
  String get name => 'browserbase';

  @override
  String get label => 'Browserbase';

  @override
  String get notConfiguredReason => 'API key or project ID not configured';

  @override
  bool get isConfigured =>
      apiKey != null &&
      apiKey!.isNotEmpty &&
      projectId != null &&
      projectId!.isNotEmpty;

  @override
  HttpSessionRequest createRequest() {
    return HttpSessionRequest(
      method: 'POST',
      url: Uri.parse('$_baseUrl/sessions'),
      headers: {'X-BB-API-Key': apiKey!, 'Content-Type': 'application/json'},
      body: {'projectId': projectId},
    );
  }

  @override
  HttpSessionResult mapResponse(Map<String, dynamic> json) {
    final sessionId = json['id'] as String;
    return HttpSessionResult(
      cdpWsUrl:
          'wss://connect.browserbase.com?apiKey=$apiKey&sessionId=$sessionId',
      viewUrl: 'https://www.browserbase.com/sessions/$sessionId',
      closeRequest: HttpSessionRequest(
        method: 'POST',
        url: Uri.parse('$_baseUrl/sessions/$sessionId/stop'),
        headers: {'X-BB-API-Key': apiKey!},
      ),
    );
  }
}
