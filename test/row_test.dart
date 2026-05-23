import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

void main() {
  group('ResultSet', () {
    test('toPositionalRows slices flat values when schema names are empty', () {
      final resultSet = ResultSet(
        ['001_init', 'abc123', '002_add', 'def456'],
        RowSchema(const []),
        2,
      );

      expect(resultSet.columnNames, isEmpty);
      expect(resultSet.toPositionalRows(), [
        ['001_init', 'abc123'],
        ['002_add', 'def456'],
      ]);
      expect(resultSet.first.values, ['001_init', 'abc123']);
    });

    test('toPositionalRows uses schema column count when present', () {
      final resultSet = ResultSet(
        ['a', 1, 'b', 2],
        RowSchema(const ['name', 'id']),
        2,
      );

      expect(resultSet.columnNames, ['name', 'id']);
      expect(resultSet.toPositionalRows(), [
        ['a', 1],
        ['b', 2],
      ]);
      expect(resultSet.first['name'], 'a');
    });

    test('resultSetFromMaterializedRows rebuilds lazy rows', () {
      final resultSet = resultSetFromMaterializedRows(const [
        {'tag': '001_init', 'checksum': 'abc123'},
      ]);

      expect(resultSet.columnNames, ['tag', 'checksum']);
      expect(resultSet.toPositionalRows(), [
        ['001_init', 'abc123'],
      ]);
    });
  });
}
