import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

import 'native_library_setup.dart';

/// Regression for AOT: [ResultSet] must not cross isolates directly.
///
/// Run compiled via `dart test test/aot_result_transfer_test.dart`.
void main() {
  setUpAll(setUpResqliteNative);

  test('select preserves column names and values under AOT', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'resqlite_aot_transfer_',
    );
    final dbPath = '${tempDir.path}/test.db';
    final db = await Database.open(dbPath);
    try {
      await db.execute(
        'CREATE TABLE IF NOT EXISTS _raindrop_migrations '
        '(id INTEGER PRIMARY KEY, tag TEXT NOT NULL UNIQUE, '
        'checksum TEXT NOT NULL, applied_at INTEGER NOT NULL)',
      );
      await db.execute(
        'INSERT INTO _raindrop_migrations (tag, checksum, applied_at) '
        'VALUES (?, ?, ?)',
        ['001_init', 'abc123', 1],
      );

      const q =
          'SELECT "tag", "checksum" FROM "_raindrop_migrations" ORDER BY "id"';
      final rows = await db.select(q);

      expect(rows, isA<ResultSet>());
      expect(rows.length, 1);
      expect(rows.columnNames, ['tag', 'checksum']);
      expect(rows.toPositionalRows(), [
        ['001_init', 'abc123'],
      ]);
      expect(rows.first['tag'], '001_init');
    } finally {
      await db.close();
      await tempDir.delete(recursive: true);
    }
  });
}
