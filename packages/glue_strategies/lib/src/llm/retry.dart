import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:glue_core/glue_core.dart';
import 'package:http/http.dart' as http;

/// Retry-with-backoff wrapper for a streaming LLM request (M6).
///
/// Wraps a `factory` that (re)opens the provider stream — each attempt
/// invokes it afresh, which (via [http.Client.send] in the clients) opens a
/// new TCP connection. On a **transient** failure that occurs *before any
/// chunk has been emitted*, this waits with exponential backoff + full
/// jitter and retries, up to [maxAttempts] total attempts.
///
/// Two safety rules keep retries from corrupting a turn:
///
/// 1. **Never retry after output.** Once the wrapped stream has yielded even
///    one [LlmChunk] (or any `T`), a subsequent error propagates unchanged —
///    retrying would replay already-emitted text / tool calls and double them
///    downstream. Transient network / 429 / 5xx failures surface *before* the
///    first chunk (the clients throw on a non-200 status before parsing), so
///    this is exactly the retry-safe window.
/// 2. **Only retry transient errors.** [isTransient] (default
///    [isTransientLlmError]) gates retries to connection errors, timeouts,
///    HTTP 429, and 5xx. 4xx-non-429 (bad request, auth, not-found) and typed
///    fail-fast errors like [ToolsNotSupportedException] propagate immediately.
///
/// [sleep] and [random] are injectable so tests exercise the backoff logic
/// without real delays or nondeterminism.
Stream<T> retryStream<T>(
  Stream<T> Function() factory, {
  int maxAttempts = 3,
  Duration baseDelay = const Duration(milliseconds: 500),
  Duration maxDelay = const Duration(seconds: 20),
  bool Function(Object error)? isTransient,
  Future<void> Function(Duration delay)? sleep,
  Random? random,
}) async* {
  final transient = isTransient ?? isTransientLlmError;
  final rng = random ?? Random();
  final waiter = sleep ?? Future<void>.delayed;

  var attempt = 0;
  while (true) {
    attempt++;
    var yieldedAny = false;
    try {
      await for (final item in factory()) {
        yieldedAny = true;
        yield item;
      }
      return;
    } catch (error) {
      final canRetry = !yieldedAny && attempt < maxAttempts && transient(error);
      if (!canRetry) rethrow;
      await waiter(_backoffDelay(attempt, baseDelay, maxDelay, rng));
    }
  }
}

/// Full-jitter exponential backoff: a random duration in `[0, cap]` where
/// `cap = min(maxDelay, baseDelay * 2^(attempt-1))`. Full jitter avoids
/// retry stampedes when many requests fail at once.
Duration _backoffDelay(int attempt, Duration base, Duration max, Random rng) {
  final expMs = base.inMilliseconds * (1 << (attempt - 1));
  final capMs = expMs < max.inMilliseconds ? expMs : max.inMilliseconds;
  final jittered = (rng.nextDouble() * capMs).round();
  return Duration(milliseconds: jittered);
}

/// Classifies an error thrown by an [LlmClient] stream as transient
/// (worth retrying) or not.
///
/// Transient: connection errors ([SocketException], [http.ClientException]),
/// [TimeoutException], and HTTP 429 / 5xx (detected from the stable
/// `"<Provider> API error <status>: <body>"` message the shared transport
/// throws). Everything else — 4xx-non-429, [ToolsNotSupportedException], and
/// provider-signalled mid-stream errors — is treated as permanent.
bool isTransientLlmError(Object error) {
  if (error is ToolsNotSupportedException) return false;
  if (error is SocketException) return true;
  if (error is http.ClientException) return true;
  if (error is TimeoutException) return true;

  final status = _httpStatusFromMessage(error.toString());
  if (status != null) {
    if (status == 429) return true;
    if (status >= 500 && status <= 599) return true;
    return false;
  }
  return false;
}

/// Extracts the HTTP status from the shared transport's error message
/// (`"<Provider> API error <status>: <body>"`), or null when absent.
int? _httpStatusFromMessage(String message) {
  final match = RegExp(r'API error (\d{3})\b').firstMatch(message);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
