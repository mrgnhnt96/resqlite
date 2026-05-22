import 'dart:io';

import 'package:resqlite/resqlite.dart';

/// Loads the resqlite shared library for tests and local development.
void setUpResqliteNative() {
  if (isInstalled) return;

  final libName = defaultLibraryFileName;
  final packageRoot = Directory.current.absolute.path;
  final candidates = [
    Platform.environment['RESQLITE_LIB'],
    '$packageRoot/.dart_tool/lib/$libName',
    '$packageRoot/../../apps/zonai/lib/gen/native/$libName',
  ];

  for (final candidate in candidates) {
    if (candidate == null) continue;
    final file = File(candidate);
    if (file.existsSync()) {
      install(file.absolute.path);
      return;
    }
  }

  throw StateError(
    'Resqlite native library not found.\n'
    'Run: cd libs/resqlite && dart run tool/build_native.dart --output .dart_tool/lib',
  );
}
