import 'dart:async';
import 'package:http/http.dart' as http;

class JinaReaderClient {
  final String baseUrl;
  final String? apiKey;
  final int timeoutSeconds;

  JinaReaderClient({
    this.baseUrl = 'https://r.jina.ai',
    this.apiKey,
    this.timeoutSeconds = 30,
  });

  Uri buildReaderUrl(String targetUrl) => Uri.parse('$baseUrl/$targetUrl');

  Map<String, String> get headers {
    final h = <String, String>{
      'Accept': 'text/markdown',
    };
    if (apiKey != null && apiKey!.isNotEmpty) {
      h['Authorization'] = 'Bearer $apiKey';
    }
    return h;
  }

  Future<String?> fetch(String url) async {
    try {
      final response = await http
          .get(buildReaderUrl(url), headers: headers)
          .timeout(Duration(seconds: timeoutSeconds));

      if (response.statusCode == 200) {
        return response.body;
      }
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
