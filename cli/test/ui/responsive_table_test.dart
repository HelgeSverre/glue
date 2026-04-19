import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/ui/responsive_table.dart';
import 'package:glue/src/ui/table_formatter.dart';
import 'package:test/test.dart';

void main() {
  group('ResponsiveTable', () {
    ResponsiveTable<Map<String, String>> buildTable() => ResponsiveTable(
          columns: const [
            TableColumn(key: 'a', header: 'A'),
            TableColumn(key: 'b', header: 'B'),
          ],
          rows: const [
            {'a': 'alpha', 'b': 'bravo'},
            {'a': 'gamma', 'b': 'delta'},
          ],
          getValues: (row) => row,
        );

    test('renderRow returns wider output at a wider width', () {
      final table = buildTable();
      final wide = table.renderRow(0, 40);
      final narrow = table.renderRow(0, 12);
      expect(stripAnsi(wide).length, greaterThanOrEqualTo(stripAnsi(narrow).length));
    });

    test('renderHeader returns the column headers', () {
      final table = buildTable();
      final headers = table.renderHeader(40);
      expect(headers, isNotEmpty);
      final stripped = headers.map(stripAnsi).join(' ');
      expect(stripped, contains('A'));
      expect(stripped, contains('B'));
    });

    test('includeDivider: false suppresses the divider line', () {
      final table = ResponsiveTable(
        columns: const [TableColumn(key: 'a', header: 'A')],
        rows: const [{'a': 'x'}],
        getValues: (row) => row,
        includeDivider: false,
      );
      final headers = table.renderHeader(10);
      expect(headers.length, 1);
    });

    test('same-width queries reuse the cached TableRender', () {
      final table = buildTable();
      final first = table.renderHeader(40);
      final second = table.renderHeader(40);
      expect(identical(first, second), isTrue);
    });

    test('width change invalidates the cache', () {
      final table = buildTable();
      final wide = table.renderHeader(40);
      final narrow = table.renderHeader(12);
      expect(identical(wide, narrow), isFalse);
    });

    test('rowCount matches input rows', () {
      final table = buildTable();
      expect(table.rowCount, 2);
    });

    test('sourceAt returns original row objects', () {
      final sourceRows = [
        ('sessionA', 'alpha'),
        ('sessionB', 'beta'),
      ];
      final table = ResponsiveTable<(String, String)>(
        columns: const [TableColumn(key: 'id', header: 'ID')],
        rows: sourceRows,
        getValues: (row) => {'id': row.$1},
      );
      expect(table.sourceAt(0), sourceRows[0]);
      expect(table.sourceAt(1), sourceRows[1]);
    });
  });
}
