import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'native_library.dart';

/// Decode-path FFI via [installedNativeLibrary] — reliable in worker isolates
/// after [install], unlike [@Native] in isolate entrypoint libraries.

int sqlite3ColumnCount(Pointer<Void> stmt) => _sqlite3ColumnCount(stmt);

int resqliteEffectiveColumnCount(Pointer<Void> stmt) =>
    _resqliteEffectiveColumnCount(stmt);

Pointer<Utf8> resqliteColumnName(Pointer<Void> stmt, int n) =>
    _resqliteColumnName(stmt, n);

int resqliteStepRow(Pointer<Void> stmt, int colCount, Pointer<Uint8> cells) =>
    _resqliteStepRow(stmt, colCount, cells);

int resqliteReadCurrentRow(
  Pointer<Void> stmt,
  int colCount,
  Pointer<Uint8> cells,
) => _resqliteReadCurrentRow(stmt, colCount, cells);

int resqliteReadCurrentRowHash(
  Pointer<Void> stmt,
  int colCount,
  Pointer<Uint8> cells,
  Pointer<Uint64> hash,
) => _resqliteReadCurrentRowHash(stmt, colCount, cells, hash);

int resqliteStepRowHash(
  Pointer<Void> stmt,
  int colCount,
  Pointer<Uint8> cells,
  Pointer<Uint64> hash,
) => _resqliteStepRowHash(stmt, colCount, cells, hash);

int resqliteQueryHash(
  Pointer<Void> stmt,
  int lastRowCount,
  Pointer<Int> outRowCount,
) => _resqliteQueryHash(stmt, lastRowCount, outRowCount);

Pointer<Void> sqlite3DbHandle(Pointer<Void> stmt) => _sqlite3DbHandle(stmt);

Pointer<Utf8> sqlite3Errmsg(Pointer<Void> db) => _sqlite3Errmsg(db);

int cStrlen(Pointer<Void> s) => _cStrlen(s);

late final _sqlite3ColumnCount = installedNativeLibrary
    .lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'sqlite3_column_count',
    );

late final _resqliteEffectiveColumnCount = installedNativeLibrary
    .lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'resqlite_effective_column_count',
    );

late final _resqliteColumnName = installedNativeLibrary
    .lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Int),
      Pointer<Utf8> Function(Pointer<Void>, int)
    >('resqlite_column_name');

late final _resqliteStepRow = installedNativeLibrary
    .lookupFunction<
      Int Function(Pointer<Void>, Int, Pointer<Uint8>),
      int Function(Pointer<Void>, int, Pointer<Uint8>)
    >('resqlite_step_row');

late final _resqliteReadCurrentRow = installedNativeLibrary
    .lookupFunction<
      Int Function(Pointer<Void>, Int, Pointer<Uint8>),
      int Function(Pointer<Void>, int, Pointer<Uint8>)
    >('resqlite_read_current_row');

late final _resqliteReadCurrentRowHash = installedNativeLibrary
    .lookupFunction<
      Int Function(Pointer<Void>, Int, Pointer<Uint8>, Pointer<Uint64>),
      int Function(Pointer<Void>, int, Pointer<Uint8>, Pointer<Uint64>)
    >('resqlite_read_current_row_hash');

late final _resqliteStepRowHash = installedNativeLibrary
    .lookupFunction<
      Int Function(Pointer<Void>, Int, Pointer<Uint8>, Pointer<Uint64>),
      int Function(Pointer<Void>, int, Pointer<Uint8>, Pointer<Uint64>)
    >('resqlite_step_row_hash');

late final _resqliteQueryHash = installedNativeLibrary
    .lookupFunction<
      Int64 Function(Pointer<Void>, Int, Pointer<Int>),
      int Function(Pointer<Void>, int, Pointer<Int>)
    >('resqlite_query_hash');

late final _sqlite3DbHandle = installedNativeLibrary
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)
    >('sqlite3_db_handle');

late final _sqlite3Errmsg = installedNativeLibrary
    .lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>),
      Pointer<Utf8> Function(Pointer<Void>)
    >('sqlite3_errmsg');

late final _cStrlen = installedNativeLibrary
    .lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'strlen',
    );
