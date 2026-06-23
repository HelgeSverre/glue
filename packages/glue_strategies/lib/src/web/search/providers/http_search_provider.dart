import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:glue_strategies/src/web/search/models.dart';
import 'package:glue_strategies/src/web/search/provider.dart';

/// Error raised when a search provider's HTTP API returns a non-200 status.
class SearchApiException implements Exception {
  SearchApiException(this.message);
  final String message;
  @override
  String toString() => 'SearchApiException: $message';

  /// Truncates an HTTP error body to the first 200 chars for safe inclusion
  /// in an exception message. Shared by every HTTP-backed search provider.
  static String truncateBody(String body) =>
      body.length > 200 ? body.substring(0, 200) : body;
}

/// Describes a single HTTP request a search provider issues to its backend.
///
/// A non-null [body] implies a POST; a null [body] implies a GET.
class HttpSearchRequest {
  HttpSearchRequest({required this.uri, required this.headers, this.body});

  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

/// Shared skeleton for API-key-backed HTTP search providers (Brave, Tavily,
/// Firecrawl). Owns [isConfigured], the not-configured guard, the timeout, and
/// the non-200 status check with 200-char body truncation.
///
/// Subclasses supply only [buildRequest] (request shape per query) and
/// [parseResponseBody] (JSON → [WebSearchResponse]).
abstract class HttpSearchProvider implements WebSearchProvider {
  HttpSearchProvider({
    required this.apiKey,
    this.timeoutSeconds = 15,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String? apiKey;
  final int timeoutSeconds;
  final http.Client _client;

  /// Human-readable provider label used in error messages (e.g. 'Brave
  /// Search API', 'Tavily API').
  String get apiLabel;

  /// Error message used when [isConfigured] is false.
  String get notConfiguredMessage;

  /// Builds the HTTP request for [query] / [maxResults].
  HttpSearchRequest buildRequest(String query, int maxResults);

  /// Maps a decoded JSON body to a [WebSearchResponse].
  WebSearchResponse parseResponseBody(Map<String, dynamic> json, String query);

  @override
  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;

  @override
  Future<WebSearchResponse> search(String query, {int maxResults = 5}) async {
    if (!isConfigured) {
      throw StateError(notConfiguredMessage);
    }

    final request = buildRequest(query, maxResults);
    final response =
        await (request.body == null
                ? _client.get(request.uri, headers: request.headers)
                : _client.post(
                    request.uri,
                    headers: request.headers,
                    body: request.body,
                  ))
            .timeout(Duration(seconds: timeoutSeconds));

    if (response.statusCode != 200) {
      throw SearchApiException(
        '$apiLabel returned ${response.statusCode}: '
        '${SearchApiException.truncateBody(response.body)}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return parseResponseBody(json, query);
  }
}
