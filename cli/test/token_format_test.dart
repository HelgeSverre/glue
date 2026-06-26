import 'package:glue/src/extensions/token_format.dart';
import 'package:test/test.dart';

void main() {
  group('formatContextGauge', () {
    test('formats used/window with rounded percent', () {
      expect(formatContextGauge(14325, 131072), '14k/131k ctx (11%)');
    });

    test('null window -> null (gauge hidden)', () {
      expect(formatContextGauge(14325, null), isNull);
    });

    test('zero/non-positive window -> null', () {
      expect(formatContextGauge(14325, 0), isNull);
    });

    test('zero used -> null (no turn yet)', () {
      expect(formatContextGauge(0, 131072), isNull);
    });
  });
}
