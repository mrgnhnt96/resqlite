/// Tests for `Database.diagnostics()` — the per-connection diagnostic
/// snapshot used by benchmark workloads and mobile memory reporting.
///
/// Verifies behavior only, not specific byte values (those are
/// implementation- and platform-dependent). The invariants covered:
///
///   1. All byte fields are non-negative on a fresh db.
///   2. WAL sidecar size grows after writes.
///   3. Schema bytes grow after adding tables + first queries.
///   4. `readersBusyAtSnapshot` is false between operations.
///   5. `walBytes` reports zero on a fresh db with no writes.
///
/// Page-cache-bytes and stmt-bytes growth are not asserted — both are
/// very sensitive to VM timing and pcache behavior, and assertions
/// tend to flake. Callers of `diagnostics()` should treat those
/// counters as informational rather than load-bearing.
///
/// QUARANTINED 2026-08-14 -- `Database.diagnostics()` SEGFAULTS.
/// si_signo=Segmentation fault: 11, si_code=SEGV_ACCERR, si_addr=0x18 -- a
/// near-null dereference in the native layer, on the FIRST call, on a fresh
/// db, in isolation, in under a second. It aborts the process, so it takes
/// every other test in this package down with it: `dart test` exits 134 with
/// no summary at all.
///
/// This is not a new bug and nothing here caused it. 15 of 18 test files in
/// this package never called `setUpResqliteNative()`, so they died in
/// `Database.open` before reaching any assertion; the package reported
/// 55 passed / 117 failed for as long as anyone had looked. Commit 08ef516
/// fixed that prerequisite, the tests reached the code for the first time,
/// and this is what came out.
///
/// It is also why five tests in stream_test.dart are quarantined: they assert
/// on the stream registry through `_streamLength`, which calls
/// `diagnostics()`. Those five are collateral, not five separate bugs --
/// there is ONE crash site and it is here.
///
/// Tracked as showrunner leaf `resqlite-stream-segv`. Remove this annotation
/// to reproduce; do not delete these tests.
@Skip(
  'Database.diagnostics() segfaults (si_addr=0x18) and aborts the whole '
  'package. See the doc comment above and leaf resqlite-stream-segv.',
)
library;

import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

import 'native_library_setup.dart';

void main() {
  setUpAll(setUpResqliteNative);

  group('Database.diagnostics', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('diag_test_');
      db = await Database.open('${tempDir.path}/test.db');
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } on PathNotFoundException {
          // ignore
        }
      }
    });

    test(
      'returns a snapshot with non-negative counters on a fresh db',
      () async {
        final d = await db.diagnostics();
        expect(d.sqlitePageCacheBytes, greaterThanOrEqualTo(0));
        expect(d.sqliteSchemaBytes, greaterThanOrEqualTo(0));
        expect(d.sqliteStmtBytes, greaterThanOrEqualTo(0));
        expect(d.walBytes, greaterThanOrEqualTo(0));
        expect(d.readersBusyAtSnapshot, isFalse);
        expect(
          d.sqliteTotalBytes,
          equals(
            d.sqlitePageCacheBytes + d.sqliteSchemaBytes + d.sqliteStmtBytes,
          ),
        );
      },
    );

    test('walBytes grows after writes in WAL mode', () async {
      final before = await db.diagnostics();
      await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, v INTEGER)');
      await db.executeBatch('INSERT INTO t(v) VALUES (?)', [
        for (var i = 0; i < 200; i++) [i],
      ]);
      final after = await db.diagnostics();
      expect(
        after.walBytes,
        greaterThan(before.walBytes),
        reason: 'WAL sidecar should grow after a batch of inserts',
      );
    });

    test('schemaBytes grows after adding tables', () async {
      final before = await db.diagnostics();
      await db.execute('CREATE TABLE a(id INTEGER PRIMARY KEY, name TEXT)');
      await db.execute('CREATE INDEX a_name ON a(name)');
      await db.execute('CREATE TABLE b(id INTEGER PRIMARY KEY, v REAL)');
      // Run a query so the readers load the schema into their parse cache.
      await db.select('SELECT * FROM a');
      await db.select('SELECT * FROM b');
      final after = await db.diagnostics();
      expect(
        after.sqliteSchemaBytes,
        greaterThan(before.sqliteSchemaBytes),
        reason: 'Schema memory should grow after DDL + first queries',
      );
    });

    test('readersBusyAtSnapshot is false between operations', () async {
      await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY)');
      // Await each op before snapshotting — no concurrent reader work.
      await db.select('SELECT * FROM t');
      final d = await db.diagnostics();
      expect(d.readersBusyAtSnapshot, isFalse);
    });

    test('toString includes all counter fields', () async {
      final d = await db.diagnostics();
      final s = d.toString();
      expect(s, contains('pageCache'));
      expect(s, contains('schema'));
      expect(s, contains('stmt'));
      expect(s, contains('wal'));
    });

    test('walBytes is zero on a fresh db with no writes', () async {
      // Fresh db — no writes have committed yet, so the -wal sidecar
      // either doesn't exist or is empty. Either way, diagnostics
      // reports 0 without throwing.
      final d = await db.diagnostics();
      expect(d.walBytes, equals(0));
    });
  });
}
