import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/redaction.dart';

/// A wrapping [http.Client] that starts/ends an [ObservabilitySpan] for every
/// outbound request, records redacted request and response details, and tees
/// the response body so streaming consumers still see the original bytes.
///
/// The span name is `http.{spanKind}` (e.g. `http.llm.anthropic`,
/// `http.search.brave`). All spans share parent inheritance via
/// [Observability.activeSpan] so they stitch into the current agent turn.
class LoggingHttpClient extends http.BaseClient {
  LoggingHttpClient({
    required http.Client inner,
    required Observability observability,
    required String spanKind,
    int maxBodyBytes = 65536,
    Map<String, String> staticAttributes = const {},
  })  : _inner = inner,
        _obs = observability,
        _spanKind = spanKind,
        _maxBodyBytes = maxBodyBytes,
        _staticAttributes = staticAttributes;

  final http.Client _inner;
  final Observability _obs;
  final String _spanKind;
  final int _maxBodyBytes;
  final Map<String, String> _staticAttributes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final attributes = <String, dynamic>{
      ..._staticAttributes,
      'http.method': request.method,
      'http.url': redactUrl(request.url),
      'http.request_headers': redactHeaders(request.headers),
    };

    // Capture request body for non-streaming Request. For StreamedRequest we
    // skip body capture to avoid draining the caller's stream.
    if (request is http.Request) {
      attributes['http.request_body_size'] = request.bodyBytes.length;
      attributes['http.request_body'] =
          redactBody(request.body, maxBytes: _maxBodyBytes);
    }

    final span = _obs.startSpan(
      'http.$_spanKind',
      kind: 'http.$_spanKind',
      attributes: attributes,
    );

    http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (error, stack) {
      _obs.endSpan(span, extra: {
        'error': true,
        'error.type': error.runtimeType.toString(),
        'error.message': error.toString(),
        'error.stack': stack.toString(),
      });
      rethrow;
    }

    // Tee the response body: accumulate bytes into a buffer so we can emit a
    // redacted transcript in the span, while forwarding chunks to the caller
    // unchanged. End the span on done/error.
    final collected = <int>[];
    final started = DateTime.now();
    final teed = response.stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          // Cap collection at 2x the cap so the redactor has room to work
          // before we discard the tail.
          if (collected.length < _maxBodyBytes * 2) {
            collected.addAll(chunk);
          }
          sink.add(chunk);
        },
        handleError: (error, stack, sink) {
          _obs.endSpan(span, extra: {
            'http.status_code': response.statusCode,
            'http.duration_ms':
                DateTime.now().difference(started).inMilliseconds,
            'error': true,
            'error.type': error.runtimeType.toString(),
            'error.message': error.toString(),
            'error.stack': stack.toString(),
          });
          sink
            ..addError(error, stack)
            ..close();
        },
        handleDone: (sink) {
          final bodyText = utf8.decode(collected, allowMalformed: true);
          _obs.endSpan(span, extra: {
            'http.status_code': response.statusCode,
            'http.response_headers': redactHeaders(response.headers),
            'http.response_body_size': collected.length,
            'http.response_body': redactBody(bodyText, maxBytes: _maxBodyBytes),
            'http.duration_ms':
                DateTime.now().difference(started).inMilliseconds,
          });
          sink.close();
        },
      ),
    );

    return http.StreamedResponse(
      teed,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
