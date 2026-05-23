// Builds libresqlite into [outputDirectory].
//
// Run from the resqlite package root:
//   dart run tool/build_native.dart --output .dart_tool/lib
//
// Pass --check to exit 1 when the library is missing (for CI).

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final checkOnly = args.contains('--check');
  final outputIndex = args.indexOf('--output');
  if (outputIndex == -1 || outputIndex + 1 >= args.length) {
    stderr.writeln(
      'Usage: dart run tool/build_native.dart --output <directory> [--check]',
    );
    exit(64);
  }

  final outputDirectory = Directory(args[outputIndex + 1]).absolute;
  final packageRoot = Directory.current.absolute;
  final targetOS = OS.current;
  final libraryFileName = targetOS.libraryFileName(
    'resqlite',
    DynamicLoadingBundled(),
  );
  final outputFile = File(p.join(outputDirectory.path, libraryFileName));

  if (checkOnly) {
    if (!outputFile.existsSync()) {
      stderr.writeln(
        '${outputFile.path} is missing. '
        'Run: dart run tool/build_native.dart --output ${outputDirectory.path}',
      );
      exit(1);
    }
    stdout.writeln('${outputFile.path} exists.');
    return;
  }

  if (!outputDirectory.existsSync()) {
    outputDirectory.createSync(recursive: true);
  }

  String? linkerScript;
  if (targetOS == OS.linux) {
    linkerScript = p.join(outputDirectory.path, 'resqlite.map');
    await File(linkerScript).writeAsString('''
{
  global:
${_exportedSymbols.map((s) => '    $s;').join('\n')}
  local:
    *;
};
''');
  }

  final buildInputBuilder = BuildInputBuilder()
    ..setupShared(
      packageName: 'resqlite',
      packageRoot: packageRoot.uri,
      outputFile: packageRoot.uri.resolve('tool/.build_native_output.json'),
      outputDirectoryShared: outputDirectory.uri,
    )
    ..config.setupBuild(linkingEnabled: false)
    ..addExtension(
      CodeAssetExtension(
        targetOS: targetOS,
        macOS: targetOS == OS.macOS
            ? MacOSCodeConfig(targetVersion: 13)
            : null,
        targetArchitecture: Architecture.current,
        linkModePreference: LinkModePreference.dynamic,
      ),
    );

  final buildInput = buildInputBuilder.build();
  final buildOutput = BuildOutputBuilder();
  final logger = Logger.detached('resqlite.build_native')
    ..onRecord.listen((record) {
      final out = record.level >= Level.WARNING ? stderr : stdout;
      out.writeln(record.message);
    });

  final library = CBuilder.library(
    name: 'resqlite',
    packageName: 'resqlite',
    assetName: 'src/native/resqlite_bindings.dart',
    sources: [
      p.join(packageRoot.path, 'third_party', 'sqlite3mc', 'sqlite3mc_amalgamation.c'),
      p.join(packageRoot.path, 'native', 'resqlite_deps.c'),
      p.join(packageRoot.path, 'native', 'resqlite.c'),
    ],
    includes: [
      p.join(packageRoot.path, 'third_party', 'sqlite3mc'),
      p.join(packageRoot.path, 'native'),
    ],
    defines: _defines,
    flags: [
      if (targetOS == OS.linux) ...[
        '-Wl,-Bsymbolic',
        '-Wl,--version-script=$linkerScript',
        '-ffunction-sections',
        '-fdata-sections',
        '-Wl,--gc-sections',
      ],
      if (targetOS case OS.iOS || OS.macOS) ...[
        '-headerpad_max_install_names',
        '-install_name',
        '@rpath/libresqlite.dylib',
      ],
    ],
    libraries: [
      if (targetOS == OS.android) 'm',
    ],
  );

  await library.run(
    input: buildInput,
    output: buildOutput,
    logger: logger,
    routing: const [],
  );

  final builtLib = Directory.fromUri(buildInput.outputDirectory)
      .listSync(recursive: true)
      .whereType<File>()
      .firstWhere(
        (file) => p.basename(file.path) == libraryFileName,
        orElse: () => throw StateError(
          'Build finished but $libraryFileName was not found under '
          '${buildInput.outputDirectory}.',
        ),
      );

  if (builtLib.path != outputFile.path) {
    await builtLib.copy(outputFile.path);
  }

  if (!outputFile.existsSync()) {
    stderr.writeln('Expected output file was not created: ${outputFile.path}');
    exit(1);
  }

  stdout.writeln('Wrote ${outputFile.path}');
}

const _defines = {
  'SQLITE_DQS': '0',
  'SQLITE_DEFAULT_MEMSTATUS': '0',
  'SQLITE_DEFAULT_LOOKASIDE': '1200,128',
  'SQLITE_DEFAULT_PCACHE_INITSZ': '128',
  'SQLITE_TEMP_STORE': '2',
  'SQLITE_MAX_EXPR_DEPTH': '0',
  'SQLITE_USE_ALLOCA': null,
  'SQLITE_LIKE_DOESNT_MATCH_BLOBS': null,
  'SQLITE_DEFAULT_WAL_SYNCHRONOUS': '1',
  'SQLITE_HAVE_ISNAN': null,
  'SQLITE_HAVE_LOCALTIME_R': null,
  'SQLITE_HAVE_LOCALTIME_S': null,
  'SQLITE_HAVE_MALLOC_USABLE_SIZE': null,
  'SQLITE_HAVE_STRCHRNUL': null,
  'SQLITE_UNTESTABLE': null,
  'SQLITE_THREADSAFE': '2',
  'SQLITE_ENABLE_BATCH_ATOMIC_WRITE': null,
  'SQLITE_ENABLE_FTS5': null,
  'SQLITE_ENABLE_MATH_FUNCTIONS': null,
  'SQLITE_ENABLE_PREUPDATE_HOOK': null,
  'SQLITE_ENABLE_STAT4': null,
  'SQLITE_OMIT_AUTOINIT': null,
  'SQLITE_OMIT_COMPLETE': null,
  'SQLITE_OMIT_DECLTYPE': null,
  'SQLITE_OMIT_DEPRECATED': null,
  'SQLITE_OMIT_GET_TABLE': null,
  'SQLITE_OMIT_PROGRESS_CALLBACK': null,
  'SQLITE_OMIT_SHARED_CACHE': null,
  'SQLITE_OMIT_TCL_VARIABLE': null,
  'SQLITE_OMIT_TRACE': null,
  'SQLITE_OMIT_UTF16': null,
};

const _exportedSymbols = [
  'sqlite3_open_v2',
  'sqlite3_close_v2',
  'sqlite3_errmsg',
  'sqlite3_exec',
  'sqlite3_prepare_v2',
  'sqlite3_step',
  'sqlite3_reset',
  'sqlite3_finalize',
  'sqlite3_column_count',
  'sqlite3_column_name',
  'sqlite3_column_type',
  'sqlite3_column_int64',
  'sqlite3_column_double',
  'sqlite3_column_text',
  'sqlite3_column_blob',
  'sqlite3_column_bytes',
  'sqlite3_bind_int64',
  'sqlite3_bind_double',
  'sqlite3_bind_text',
  'sqlite3_bind_blob64',
  'sqlite3_bind_null',
  'sqlite3_bind_parameter_count',
  'sqlite3_changes',
  'sqlite3_last_insert_rowid',
  'sqlite3_sleep',
  'sqlite3_db_handle',
  // SQLite mutex (used by resqlite.c for cross-platform threading)
  'sqlite3_mutex_alloc',
  'sqlite3_mutex_enter',
  'sqlite3_mutex_leave',
  'sqlite3_mutex_free',
  'sqlite3_preupdate_hook',
  'sqlite3_set_authorizer',
  'resqlite_open',
  'resqlite_close',
  'resqlite_errmsg',
  'resqlite_reader_errmsg',
  'resqlite_reader_last_error',
  'resqlite_exec',
  'resqlite_execute',
  'resqlite_tx_begin_immediate',
  'resqlite_tx_commit',
  'resqlite_tx_rollback',
  'resqlite_run_batch',
  'resqlite_run_batch_nested',
  'resqlite_get_dirty_tables',
  'resqlite_get_read_tables',
  'resqlite_get_dirty_columns',
  'resqlite_get_read_columns',
  'resqlite_db_status_total',
  'resqlite_writer_handle',
  'resqlite_stmt_acquire',
  'resqlite_stmt_acquire_on',
  'resqlite_stmt_acquire_writer',
  'resqlite_stmt_release',
  'resqlite_query_bytes',
  'resqlite_effective_column_count',
  'resqlite_column_name',
  'resqlite_read_current_row',
  'resqlite_read_current_row_hash',
  'resqlite_step_row',
  'resqlite_step_row_hash',
  'resqlite_query_hash',
  'resqlite_free',
];
