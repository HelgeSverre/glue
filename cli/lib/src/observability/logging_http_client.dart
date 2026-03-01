import 'package:http/http.dart' as http;
import 'package:glue/src/observability/observability.dart';

class LoggingHttpClient extends http.BaseClient {
  final http.Client _inner;
  final Observability _obs;

  LoggingHttpClient({required http.Client inner, required Observability obs})
      : _inner = inner,
        _obs = obs;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final span = _obs.startSpan(
      'http ${request.method}',
      kind: 'http',
      attributes: {
        'http.method': request.method,
        'http.url': request.url.toString(),
      },
    );
    try {
      final response = await _inner.send(request);
      // TODO: This measures TTFB (time to first byte), not full download.
      // For streaming responses, consider wrapping the response stream to
      // end the span on completion for accurate total transfer duration.
      _obs.endSpan(span, extra: {'http.status_code': response.statusCode});
      return response;
    } catch (e) {
      _obs.endSpan(span, extra: {'error': e.toString()});
      rethrow;
    }
  }
}
