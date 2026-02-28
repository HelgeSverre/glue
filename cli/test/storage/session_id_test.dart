import 'package:test/test.dart';
import 'package:glue/src/storage/session_id.dart';

void main() {
  group('generateSessionId', () {
    test('returns exactly 12 characters', () {
      final id = generateSessionId();
      expect(id.length, 12);
    });

    test('contains only base-36 characters', () {
      final id = generateSessionId();
      expect(id, matches(RegExp(r'^[0-9a-z]{12}$')));
    });

    test('generates unique IDs across multiple calls', () {
      final ids = List.generate(100, (_) => generateSessionId());
      expect(ids.toSet().length, ids.length);
    });
  });
}
