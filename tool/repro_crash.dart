import 'dart:io';

import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:resqlite/resqlite.dart' as rs;

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('resqlite_repro_');
  final path = '${dir.path}/test.sqlite';

  final libCandidates = [
    '../../apps/zonai/lib/gen/native/libresqlite.dylib',
    'native/build/libresqlite.dylib',
  ];
  for (final candidate in libCandidates) {
    final file = File(candidate);
    if (file.existsSync()) {
      rs.install(file.absolute.path);
      break;
    }
  }
  if (!rs.isInstalled) {
    stderr.writeln('resqlite native library not found');
    exit(1);
  }

  final delegate = await ResqliteDelegate.open(path);
  final db = Raindrop(delegate);

  try {
    print('SELECT 1 (no params)...');
    final one = await db.execute('SELECT 1');
    print('OK: ${one.rows}');

    print('SELECT ? (param)...');
    final param = await db.execute('SELECT ?', ['hello']);
    print('OK: ${param.rows}');

    print('pragma_table_info(?)...');
    await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)');
    final cols = await db.execute(
      'SELECT name FROM pragma_table_info(?) ORDER BY cid',
      ['t'],
    );
    print('OK: ${cols.rows}');

    print('stream with param...');
    final stream = delegate.streamQuery('SELECT * FROM t WHERE name = ?', [
      'a',
    ]);
    await stream.first;
    print('stream OK');

    print('ALL PASSED');
  } finally {
    await delegate.close();
    dir.deleteSync(recursive: true);
  }
}
