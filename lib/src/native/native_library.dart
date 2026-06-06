import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

DynamicLibrary? _installedLibrary;
String? _installedPath;

// Linux dlopen defaults to RTLD_LOCAL, so @Native fallbacks that use process
// lookup cannot see symbols loaded via DynamicLibrary.open. macOS defaults to
// global visibility; see https://github.com/dart-lang/sdk/issues/50105
const _rtldLazy = 0x00001;
const _rtldGlobalLinux = 0x00100;
const _rtldGlobalAndroidArm = 0x00002;

@Native<Pointer<Void> Function(Pointer<Utf8>, Int)>(symbol: 'dlopen')
external Pointer<Void> _dlopen(Pointer<Utf8> filename, int flag);

bool get _needsExplicitDlopenGlobal =>
    Platform.isLinux || Platform.isAndroid || Platform.isFuchsia;

int get _rtldGlobalFlag =>
    Abi.current() == Abi.androidArm ? _rtldGlobalAndroidArm : _rtldGlobalLinux;

/// Loads the resqlite native library from [path] so [@Native] bindings can
/// resolve symbols via process lookup.
///
/// Must be called once before any resqlite FFI use when native assets are not
/// bundled (for example `dart compile exe` without build hooks).
void install(String path) {
  final absolute = File(path).absolute.path;
  if (_installedPath == absolute && _installedLibrary != null) {
    return;
  }

  if (_needsExplicitDlopenGlobal) {
    using((arena) {
      final handle = _dlopen(
        absolute.toNativeUtf8(allocator: arena),
        _rtldLazy | _rtldGlobalFlag,
      );
      if (handle == nullptr) {
        throw ArgumentError(
          'Failed to dlopen resqlite library at $absolute with RTLD_GLOBAL',
        );
      }
    });
  }

  _installedLibrary = DynamicLibrary.open(absolute);
  _installedPath = absolute;
}

/// Whether [install] has been called successfully.
bool get isInstalled => _installedLibrary != null;

/// The library loaded by [install], for dynamic symbol lookup.
DynamicLibrary get installedNativeLibrary {
  final lib = _installedLibrary;
  if (lib == null) {
    throw StateError('resqlite native library not installed');
  }
  return lib;
}

/// Error message from a reader connection ([readerId] from the worker).
String readerErrmsg(Pointer<Void> dbHandle, int readerId) {
  return installedNativeLibrary
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Int),
        Pointer<Utf8> Function(Pointer<Void>, int)
      >('resqlite_reader_errmsg')(dbHandle, readerId)
      .toDartString();
}

int readerLastError(Pointer<Void> dbHandle, int readerId) {
  return installedNativeLibrary.lookupFunction<
    Int Function(Pointer<Void>, Int),
    int Function(Pointer<Void>, int)
  >('resqlite_reader_last_error')(dbHandle, readerId);
}

/// Absolute path passed to the last successful [install], if any.
String? get installedLibraryPath => _installedPath;

/// Platform-specific shared library file name for resqlite.
String get defaultLibraryFileName => switch (Platform.operatingSystem) {
  'macos' => 'libresqlite.dylib',
  'linux' => 'libresqlite.so',
  'windows' => 'resqlite.dll',
  _ => throw UnsupportedError(
    'Unsupported platform for resqlite: ${Platform.operatingSystem}',
  ),
};
