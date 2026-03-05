import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/ui/table_formatter.dart';
import 'package:test/test.dart';

void main() {
  group('TableFormatter', () {
    test('renders aligned rows with header and divider', () {
      final table = TableFormatter.format(
        columns: const [
          TableColumn(key: 'id', header: 'ID'),
          TableColumn(key: 'name', header: 'NAME'),
          TableColumn(key: 'age', header: 'AGE', align: TableAlign.right),
        ],
        rows: const [
          {'id': '1', 'name': 'Alice', 'age': '9m'},
          {'id': '22', 'name': 'Bob', 'age': '12h'},
        ],
      );

      expect(table.headerLines, hasLength(2));
      expect(table.rowLines, hasLength(2));
      expect(visibleLength(table.headerLines.first),
          visibleLength(table.rowLines.first));
      expect(visibleLength(table.rowLines.first),
          visibleLength(table.rowLines.last));
    });

    test('honors max width with truncation', () {
      final table = TableFormatter.format(
        columns: const [
          TableColumn(key: 'name', header: 'NAME', maxWidth: 6),
        ],
        rows: const [
          {'name': 'a-very-very-long-name'},
        ],
        includeHeader: false,
      );

      expect(table.rowLines, hasLength(1));
      expect(stripAnsi(table.rowLines.first), endsWith('…'));
      expect(visibleLength(table.rowLines.first), lessThanOrEqualTo(6));
    });

    test('fits rows to max total width budget', () {
      final table = TableFormatter.format(
        columns: const [
          TableColumn(key: 'id', header: 'ID', minWidth: 2),
          TableColumn(key: 'name', header: 'NAME', minWidth: 4),
          TableColumn(key: 'path', header: 'PATH', minWidth: 6),
        ],
        rows: const [
          {'id': 's1', 'name': 'session-alpha', 'path': '/very/long/path/here'},
        ],
        gap: ' ',
        maxTotalWidth: 20,
      );

      expect(table.headerLines, isNotEmpty);
      expect(visibleLength(table.headerLines.first), lessThanOrEqualTo(20));
      expect(visibleLength(table.rowLines.first), lessThanOrEqualTo(20));
    });
  });
}
