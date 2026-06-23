import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:glue_strategies/src/web/browser/browser_endpoint.dart';

/// A single HTTP call against a cloud browser provider's session API.
///
/// Used both to create a session (the POST in [HttpSessionBrowserProvider
/// .provision]) and to release it (the request returned in
/// [HttpSessionResult.closeRequest]).
class HttpSessionRequest {
  HttpSessionRequest({
    required this.method,
    required this.url,
    required this.headers,
    this.body,
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;

  /// JSON body for the request, if any. Encoded with [jsonEncode].
  final Object? body;
}

/// The provisioned endpoint details a provider extracts from its
/// session-creation response.
class HttpSessionResult {
  HttpSessionResult({required this.cdpWsUrl, this.viewUrl, this.closeRequest});

  final String cdpWsUrl;
  final String? viewUrl;

  /// Request issued (best-effort) to release the session on close.
  final HttpSessionRequest? closeRequest;
}

/// Shared base for cloud browser providers that provision a CDP endpoint by
/// POSTing to an HTTP session API.
///
/// Owns the `apiKey` configuration guard and the shared POST / status-check /
/// close plumbing. Subclasses supply only their endpoint, headers, request
/// body, and response mapping via [createRequest] and [mapResponse].
abstract class HttpSessionBrowserProvider implements BrowserEndpointProvider {
  HttpSessionBrowserProvider({required this.apiKey, http.Client? client})
    : client = client ?? http.Client();

  final String? apiKey;
  final http.Client client;

  /// Human-readable provider label used in error messages
  /// (e.g. `'Anchor'`, `'Hyperbrowser'`).
  String get label;

  /// Reason appended after the label when [isConfigured] is false,
  /// e.g. `'API key not configured'`.
  String get notConfiguredReason => 'API key not configured';

  @override
  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;

  /// The request that creates a session.
  HttpSessionRequest createRequest();

  /// Map the decoded session-creation response into endpoint details.
  HttpSessionResult mapResponse(Map<String, dynamic> json);

  @override
  Future<BrowserEndpoint> provision() async {
    if (!isConfigured) {
      throw StateError('$label $notConfiguredReason');
    }

    final response = await _send(
      createRequest(),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(
        '$label API error ${response.statusCode}: ${response.body}',
      );
    }

    final result = mapResponse(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    final closeRequest = result.closeRequest;

    return BrowserEndpoint(
      cdpWsUrl: result.cdpWsUrl,
      backendName: name,
      viewUrl: result.viewUrl,
      onClose: closeRequest == null
          ? null
          : () async {
              try {
                await _send(closeRequest);
              } catch (_) {}
            },
    );
  }

  Future<http.Response> _send(HttpSessionRequest request) {
    final body = request.body == null ? null : jsonEncode(request.body);
    return switch (request.method) {
      'POST' => client.post(request.url, headers: request.headers, body: body),
      'PUT' => client.put(request.url, headers: request.headers, body: body),
      'DELETE' => client.delete(request.url, headers: request.headers),
      _ => throw StateError('Unsupported method: ${request.method}'),
    };
  }
}
