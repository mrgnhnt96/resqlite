// Builds libresqlite into [outputDirectory].
//
// Run from the resqlite package root:
//   dart run tool/build_native.dart --output .dart_tool/lib
//
// Pass --check to exit 1 when the library is missing (for CI).

import 'dart:ffi';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final checkOnly = args.contains('--check');
  final outputIndex = args.indexOf('--output');
  final archIndex = args.indexOf('--arch');
  if (outputIndex == -1 || outputIndex + 1 >= args.length) {
    stderr.writeln(
      'Usage: dart run tool/build_native.dart --output <directory> '
      '[--arch <architecture>] [--check]',
    );
    exit(64);
  }

  final outputDirectory = Directory(args[outputIndex + 1]).absolute;
  final packageRoot = Directory.current.absolute;
  final targetOS = OS.current;
  final targetArchitecture = archIndex == -1 || archIndex + 1 >= args.length
      ? Architecture.current
      : Architecture.fromString(args[archIndex + 1]);
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
        macOS: targetOS == OS.macOS ? MacOSCodeConfig(targetVersion: 13) : null,
        targetArchitecture: targetArchitecture,
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
    // Linux needs gnu11 for POSIX helpers like strdup; Windows needs c17 for
    // MSVC <stdatomic.h> support used by resqlite.c.
    std: switch (targetOS) {
      OS.linux => 'gnu11',
      OS.windows => 'c17',
      _ => 'c11',
    },
    assetName: 'src/native/resqlite_bindings.dart',
    sources: [
      p.join(
        packageRoot.path,
        'third_party',
        'sqlite3mc',
        'sqlite3mc_amalgamation.c',
      ),
      p.join(packageRoot.path, 'native', 'resqlite_deps.c'),
      p.join(packageRoot.path, 'native', 'resqlite.c'),
    ],
    includes: [
      p.join(packageRoot.path, 'third_party', 'sqlite3mc'),
      p.join(packageRoot.path, 'native'),
    ],
    // Windows: force-include so sqlite3mc_amalgamation.c sees
    // SQLITE_API=__declspec(dllexport). Do NOT pass /DEF: via [flags] —
    // CBuilder.flags are compiler flags, and MSVC parses `/DEF:path` as
    // `/D EF:path` (warning C5102), silently dropping the module-definition
    // file. resqlite_* already export via RESQLITE_API in resqlite.h.
    forcedIncludes: [
      if (targetOS == OS.windows)
        p.join(packageRoot.path, 'native', 'windows_sqlite_api.h'),
    ],
    defines: _defines,
    flags: [
      if (targetOS == OS.windows) ...[
        // MSVC requires this alongside /std:c17 for <stdatomic.h> in resqlite.c.
        '/experimental:c11atomics',
      ],
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
    libraries: [if (targetOS == OS.android) 'm'],
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

  _assertRequiredExports(outputFile);
  stdout.writeln('Wrote ${outputFile.path}');
}

/// Symbols package:sqlite3 and resqlite FFI bindings need at process start.
///
/// Kept small on purpose: the full [_exportedSymbols] list includes optional
/// SQLite APIs (e.g. column metadata) that are not compiled into this build.
/// Looking those up would false-fail a correct library. These canaries are the
/// ones that failed in CI when Windows exports were silently dropped.
void _assertRequiredExports(File libraryFile) {
  const required = [
    'sqlite3_libversion_number',
    'sqlite3_open_v2',
    'sqlite3_initialize',
    'resqlite_open',
  ];

  final lib = DynamicLibrary.open(libraryFile.path);
  final missing = <String>[
    for (final symbol in required)
      if (!lib.providesSymbol(symbol)) symbol,
  ];

  if (missing.isEmpty) {
    stdout.writeln(
      'Verified required exports in ${p.basename(libraryFile.path)}: '
      '${required.join(', ')}',
    );
    return;
  }

  stderr.writeln(
    '${libraryFile.path} is missing required exported symbol(s): '
    '${missing.join(', ')}.\n'
    'On Windows this usually means SQLITE_API was not __declspec(dllexport) '
    'when compiling sqlite3mc_amalgamation.c (see native/windows_sqlite_api.h).',
  );
  exit(1);
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
  // Do NOT set SQLITE_ENABLE_UPDATE_DELETE_LIMIT here. The sqlite3mc
  // amalgamation's lemon parser was generated without that feature; defining
  // the flag at C compile time only flips compileoption_used — DELETE/UPDATE
  // … LIMIT still syntax-errors. Zonai rewrites limited deletes to
  // `WHERE pk IN (SELECT pk … LIMIT n)` instead (see TableOperations.delete).
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
  // Everything below is unused by resqlite.c itself but is required so
  // package:sqlite3 can be pointed at this library instead of dlopen-ing a
  // second, separately-built libsqlite3 -- see raindrop_sqlite's
  // `ResqliteDelegate.open` for why running two different SQLite builds
  // against the same connection/file in one process is unsafe (confirmed:
  // 100%-reproducible segfault, not a race). package:sqlite3's `NativeLibrary`
  // binds this exact symbol set eagerly on construction, so all of them must
  // be visible even though a given app may only call a subset. All of these
  // are standard SQLite C API functions already implemented by
  // sqlite3mc_amalgamation.c -- this list only controls *visibility*, not
  // what gets compiled.
  'sqlite3_aggregate_context',
  'sqlite3_auto_extension',
  'sqlite3_backup_finish',
  'sqlite3_backup_init',
  'sqlite3_backup_pagecount',
  'sqlite3_backup_remaining',
  'sqlite3_backup_step',
  'sqlite3_bind_parameter_index',
  'sqlite3_column_table_name',
  'sqlite3_commit_hook',
  'sqlite3_compileoption_get',
  'sqlite3_create_collation_v2',
  'sqlite3_create_function_v2',
  'sqlite3_create_window_function',
  'sqlite3_db_config',
  'sqlite3_db_filename',
  'sqlite3_error_offset',
  'sqlite3_errstr',
  'sqlite3_extended_errcode',
  'sqlite3_extended_result_codes',
  'sqlite3_free',
  'sqlite3_get_autocommit',
  'sqlite3_initialize',
  'sqlite3_libversion',
  'sqlite3_libversion_number',
  'sqlite3_prepare_v3',
  'sqlite3_result_blob64',
  'sqlite3_result_double',
  'sqlite3_result_error',
  'sqlite3_result_int64',
  'sqlite3_result_null',
  'sqlite3_result_subtype',
  'sqlite3_result_text',
  'sqlite3_rollback_hook',
  'sqlite3_sourceid',
  'sqlite3_stmt_isexplain',
  'sqlite3_stmt_readonly',
  'sqlite3_temp_directory',
  'sqlite3_update_hook',
  'sqlite3_user_data',
  'sqlite3_value_blob',
  'sqlite3_value_bytes',
  'sqlite3_value_double',
  'sqlite3_value_int64',
  'sqlite3_value_subtype',
  'sqlite3_value_text',
  'sqlite3_value_type',
  'sqlite3_vfs_register',
  'sqlite3_vfs_unregister',
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
