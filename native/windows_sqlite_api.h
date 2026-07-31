// Forced-include for Windows builds of sqlite3mc_amalgamation.c.
//
// resqlite.h sets SQLITE_API=__declspec(dllexport), but the amalgamation is
// compiled as its own TU and never includes that header -- so without this,
// SQLITE_API stays empty and MSVC does not export any sqlite3_* symbols from
// resqlite.dll. package:sqlite3 then fails looking up sqlite3_libversion_number
// when pointed at this library (see raindrop_sqlite's ResqliteDelegate.open).
//
// Must be forced-included (via /FI) before the amalgamation's own
// `#ifndef SQLITE_API` default kicks in.

#ifndef SQLITE_API
#define SQLITE_API __declspec(dllexport)
#endif
