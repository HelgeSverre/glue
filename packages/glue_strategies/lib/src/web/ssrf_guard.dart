import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Resolves a host name to a list of IP addresses.
///
/// Injectable so callers (and tests) can supply a deterministic, offline
/// resolver instead of hitting real DNS.
typedef HostResolver = Future<List<InternetAddress>> Function(String host);

Future<List<InternetAddress>> _defaultResolver(String host) =>
    InternetAddress.lookup(host);

/// Thrown when a URL targets a network location Glue refuses to fetch:
/// loopback, private, link-local (including the cloud metadata endpoint), ULA,
/// multicast, unspecified, or an unsupported scheme.
class SsrfBlockedException implements Exception {
  SsrfBlockedException(this.url, this.reason);

  final String url;
  final String reason;

  @override
  String toString() => 'SsrfBlockedException: blocked $url ($reason)';
}

/// Guards outbound fetches of caller/model-supplied URLs against SSRF.
///
/// The web_fetch / web_search / browser tools are auto-allowed (they run
/// without a human approval prompt), so a prompt injection that steers the
/// model to fetch `http://169.254.169.254/…` could read cloud IAM credentials
/// and exfiltrate them. This guard resolves the target host up front and
/// refuses any address that is not publicly routable, and re-validates on every
/// redirect hop (metadata endpoints are frequently reached via a 30x bounce).
class SsrfGuard {
  SsrfGuard({HostResolver? resolver, this.maxRedirects = 5})
    : _resolver = resolver ?? _defaultResolver;

  final HostResolver _resolver;
  final int maxRedirects;

  /// Validates [uri]'s scheme and host, resolving the host and rejecting if
  /// ANY resolved address is non-public. Throws [SsrfBlockedException] on
  /// rejection. Literal-IP hosts are checked directly (no DNS lookup).
  Future<void> validate(Uri uri) async {
    if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw SsrfBlockedException(uri.toString(), 'unsupported scheme');
    }
    final host = uri.host;
    if (host.isEmpty) {
      throw SsrfBlockedException(uri.toString(), 'missing host');
    }

    final literal = InternetAddress.tryParse(host);
    final addresses = literal != null ? [literal] : await _resolver(host);
    if (addresses.isEmpty) {
      throw SsrfBlockedException(uri.toString(), 'host did not resolve');
    }
    for (final addr in addresses) {
      if (isBlockedAddress(addr)) {
        throw SsrfBlockedException(
          uri.toString(),
          'resolves to non-public address ${addr.address}',
        );
      }
    }
  }

  /// GET [url] with [client], following redirects manually and re-validating
  /// the target before every hop. Automatic redirect following is disabled so a
  /// 30x pointing at an internal address can never be dereferenced.
  ///
  /// Throws [SsrfBlockedException] if the initial URL or any redirect target is
  /// non-public, or if the redirect budget ([maxRedirects]) is exceeded.
  Future<http.Response> safeGet(
    http.Client client,
    Uri url, {
    Map<String, String> headers = const {},
    Duration? timeout,
  }) async {
    var current = url;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      await validate(current);

      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers.addAll(headers);

      final streamed = await _withTimeout(client.send(request), timeout);

      if (_isRedirect(streamed.statusCode)) {
        // Drain so the underlying connection can be released/reused.
        await streamed.stream.drain<void>();
        final location = streamed.headers['location'];
        if (location == null || location.isEmpty) {
          throw SsrfBlockedException(
            current.toString(),
            'redirect (${streamed.statusCode}) without a Location header',
          );
        }
        current = current.resolveUri(Uri.parse(location));
        continue;
      }

      return _withTimeout(http.Response.fromStream(streamed), timeout);
    }
    throw SsrfBlockedException(
      url.toString(),
      'too many redirects (> $maxRedirects)',
    );
  }

  static Future<T> _withTimeout<T>(Future<T> f, Duration? timeout) =>
      timeout == null ? f : f.timeout(timeout);

  static bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;
}

/// Whether [addr] is NOT a publicly routable address and must be refused:
/// loopback, private, link-local (incl. `169.254.169.254`), ULA, multicast,
/// unspecified, CGNAT, or reserved. IPv4-mapped IPv6 addresses are unwrapped
/// and checked as IPv4.
bool isBlockedAddress(InternetAddress addr) {
  final bytes = addr.rawAddress;
  if (addr.type == InternetAddressType.IPv4) {
    return _isBlockedIPv4(bytes);
  }
  if (bytes.length != 16) {
    // Unknown family — fail closed.
    return true;
  }

  // IPv4-mapped IPv6 (::ffff:a.b.c.d): apply the IPv4 rules to the tail.
  final mappedPrefix = bytes.take(10).every((b) => b == 0);
  if (mappedPrefix && bytes[10] == 0xff && bytes[11] == 0xff) {
    return _isBlockedIPv4(bytes.sublist(12));
  }

  // :: (unspecified) and ::1 (loopback).
  if (bytes.take(15).every((b) => b == 0)) {
    return true;
  }

  final b0 = bytes[0];
  final b1 = bytes[1];
  if (b0 == 0xff) return true; // multicast    ff00::/8
  if (b0 == 0xfe && (b1 & 0xc0) == 0x80) return true; // link-local fe80::/10
  if ((b0 & 0xfe) == 0xfc) return true; // ULA          fc00::/7

  // Backstop against anything dart:io recognizes that we didn't enumerate.
  return addr.isLoopback || addr.isLinkLocal || addr.isMulticast;
}

bool _isBlockedIPv4(List<int> b) {
  final a = b[0];
  final c = b[1];
  if (a == 0) return true; // 0.0.0.0/8      "this host"
  if (a == 10) return true; // 10.0.0.0/8     private
  if (a == 127) return true; // 127.0.0.0/8    loopback
  if (a == 100 && c >= 64 && c <= 127) return true; // 100.64.0.0/10 CGNAT
  if (a == 169 && c == 254) return true; // 169.254.0.0/16 link-local
  if (a == 172 && c >= 16 && c <= 31) return true; // 172.16.0.0/12 private
  if (a == 192 && c == 168) return true; // 192.168.0.0/16 private
  if (a >= 224) return true; // 224.0.0.0/4 multicast, 240.0.0.0/4 + broadcast
  return false;
}
