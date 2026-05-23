import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

import 'native_library_setup.dart';

void main() {
  setUpAll(setUpResqliteNative);

  test('reader prepare failure uses reader sqlite error message', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'resqlite_reader_err_',
    );
    final db = await Database.open('${tempDir.path}/test.db');
    try {
      await expectLater(
        () => db.select('SELECT * FROM definitely_missing_table_xyz'),
        throwsA(
          isA<ResqliteQueryException>()
              .having((e) => e.message, 'message', isNot('not an error'))
              .having((e) => e.message, 'message', contains('no such table')),
        ),
      );
    } finally {
      await db.close();
      await tempDir.delete(recursive: true);
    }
  });

  test('reader bind failure uses reader sqlite error message', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'resqlite_reader_err_',
    );
    final db = await Database.open('${tempDir.path}/test.db');
    try {
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      await expectLater(
        () => db.select('SELECT * FROM t WHERE id = ?', [1, 2]),
        throwsA(
          isA<ResqliteQueryException>()
              .having((e) => e.message, 'message', isNot('not an error'))
              .having(
                (e) => e.message,
                'message',
                contains('column index out of range'),
              ),
        ),
      );
    } finally {
      await db.close();
      await tempDir.delete(recursive: true);
    }
  });
}
