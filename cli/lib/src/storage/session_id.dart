import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Generate a 12-character, filesystem-safe, globally unique session ID.
///
/// Derives the ID by hashing the current microsecond timestamp concatenated
/// with 8 cryptographically-random bytes through SHA-256, then base-36
/// encoding the first 8 bytes of the digest.
String generateSessionId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final rng = Random.secure();

  final input = Uint8List(16);
  for (var i = 0; i < 8; i++) {
    input[i] = (now >> (8 * i)) & 0xFF;
  }
  for (var i = 8; i < 16; i++) {
    input[i] = rng.nextInt(256);
  }

  final hash = sha256.convert(input);

  var value = BigInt.zero;
  for (var i = 0; i < 8; i++) {
    value = (value << 8) | BigInt.from(hash.bytes[i]);
  }

  final encoded = value.toRadixString(36);
  return encoded.padLeft(12, '0').substring(0, 12);
}
