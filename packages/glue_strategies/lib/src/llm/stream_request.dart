import 'dart:async';
import 'dart:convert';

import 'package:glue_core/glue_core.dart';
import 'package:http/http.dart' as http;

/// Shared streaming-POST envelope used by every built-in [LlmClient].
///
/// All four clients (Anthropic, OpenAI-compatible, Ollama, Gemini) share the
/// same request lifecycle: build a JSON body, POST it with provider headers,
/// fail on a non-200 status, then hand the raw byte stream to a provider
/// decoder/parser. The only per-provider variation is the URI, the headers,
/// the body, the decode+parse pipeline, and (for Ollama) how a specific
/// error status maps to a typed exception.
///
/// A per-request [http.Client] is created via [requestClientFactory] and
/// closed in a `finally`, so cancelling the returned stream's subscription
/// aborts the TCP connection (saving output tokens).
///
/// [classifyError] is consulted before the generic error path when the
/// response status is not 200; returning normally from it is not allowed —
/// it must throw (its return type is `Future<Never>`). When it is null, or
/// when it is provided but the caller wants the default for an unhandled
/// status, a generic `Exception('$providerName API error <status>: <body>')`
/// is thrown.
Stream<LlmChunk> sendAndStream({
  required http.Client Function() requestClientFactory,
  required Uri uri,
  required Map<String, String> headers,
  required Map<String, dynamic> body,
  required String providerName,
  required Stream<LlmChunk> Function(Stream<List<int>> bytes) parse,
  Future<Never> Function(int status, String body)? classifyError,
}) async* {
  // Per-request client: closing it aborts the TCP connection when the
  // stream subscription is cancelled, saving output tokens.
  final requestClient = requestClientFactory();
  try {
    final request = http.Request('POST', uri);
    request.headers.addAll(headers);
    request.body = jsonEncode(body);

    final response = await requestClient.send(request);

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      if (classifyError != null) {
        await classifyError(response.statusCode, errorBody);
      }
      throw Exception(
        '$providerName API error ${response.statusCode}: $errorBody',
      );
    }

    yield* parse(response.stream);
  } finally {
    requestClient.close();
  }
}
