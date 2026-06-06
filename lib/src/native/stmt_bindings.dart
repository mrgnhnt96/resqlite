import 'dart:ffi';

import 'native_library.dart';

Pointer<Void> resqliteStmtAcquireOn(
  Pointer<Void> db,
  int readerId,
  Pointer<Void> sql,
  Pointer<Uint8> params,
  int paramCount,
  Pointer<Int32> outRc,
) => _resqliteStmtAcquireOn(db, readerId, sql, params, paramCount, outRc);

Pointer<Void> resqliteStmtAcquireWriter(
  Pointer<Void> db,
  Pointer<Void> sql,
  Pointer<Uint8> params,
  int paramCount,
) => _resqliteStmtAcquireWriter(db, sql, params, paramCount);

late final _resqliteStmtAcquireOn = installedNativeLibrary
    .lookupFunction<
      Pointer<Void> Function(
        Pointer<Void>,
        Int,
        Pointer<Void>,
        Pointer<Uint8>,
        Int,
        Pointer<Int32>,
      ),
      Pointer<Void> Function(
        Pointer<Void>,
        int,
        Pointer<Void>,
        Pointer<Uint8>,
        int,
        Pointer<Int32>,
      )
    >('resqlite_stmt_acquire_on');

late final _resqliteStmtAcquireWriter = installedNativeLibrary
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Uint8>, Int),
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Uint8>, int)
    >('resqlite_stmt_acquire_writer');
