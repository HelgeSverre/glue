/// Redaction helpers for HTTP debug logging.
///
/// Philosophy: allowlist safe header names, mask everything else. Bodies and
/// URLs pass through a deny-pattern regex pass so common API key shapes are
/// caught even if the header allowlist misses them.
library;

import 'dart:convert';

/// Header names that are always safe to log in full. Anything outside this
/// list is replaced with `****`.
const _safeHeaders = <String>{
  'accept',
  'accept-encoding',
  'accept-language',
  'cache-control',
  'connection',
  'content-encoding',
  'content-language',
  'content-length',
  'content-type',
  'date',
  'etag',
  'expires',
  'host',
  'if-modified-since',
  'if-none-match',
  'last-modified',
  'location',
  'pragma',
  'server',
  'transfer-encoding',
  'user-agent',
  'vary',
  'via',
  'x-powered-by',
  'x-request-id',
  'anthropic-version',
  'openai-organization',
  'openai-processing-ms',
  'openai-version',
  'x-ratelimit-limit-requests',
  'x-ratelimit-limit-tokens',
  'x-ratelimit-remaining-requests',
  'x-ratelimit-remaining-tokens',
  'x-ratelimit-reset-requests',
  'x-ratelimit-reset-tokens',
};

/// Query-param names whose values must be scrubbed.
const _sensitiveQueryKeys = <String>{
  'api_key',
  'apikey',
  'access_token',
  'auth',
  'authorization',
  'client_secret',
  'key',
  'password',
  'secret',
  'token',
};

/// Body-level patterns that look like secrets regardless of context.
final _secretPatterns = <RegExp>[
  // JSON "api_key": "...", "token": "...", etc.
  RegExp(
    r'"(api_?key|access_?token|client_?secret|authorization|password|secret|token)"\s*:\s*"[^"]+"',
    caseSensitive: false,
  ),
  // Bearer / Basic authorization header values appearing in bodies.
  RegExp(r'(Bearer|Basic)\s+[A-Za-z0-9\-._~+/=]+'),
  // OpenAI-style keys (sk-…).
  RegExp(r'sk-[A-Za-z0-9\-_]{16,}'),
  // Anthropic-style keys (sk-ant-…).
  RegExp(r'sk-ant-[A-Za-z0-9\-_]{16,}'),
  // GitHub tokens.
  RegExp(r'gh[pousr]_[A-Za-z0-9]{16,}'),
  // JWTs (three base64url segments joined by dots).
  RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'),
];

/// Returns a redacted copy of [headers].
///
/// Header names are compared case-insensitively. Values for allowlisted
/// headers pass through unchanged; everything else becomes `****`.
Map<String, String> redactHeaders(Map<String, String> headers) {
  final out = <String, String>{};
  headers.forEach((key, value) {
    final lower = key.toLowerCase();
    out[key] = _safeHeaders.contains(lower) ? value : '****';
  });
  return out;
}

/// Strips sensitive query parameters from [uri] and returns its string form.
///
/// We manually rebuild the query string so the literal `****` mask appears in
/// the log — using [Uri.replace] would url-encode the asterisks to `%2A`,
/// which is technically correct but unreadable.
String redactUrl(Uri uri) {
  final rawQuery = uri.query;
  if (rawQuery.isEmpty) return uri.toString();
  final redactedPairs = rawQuery.split('&').map((pair) {
    final eq = pair.indexOf('=');
    if (eq < 0) return pair;
    final keyEnc = pair.substring(0, eq);
    final key = Uri.decodeQueryComponent(keyEnc).toLowerCase();
    return _sensitiveQueryKeys.contains(key) ? '$keyEnc=****' : pair;
  }).join('&');
  final buffer = StringBuffer();
  if (uri.hasScheme) buffer.write('${uri.scheme}://');
  buffer.write(uri.authority);
  buffer.write(uri.path);
  buffer.write('?');
  buffer.write(redactedPairs);
  if (uri.hasFragment) {
    buffer
      ..write('#')
      ..write(uri.fragment);
  }
  return buffer.toString();
}

/// Redacts common secret patterns in [body] and truncates to [maxBytes].
///
/// UTF-8 length is used for the cap. If truncated, a `…[truncated N bytes]`
/// marker is appended so callers know they saw a partial body.
String redactBody(String body, {int maxBytes = 65536}) {
  var redacted = body;
  for (final pattern in _secretPatterns) {
    redacted = redacted.replaceAllMapped(pattern, (match) {
      final raw = match.group(0)!;
      // Preserve the JSON key name for pattern 1 so the log is still readable.
      final keyMatch =
          RegExp(r'"([^"]+)"\s*:', caseSensitive: false).firstMatch(raw);
      if (keyMatch != null) return '"${keyMatch.group(1)}":"****"';
      return '****';
    });
  }
  final bytes = utf8.encode(redacted);
  if (bytes.length <= maxBytes) return redacted;
  final truncatedBytes = bytes.sublist(0, maxBytes);
  final truncated = utf8.decode(truncatedBytes, allowMalformed: true);
  return '$truncated…[truncated ${bytes.length - maxBytes} bytes]';
}
