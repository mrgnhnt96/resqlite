import 'dart:ffi';
import 'dart:io';

DynamicLibrary? _installedLibrary;
String? _installedPath;

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

  _installedLibrary = DynamicLibrary.open(absolute);
  _installedPath = absolute;
}

/// Whether [install] has been called successfully.
bool get isInstalled => _installedLibrary != null;

/// Platform-specific shared library file name for resqlite.
String get defaultLibraryFileName => switch (Platform.operatingSystem) {
  'macos' => 'libresqlite.dylib',
  'linux' => 'libresqlite.so',
  'windows' => 'resqlite.dll',
  _ => throw UnsupportedError(
    'Unsupported platform for resqlite: ${Platform.operatingSystem}',
  ),
};
