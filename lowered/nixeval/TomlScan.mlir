// builtins.fromTOML's scan, hollowed out of lib/Eval/Formats.cpp (the old TomlParser): the whole lexical and syntactic
// machine of the document is here -- whitespace, comments and newlines with the line count; keys (bare, quoted basic and
// literal, dotted); the [a.b] and [[a.b]] headers; values: basic, literal and multi-line strings with every escape
// (\uXXXX / \UXXXXXXXX into UTF-8), integers (decimal, 0x / 0o / 0b, underscores, sign, range), floats (inf / nan,
// exponent, underscores; the text is read by libc strtod in the C locale, as before), booleans, dates and times (the
// detection and the normal form: 'T', fractions padded to 3 / 6 / 9 digits, 'Z'), arrays and inline tables nested on an
// explicit stack (no recursion).  The table semantics (dotted-key tables, header navigation, array-of-tables, duplicate
// keys and redefinitions) are TomlTables.mlir's, fed by this scan's events IN ORDER through nixev_toml_ev, so an error
// the bridge finds is still reported before a lexical error later in the text.  The scan stops at its first error and
// returns its code; nixev_ts_toml_msg composes every message ("while parsing TOML: ... (line N)") as one trikeshed
// combine drained once, for the scan's codes and the bridge's three (29 cannot redefine, 30 duplicate, 31 table defined).
//
// nixev_ts_toml_scan(rec) reads and writes the record the bridge owns (i64 words; ptr fields at 0, 2, 3, 4, 9, 12):
//   0 src, 1 n, 2 ctx (the bridge's builder, for the callback), 3 stack (u8 per nesting level: 1 array, 2 inline
//   table; room n + 1), 4 dec (decoded bytes: basic strings, dates, number scratch; room 2 n + 16), 5 p, 6 line,
//   7 sp, 8 dp (bytes used in dec), 9 / 10 the window an error names (ptr, len), 12 / 13 a value's window, 14 / 15 a
//   number's kind (2 int, 3 float) and bits.
// It returns 0 when the document was read, else the error code (line in word 6).
// Events nixev_toml_ev(ctx, kind, ptr, a, line): 0 key part (ptr, len), 1 string (ptr, len), 2 int a, 3 float bits a,
// 4 bool a, 5 date (ptr, len), 6 array begins, 7 array ends, 8 inline table begins, 9 inline table ends, 10 header
// (a = 1 for [[...]]); the line is the line when the value or header was complete.
//
// Lowered by lib/CMakeLists.txt's mlnix_lower_trikeshed (its cf loops lifted to scf first) into NixEval.
!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// byte classes: bare-key characters (alnum _ -), number-token characters (alnum _ + - .), date characters (digit - :),
// time characters (digit :), digits, digit values (0-9, a-z / A-Z 10-35, else 99), simple escapes (the byte, else 0)
llvm.mlir.global internal constant @tm_bare(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @tm_tok(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @tm_dt1(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @tm_dt2(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @tm_digit(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @tm_alnum(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @tm_dval(dense<[99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 99, 99, 99, 99, 99, 99, 99, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 99, 99, 99, 99, 99, 99, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @tm_esc(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 34, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 92, 0, 0, 0, 0, 0, 8, 0, 0, 27, 12, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 13, 0, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>

func.func private @nixev_toml_ev(!llvm.ptr, i64, !llvm.ptr, i64, i64)
func.func private @strtod(!llvm.ptr, !llvm.ptr) -> f64

// ---- the record ----
func.func private @tm_rd(%s: !llvm.ptr, %k: i64) -> i64 {
  %q = llvm.getelementptr %s[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %q : !llvm.ptr -> i64
  return %v : i64
}
func.func private @tm_wr(%s: !llvm.ptr, %k: i64, %v: i64) {
  %q = llvm.getelementptr %s[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %q : i64, !llvm.ptr
  return
}
func.func private @tm_rp(%s: !llvm.ptr, %k: i64) -> !llvm.ptr {
  %q = llvm.getelementptr %s[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %q : !llvm.ptr -> !llvm.ptr
  return %v : !llvm.ptr
}
func.func private @tm_wp(%s: !llvm.ptr, %k: i64, %v: !llvm.ptr) {
  %q = llvm.getelementptr %s[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %q : !llvm.ptr, !llvm.ptr
  return
}
func.func private @tm_ld(%p: !llvm.ptr, %i: i64) -> i8 {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %v = llvm.load %q : !llvm.ptr -> i8
  return %v : i8
}
func.func private @tm_st(%p: !llvm.ptr, %i: i64, %v: i8) {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %v, %q : i8, !llvm.ptr
  return
}
func.func private @tm_off(%p: !llvm.ptr, %i: i64) -> !llvm.ptr {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  return %q : !llvm.ptr
}
// a byte's entry in a 256-byte class table
func.func private @tm_cv(%t: !llvm.ptr, %c: i8) -> i8 {
  %i = arith.extui %c : i8 to i64
  %v = func.call @tm_ld(%t, %i) : (!llvm.ptr, i64) -> i8
  return %v : i8
}
func.func private @tm_is(%t: !llvm.ptr, %c: i8) -> i1 {
  %v = func.call @tm_cv(%t, %c) : (!llvm.ptr, i8) -> i8
  %z = arith.constant 0 : i8
  %r = arith.cmpi ne, %v, %z : i8
  return %r : i1
}
func.func private @tm_p(%s: !llvm.ptr) -> i64 {
  %k = arith.constant 5 : i64
  %v = func.call @tm_rd(%s, %k) : (!llvm.ptr, i64) -> i64
  return %v : i64
}
func.func private @tm_setp(%s: !llvm.ptr, %v: i64) {
  %k = arith.constant 5 : i64
  func.call @tm_wr(%s, %k, %v) : (!llvm.ptr, i64, i64) -> ()
  return
}
func.func private @tm_adv(%s: !llvm.ptr, %d: i64) {
  %p = func.call @tm_p(%s) : (!llvm.ptr) -> i64
  %q = arith.addi %p, %d : i64
  func.call @tm_setp(%s, %q) : (!llvm.ptr, i64) -> ()
  return
}
func.func private @tm_nl(%s: !llvm.ptr) {
  %k = arith.constant 6 : i64
  %one = arith.constant 1 : i64
  %l = func.call @tm_rd(%s, %k) : (!llvm.ptr, i64) -> i64
  %m = arith.addi %l, %one : i64
  func.call @tm_wr(%s, %k, %m) : (!llvm.ptr, i64, i64) -> ()
  return
}
// the byte at i, 0 past the end
func.func private @tm_at(%s: !llvm.ptr, %i: i64) -> i8 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %src = func.call @tm_rp(%s, %k0) : (!llvm.ptr, i64) -> !llvm.ptr
  %n = func.call @tm_rd(%s, %k1) : (!llvm.ptr, i64) -> i64
  %in = arith.cmpi ult, %i, %n : i64
  %z = arith.constant 0 : i8
  %c = scf.if %in -> (i8) {
    %b = func.call @tm_ld(%src, %i) : (!llvm.ptr, i64) -> i8
    scf.yield %b : i8
  } else {
    scf.yield %z : i8
  }
  return %c : i8
}
// the byte at p + o, 0 past the end
func.func private @tm_peek(%s: !llvm.ptr, %o: i64) -> i8 {
  %p = func.call @tm_p(%s) : (!llvm.ptr) -> i64
  %i = arith.addi %p, %o : i64
  %c = func.call @tm_at(%s, %i) : (!llvm.ptr, i64) -> i8
  return %c : i8
}
func.func private @tm_pk(%s: !llvm.ptr, %o: i64, %b: i8) -> i1 {
  %c = func.call @tm_peek(%s, %o) : (!llvm.ptr, i64) -> i8
  %r = arith.cmpi eq, %c, %b : i8
  return %r : i1
}
func.func private @tm_eof(%s: !llvm.ptr) -> i1 {
  %k1 = arith.constant 1 : i64
  %n = func.call @tm_rd(%s, %k1) : (!llvm.ptr, i64) -> i64
  %p = func.call @tm_p(%s) : (!llvm.ptr) -> i64
  %r = arith.cmpi sge, %p, %n : i64
  return %r : i1
}
// three bytes b at p (s.substr(p, 3) == bbb)
func.func private @tm_triple(%s: !llvm.ptr, %b: i8) -> i1 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k2 = arith.constant 2 : i64
  %a0 = func.call @tm_pk(%s, %k0, %b) : (!llvm.ptr, i64, i8) -> i1
  %a1 = func.call @tm_pk(%s, %k1, %b) : (!llvm.ptr, i64, i8) -> i1
  %a2 = func.call @tm_pk(%s, %k2, %b) : (!llvm.ptr, i64, i8) -> i1
  %x = arith.andi %a0, %a1 : i1
  %r = arith.andi %x, %a2 : i1
  return %r : i1
}
// a decoded byte appended (dec[dp++])
func.func private @tm_put(%s: !llvm.ptr, %c: i8) {
  %k4 = arith.constant 4 : i64
  %k8 = arith.constant 8 : i64
  %one = arith.constant 1 : i64
  %dec = func.call @tm_rp(%s, %k4) : (!llvm.ptr, i64) -> !llvm.ptr
  %dp = func.call @tm_rd(%s, %k8) : (!llvm.ptr, i64) -> i64
  func.call @tm_st(%dec, %dp, %c) : (!llvm.ptr, i64, i8) -> ()
  %dq = arith.addi %dp, %one : i64
  func.call @tm_wr(%s, %k8, %dq) : (!llvm.ptr, i64, i64) -> ()
  return
}
// the value window (words 12, 13)
func.func private @tm_setv(%s: !llvm.ptr, %p: !llvm.ptr, %n: i64) {
  %k12 = arith.constant 12 : i64
  %k13 = arith.constant 13 : i64
  func.call @tm_wp(%s, %k12, %p) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @tm_wr(%s, %k13, %n) : (!llvm.ptr, i64, i64) -> ()
  return
}
// the window an error names (words 9, 10)
func.func private @tm_setw(%s: !llvm.ptr, %p: !llvm.ptr, %n: i64) {
  %k9 = arith.constant 9 : i64
  %k10 = arith.constant 10 : i64
  func.call @tm_wp(%s, %k9, %p) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @tm_wr(%s, %k10, %n) : (!llvm.ptr, i64, i64) -> ()
  return
}
// an event to the bridge, with the current line
func.func private @tm_ev(%s: !llvm.ptr, %kind: i64, %p: !llvm.ptr, %a: i64) {
  %k2 = arith.constant 2 : i64
  %k6 = arith.constant 6 : i64
  %ctx = func.call @tm_rp(%s, %k2) : (!llvm.ptr, i64) -> !llvm.ptr
  %line = func.call @tm_rd(%s, %k6) : (!llvm.ptr, i64) -> i64
  func.call @nixev_toml_ev(%ctx, %kind, %p, %a, %line) : (!llvm.ptr, i64, !llvm.ptr, i64, i64) -> ()
  return
}
func.func private @tm_ev0(%s: !llvm.ptr, %kind: i64, %a: i64) {
  %c0 = arith.constant 0 : i64
  %np = llvm.inttoptr %c0 : i64 to !llvm.ptr
  func.call @tm_ev(%s, %kind, %np, %a) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  return
}
// the nesting stack (word 3, sp word 7): 1 array, 2 inline table; 0 when at the document level
func.func private @tm_push(%s: !llvm.ptr, %v: i8) {
  %k3 = arith.constant 3 : i64
  %k7 = arith.constant 7 : i64
  %one = arith.constant 1 : i64
  %st = func.call @tm_rp(%s, %k3) : (!llvm.ptr, i64) -> !llvm.ptr
  %sp = func.call @tm_rd(%s, %k7) : (!llvm.ptr, i64) -> i64
  func.call @tm_st(%st, %sp, %v) : (!llvm.ptr, i64, i8) -> ()
  %sq = arith.addi %sp, %one : i64
  func.call @tm_wr(%s, %k7, %sq) : (!llvm.ptr, i64, i64) -> ()
  return
}
func.func private @tm_pop(%s: !llvm.ptr) {
  %k7 = arith.constant 7 : i64
  %one = arith.constant 1 : i64
  %sp = func.call @tm_rd(%s, %k7) : (!llvm.ptr, i64) -> i64
  %sq = arith.subi %sp, %one : i64
  func.call @tm_wr(%s, %k7, %sq) : (!llvm.ptr, i64, i64) -> ()
  return
}
func.func private @tm_top(%s: !llvm.ptr) -> i8 {
  %k3 = arith.constant 3 : i64
  %k7 = arith.constant 7 : i64
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %z8 = arith.constant 0 : i8
  %sp = func.call @tm_rd(%s, %k7) : (!llvm.ptr, i64) -> i64
  %empty = arith.cmpi eq, %sp, %z : i64
  %r = scf.if %empty -> (i8) {
    scf.yield %z8 : i8
  } else {
    %st = func.call @tm_rp(%s, %k3) : (!llvm.ptr, i64) -> !llvm.ptr
    %i = arith.subi %sp, %one : i64
    %v = func.call @tm_ld(%st, %i) : (!llvm.ptr, i64) -> i8
    scf.yield %v : i8
  }
  return %r : i8
}

// whether the window holds byte c: a fold over its byte series
func.func private @tm_has(%p: !llvm.ptr, %n: i64, %c: i8) -> i1 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %u = llvm.mlir.undef : !d
  %a = llvm.insertvalue %p, %u[0] : !d
  %b = llvm.insertvalue %p, %a[1] : !d
  %e = llvm.insertvalue %c0, %b[2] : !d
  %f = llvm.insertvalue %n, %e[3, 0] : !d
  %g = llvm.insertvalue %c1, %f[4, 0] : !d
  %mm = builtin.unrealized_conversion_cast %g : !d to !m8
  %xs = builtin.unrealized_conversion_cast %mm : !m8 to !text
  %no = arith.constant 0 : i1
  %r = trikeshed.fold %xs, %no : !text, i1 -> i1 {
  ^bb0(%acc: i1, %x: i8):
    %hit = arith.cmpi eq, %x, %c : i8
    %rr = arith.ori %acc, %hit : i1
    trikeshed.yield %rr : i1
  }
  return %r : i1
}

// ---- whitespace, comments, newlines ----
func.func private @tm_wsinline(%s: !llvm.ptr) {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %sp = arith.constant 32 : i8
  %tab = arith.constant 9 : i8
  %u = arith.constant 0 : i1
  %r = scf.while (%x = %u) : (i1) -> i1 {
    %c = func.call @tm_peek(%s, %k0) : (!llvm.ptr, i64) -> i8
    %a = arith.cmpi eq, %c, %sp : i8
    %b = arith.cmpi eq, %c, %tab : i8
    %go = arith.ori %a, %b : i1
    scf.condition(%go) %go : i1
  } do {
  ^bb0(%y: i1):
    func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
    scf.yield %y : i1
  }
  return
}
// a # comment's text up to its newline; 1 on a control character in it
func.func private @tm_comment(%s: !llvm.ptr) -> i32 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %hash = arith.constant 35 : i8
  %nl = arith.constant 10 : i8
  %cr = arith.constant 13 : i8
  %tab = arith.constant 9 : i8
  %sp = arith.constant 32 : i8
  %z = arith.constant 0 : i32
  %e1 = arith.constant 1 : i32
  %isc = func.call @tm_pk(%s, %k0, %hash) : (!llvm.ptr, i64, i8) -> i1
  %r = scf.if %isc -> (i32) {
    %w = scf.while (%st = %z) : (i32) -> i32 {
      %c = func.call @tm_peek(%s, %k0) : (!llvm.ptr, i64) -> i8
      %eof = func.call @tm_eof(%s) : (!llvm.ptr) -> i1
      %t = arith.constant 1 : i1
      %ne = arith.xori %eof, %t : i1
      %notnl = arith.cmpi ne, %c, %nl : i8
      %more = arith.andi %ne, %notnl : i1
      %low = arith.cmpi ult, %c, %sp : i8
      %ntab = arith.cmpi ne, %c, %tab : i8
      %ncr = arith.cmpi ne, %c, %cr : i8
      %b1 = arith.andi %low, %ntab : i1
      %bad = arith.andi %b1, %ncr : i1
      %stop = arith.andi %more, %bad : i1
      %res = arith.select %stop, %e1, %z : i32
      %nb = arith.xori %bad, %t : i1
      %go = arith.andi %more, %nb : i1
      scf.condition(%go) %res : i32
    } do {
    ^bb0(%y: i32):
      func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
      scf.yield %y : i32
    }
    scf.yield %w : i32
  } else {
    scf.yield %z : i32
  }
  return %r : i32
}
// one newline (\r\n or \n), counted
func.func private @tm_newline(%s: !llvm.ptr) {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k2 = arith.constant 2 : i64
  %nl = arith.constant 10 : i8
  %cr = arith.constant 13 : i8
  %a = func.call @tm_pk(%s, %k0, %cr) : (!llvm.ptr, i64, i8) -> i1
  %b = func.call @tm_pk(%s, %k1, %nl) : (!llvm.ptr, i64, i8) -> i1
  %crlf = arith.andi %a, %b : i1
  scf.if %crlf {
    func.call @tm_adv(%s, %k2) : (!llvm.ptr, i64) -> ()
    func.call @tm_nl(%s) : (!llvm.ptr) -> ()
  } else {
    %lf = func.call @tm_pk(%s, %k0, %nl) : (!llvm.ptr, i64, i8) -> i1
    scf.if %lf {
      func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
      func.call @tm_nl(%s) : (!llvm.ptr) -> ()
    }
  }
  return
}
func.func private @tm_isnl(%s: !llvm.ptr) -> i1 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %nl = arith.constant 10 : i8
  %cr = arith.constant 13 : i8
  %lf = func.call @tm_pk(%s, %k0, %nl) : (!llvm.ptr, i64, i8) -> i1
  %a = func.call @tm_pk(%s, %k0, %cr) : (!llvm.ptr, i64, i8) -> i1
  %b = func.call @tm_pk(%s, %k1, %nl) : (!llvm.ptr, i64, i8) -> i1
  %crlf = arith.andi %a, %b : i1
  %r = arith.ori %lf, %crlf : i1
  return %r : i1
}
// whitespace, comments and newlines (between array elements, between lines); a comment's error code
func.func private @tm_wsall(%s: !llvm.ptr) -> i32 {
  %z = arith.constant 0 : i32
  %r = scf.while (%e = %z) : (i32) -> i32 {
    func.call @tm_wsinline(%s) : (!llvm.ptr) -> ()
    %err = func.call @tm_comment(%s) : (!llvm.ptr) -> i32
    %ok = arith.cmpi eq, %err, %z : i32
    %nl = func.call @tm_isnl(%s) : (!llvm.ptr) -> i1
    %go = arith.andi %ok, %nl : i1
    scf.condition(%go) %err : i32
  } do {
  ^bb0(%y: i32):
    func.call @tm_newline(%s) : (!llvm.ptr) -> ()
    scf.yield %y : i32
  }
  return %r : i32
}
// whether the line ends here (end of input, \n or \r)
func.func private @tm_lineend(%s: !llvm.ptr) -> i1 {
  %k0 = arith.constant 0 : i64
  %nl = arith.constant 10 : i8
  %cr = arith.constant 13 : i8
  %eof = func.call @tm_eof(%s) : (!llvm.ptr) -> i1
  %a = func.call @tm_pk(%s, %k0, %nl) : (!llvm.ptr, i64, i8) -> i1
  %b = func.call @tm_pk(%s, %k0, %cr) : (!llvm.ptr, i64, i8) -> i1
  %x = arith.ori %eof, %a : i1
  %r = arith.ori %x, %b : i1
  return %r : i1
}

// ---- strings ----
// a code point as UTF-8 (the old utf8(): 4 bytes for anything from 0x10000, the lead byte truncated)
func.func private @tm_utf8(%s: !llvm.ptr, %cp: i32) {
  %x80 = arith.constant 128 : i32
  %x800 = arith.constant 2048 : i32
  %x10000 = arith.constant 65536 : i32
  %m3f = arith.constant 63 : i32
  %xc0 = arith.constant 192 : i32
  %xe0 = arith.constant 224 : i32
  %xf0 = arith.constant 240 : i32
  %k6 = arith.constant 6 : i32
  %k12 = arith.constant 12 : i32
  %k18 = arith.constant 18 : i32
  %lo = arith.andi %cp, %m3f : i32
  %t0 = arith.ori %lo, %x80 : i32
  %b0 = arith.trunci %t0 : i32 to i8
  %s6 = arith.shrui %cp, %k6 : i32
  %m6 = arith.andi %s6, %m3f : i32
  %t1 = arith.ori %m6, %x80 : i32
  %b1 = arith.trunci %t1 : i32 to i8
  %s12 = arith.shrui %cp, %k12 : i32
  %m12 = arith.andi %s12, %m3f : i32
  %t2 = arith.ori %m12, %x80 : i32
  %b2 = arith.trunci %t2 : i32 to i8
  %s18 = arith.shrui %cp, %k18 : i32
  %a1 = arith.cmpi ult, %cp, %x80 : i32
  scf.if %a1 {
    %c = arith.trunci %cp : i32 to i8
    func.call @tm_put(%s, %c) : (!llvm.ptr, i8) -> ()
  } else {
    %a2 = arith.cmpi ult, %cp, %x800 : i32
    scf.if %a2 {
      %h = arith.ori %s6, %xc0 : i32
      %hc = arith.trunci %h : i32 to i8
      func.call @tm_put(%s, %hc) : (!llvm.ptr, i8) -> ()
      func.call @tm_put(%s, %b0) : (!llvm.ptr, i8) -> ()
    } else {
      %a3 = arith.cmpi ult, %cp, %x10000 : i32
      scf.if %a3 {
        %h = arith.ori %s12, %xe0 : i32
        %hc = arith.trunci %h : i32 to i8
        func.call @tm_put(%s, %hc) : (!llvm.ptr, i8) -> ()
        func.call @tm_put(%s, %b1) : (!llvm.ptr, i8) -> ()
        func.call @tm_put(%s, %b0) : (!llvm.ptr, i8) -> ()
      } else {
        %h = arith.ori %s18, %xf0 : i32
        %hc = arith.trunci %h : i32 to i8
        func.call @tm_put(%s, %hc) : (!llvm.ptr, i8) -> ()
        func.call @tm_put(%s, %b2) : (!llvm.ptr, i8) -> ()
        func.call @tm_put(%s, %b1) : (!llvm.ptr, i8) -> ()
        func.call @tm_put(%s, %b0) : (!llvm.ptr, i8) -> ()
      }
    }
  }
  return
}
// a backslash escape at p, decoded; 0, 2 (invalid unicode escape) or 3 (invalid escape; the byte in the error window)
func.func private @tm_escape(%s: !llvm.ptr) -> i32 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k4 = arith.constant 4 : i64
  %k8 = arith.constant 8 : i64
  %z = arith.constant 0 : i32
  %e2 = arith.constant 2 : i32
  %e3 = arith.constant 3 : i32
  %z8 = arith.constant 0 : i8
  %bu = arith.constant 117 : i8
  %bU = arith.constant 85 : i8
  %bad = arith.constant 15 : i8
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  %e = func.call @tm_peek(%s, %k0) : (!llvm.ptr, i64) -> i8
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  %esc = llvm.mlir.addressof @tm_esc : !llvm.ptr
  %v = func.call @tm_cv(%esc, %e) : (!llvm.ptr, i8) -> i8
  %simple = arith.cmpi ne, %v, %z8 : i8
  %r = scf.if %simple -> (i32) {
    func.call @tm_put(%s, %v) : (!llvm.ptr, i8) -> ()
    scf.yield %z : i32
  } else {
    %isu = arith.cmpi eq, %e, %bu : i8
    %isU = arith.cmpi eq, %e, %bU : i8
    %uni = arith.ori %isu, %isU : i1
    %r2 = scf.if %uni -> (i32) {
      %n = arith.select %isu, %k4, %k8 : i64
      %dv = llvm.mlir.addressof @tm_dval : !llvm.ptr
      %z32 = arith.constant 0 : i32
      %four = arith.constant 4 : i32
      %ok0 = arith.constant 1 : i1
      // n hex digits; stop at the first that is not one
      %res:3 = scf.while (%i = %k0, %cp = %z32, %ok = %ok0) : (i64, i32, i1) -> (i64, i32, i1) {
        %more = arith.cmpi slt, %i, %n : i64
        %go = arith.andi %more, %ok : i1
        scf.condition(%go) %i, %cp, %ok : i64, i32, i1
      } do {
      ^bb0(%i1: i64, %cp1: i32, %ok1: i1):
        %c = func.call @tm_peek(%s, %k0) : (!llvm.ptr, i64) -> i8
        func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
        %d = func.call @tm_cv(%dv, %c) : (!llvm.ptr, i8) -> i8
        %le = arith.constant 16 : i8
        %hex2 = arith.cmpi ult, %d, %le : i8
        %d32 = arith.extui %d : i8 to i32
        %sh = arith.shli %cp1, %four : i32
        %nx = arith.ori %sh, %d32 : i32
        %i2 = arith.addi %i1, %k1 : i64
        scf.yield %i2, %nx, %hex2 : i64, i32, i1
      }
      %r3 = scf.if %res#2 -> (i32) {
        func.call @tm_utf8(%s, %res#1) : (!llvm.ptr, i32) -> ()
        scf.yield %z : i32
      } else {
        scf.yield %e2 : i32
      }
      scf.yield %r3 : i32
    } else {
      // the escape byte (0 at the end of input) into dec's scratch, named by the error
      %dec = func.call @tm_rp(%s, %k4) : (!llvm.ptr, i64) -> !llvm.ptr
      %dp = func.call @tm_rd(%s, %k8) : (!llvm.ptr, i64) -> i64
      func.call @tm_st(%dec, %dp, %e) : (!llvm.ptr, i64, i8) -> ()
      %wp = func.call @tm_off(%dec, %dp) : (!llvm.ptr, i64) -> !llvm.ptr
      func.call @tm_setw(%s, %wp, %k1) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      scf.yield %e3 : i32
    }
    scf.yield %r2 : i32
  }
  return %r : i32
}
// a basic string at p ("..." or """..."""), decoded into dec; its window in words 12 / 13; 0 or an error code
func.func private @tm_basic(%s: !llvm.ptr) -> i32 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k2 = arith.constant 2 : i64
  %k3 = arith.constant 3 : i64
  %k4 = arith.constant 4 : i64
  %k8 = arith.constant 8 : i64
  %z = arith.constant 0 : i32
  %e4 = arith.constant 4 : i32
  %e5 = arith.constant 5 : i32
  %q = arith.constant 34 : i8
  %bs = arith.constant 92 : i8
  %nl = arith.constant 10 : i8
  %cr = arith.constant 13 : i8
  %sp = arith.constant 32 : i8
  %tab = arith.constant 9 : i8
  %dec = func.call @tm_rp(%s, %k4) : (!llvm.ptr, i64) -> !llvm.ptr
  %d0 = func.call @tm_rd(%s, %k8) : (!llvm.ptr, i64) -> i64
  %multi = func.call @tm_triple(%s, %q) : (!llvm.ptr, i8) -> i1
  cf.cond_br %multi, ^ml, ^sl
^ml:
  func.call @tm_adv(%s, %k3) : (!llvm.ptr, i64) -> ()
  %lf_ml = func.call @tm_pk(%s, %k0, %nl) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %lf_ml, ^ml_lf, ^ml_crq
^ml_lf:
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  func.call @tm_nl(%s) : (!llvm.ptr) -> ()
  cf.br ^ml_loop
^ml_crq:
  %a_crq = func.call @tm_pk(%s, %k0, %cr) : (!llvm.ptr, i64, i8) -> i1
  %b_crq = func.call @tm_pk(%s, %k1, %nl) : (!llvm.ptr, i64, i8) -> i1
  %crlf_crq = arith.andi %a_crq, %b_crq : i1
  cf.cond_br %crlf_crq, ^ml_crlf, ^ml_loop
^ml_crlf:
  func.call @tm_adv(%s, %k2) : (!llvm.ptr, i64) -> ()
  func.call @tm_nl(%s) : (!llvm.ptr) -> ()
  cf.br ^ml_loop
^ml_loop:
  %eof_l = func.call @tm_eof(%s) : (!llvm.ptr) -> i1
  cf.cond_br %eof_l, ^fail(%e4 : i32), ^ml_close
^ml_close:
  %end_c = func.call @tm_triple(%s, %q) : (!llvm.ptr, i8) -> i1
  cf.cond_br %end_c, ^ml_end, ^ml_char
^ml_end:
  func.call @tm_adv(%s, %k3) : (!llvm.ptr, i64) -> ()
  // up to two more quotes belong to the content
  %x1_e = func.call @tm_pk(%s, %k0, %q) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %x1_e, ^ml_x1, ^done
^ml_x1:
  func.call @tm_put(%s, %q) : (!llvm.ptr, i8) -> ()
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  %x2_x1 = func.call @tm_pk(%s, %k0, %q) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %x2_x1, ^ml_x2, ^done
^ml_x2:
  func.call @tm_put(%s, %q) : (!llvm.ptr, i8) -> ()
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  cf.br ^done
^ml_char:
  %c_ch = func.call @tm_peek(%s, %k0) : (!llvm.ptr, i64) -> i8
  %isbs_ch = arith.cmpi eq, %c_ch, %bs : i8
  cf.cond_br %isbs_ch, ^ml_bs, ^ml_plain
^ml_bs:
  // a line-ending backslash: blanks, then a newline -> skip every blank and newline after it
  %p_bs = func.call @tm_p(%s) : (!llvm.ptr) -> i64
  %q0_bs = arith.addi %p_bs, %k1 : i64
  %qe_bs = scf.while (%j = %q0_bs) : (i64) -> i64 {
    %c = func.call @tm_at(%s, %j) : (!llvm.ptr, i64) -> i8
    %a = arith.cmpi eq, %c, %sp : i8
    %b = arith.cmpi eq, %c, %tab : i8
    %go = arith.ori %a, %b : i1
    scf.condition(%go) %j : i64
  } do {
  ^bb0(%j1: i64):
    %j2 = arith.addi %j1, %k1 : i64
    scf.yield %j2 : i64
  }
  %cq_bs = func.call @tm_at(%s, %qe_bs) : (!llvm.ptr, i64) -> i8
  %qn_bs = arith.cmpi eq, %cq_bs, %nl : i8
  %qr_bs = arith.cmpi eq, %cq_bs, %cr : i8
  %le_bs = arith.ori %qn_bs, %qr_bs : i1
  cf.cond_br %le_bs, ^ml_skip, ^ml_esc
^ml_skip:
  func.call @tm_setp(%s, %qe_bs) : (!llvm.ptr, i64) -> ()
  %u_sk = arith.constant 0 : i1
  %w_sk = scf.while (%x = %u_sk) : (i1) -> i1 {
    %c = func.call @tm_peek(%s, %k0) : (!llvm.ptr, i64) -> i8
    %a = arith.cmpi eq, %c, %sp : i8
    %b = arith.cmpi eq, %c, %tab : i8
    %cn = arith.cmpi eq, %c, %nl : i8
    %cc = arith.cmpi eq, %c, %cr : i8
    %o1 = arith.ori %a, %b : i1
    %o2 = arith.ori %cn, %cc : i1
    %go = arith.ori %o1, %o2 : i1
    scf.condition(%go) %cn : i1
  } do {
  ^bb0(%isn: i1):
    scf.if %isn {
      func.call @tm_nl(%s) : (!llvm.ptr) -> ()
    }
    func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
    %f = arith.constant 0 : i1
    scf.yield %f : i1
  }
  cf.br ^ml_loop
^ml_esc:
  %err_me = func.call @tm_escape(%s) : (!llvm.ptr) -> i32
  %bad_me = arith.cmpi ne, %err_me, %z : i32
  cf.cond_br %bad_me, ^fail(%err_me : i32), ^ml_loop
^ml_plain:
  %isnl_pl = arith.cmpi eq, %c_ch, %nl : i8
  cf.cond_br %isnl_pl, ^ml_plnl, ^ml_pl
^ml_plnl:
  func.call @tm_nl(%s) : (!llvm.ptr) -> ()
  cf.br ^ml_pl
^ml_pl:
  func.call @tm_put(%s, %c_ch) : (!llvm.ptr, i8) -> ()
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  cf.br ^ml_loop
^sl:
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  cf.br ^sl_loop
^sl_loop:
  %eof_sl = func.call @tm_eof(%s) : (!llvm.ptr) -> i1
  %lf_sl = func.call @tm_pk(%s, %k0, %nl) : (!llvm.ptr, i64, i8) -> i1
  %stop_sl = arith.ori %eof_sl, %lf_sl : i1
  cf.cond_br %stop_sl, ^fail(%e5 : i32), ^sl_char
^sl_char:
  %c_sc = func.call @tm_peek(%s, %k0) : (!llvm.ptr, i64) -> i8
  %isq_sc = arith.cmpi eq, %c_sc, %q : i8
  cf.cond_br %isq_sc, ^sl_end, ^sl_bsq
^sl_end:
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  cf.br ^done
^sl_bsq:
  %isbs_bq = arith.cmpi eq, %c_sc, %bs : i8
  cf.cond_br %isbs_bq, ^sl_esc, ^sl_pl
^sl_esc:
  %err_se = func.call @tm_escape(%s) : (!llvm.ptr) -> i32
  %bad_se = arith.cmpi ne, %err_se, %z : i32
  cf.cond_br %bad_se, ^fail(%err_se : i32), ^sl_loop
^sl_pl:
  func.call @tm_put(%s, %c_sc) : (!llvm.ptr, i8) -> ()
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  cf.br ^sl_loop
^done:
  %d1_dn = func.call @tm_rd(%s, %k8) : (!llvm.ptr, i64) -> i64
  %len_dn = arith.subi %d1_dn, %d0 : i64
  %wp_dn = func.call @tm_off(%dec, %d0) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @tm_setv(%s, %wp_dn, %len_dn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  return %z : i32
^fail(%code: i32):
  return %code : i32
}
// a literal string at p ('...' or '''...'''): a window of the input in words 12 / 13; 0 or an error code
func.func private @tm_literal(%s: !llvm.ptr) -> i32 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k2 = arith.constant 2 : i64
  %k3 = arith.constant 3 : i64
  %z = arith.constant 0 : i32
  %e6 = arith.constant 6 : i32
  %e7 = arith.constant 7 : i32
  %q = arith.constant 39 : i8
  %nl = arith.constant 10 : i8
  %cr = arith.constant 13 : i8
  %src = func.call @tm_rp(%s, %k0) : (!llvm.ptr, i64) -> !llvm.ptr
  %multi = func.call @tm_triple(%s, %q) : (!llvm.ptr, i8) -> i1
  cf.cond_br %multi, ^ml, ^sl
^ml:
  func.call @tm_adv(%s, %k3) : (!llvm.ptr, i64) -> ()
  %lf_ml = func.call @tm_pk(%s, %k0, %nl) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %lf_ml, ^ml_lf, ^ml_crq
^ml_lf:
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  func.call @tm_nl(%s) : (!llvm.ptr) -> ()
  cf.br ^ml_start
^ml_crq:
  %a_crq = func.call @tm_pk(%s, %k0, %cr) : (!llvm.ptr, i64, i8) -> i1
  %b_crq = func.call @tm_pk(%s, %k1, %nl) : (!llvm.ptr, i64, i8) -> i1
  %crlf_crq = arith.andi %a_crq, %b_crq : i1
  cf.cond_br %crlf_crq, ^ml_crlf, ^ml_start
^ml_crlf:
  func.call @tm_adv(%s, %k2) : (!llvm.ptr, i64) -> ()
  func.call @tm_nl(%s) : (!llvm.ptr) -> ()
  cf.br ^ml_start
^ml_start:
  %st_ms = func.call @tm_p(%s) : (!llvm.ptr) -> i64
  cf.br ^ml_loop
^ml_loop:
  %eof_l = func.call @tm_eof(%s) : (!llvm.ptr) -> i1
  cf.cond_br %eof_l, ^fail(%e6 : i32), ^ml_close
^ml_close:
  %end_c = func.call @tm_triple(%s, %q) : (!llvm.ptr, i8) -> i1
  cf.cond_br %end_c, ^ml_end, ^ml_char
^ml_end:
  %q0_e = func.call @tm_p(%s) : (!llvm.ptr) -> i64
  func.call @tm_adv(%s, %k3) : (!llvm.ptr, i64) -> ()
  // up to two more quotes belong to the content: they follow it in the input
  %x1_e = func.call @tm_pk(%s, %k0, %q) : (!llvm.ptr, i64, i8) -> i1
  %x1i_e = arith.extui %x1_e : i1 to i64
  func.call @tm_adv(%s, %x1i_e) : (!llvm.ptr, i64) -> ()
  %x2_e = func.call @tm_pk(%s, %k0, %q) : (!llvm.ptr, i64, i8) -> i1
  %x2b_e = arith.andi %x1_e, %x2_e : i1
  %x2i_e = arith.extui %x2b_e : i1 to i64
  func.call @tm_adv(%s, %x2i_e) : (!llvm.ptr, i64) -> ()
  %xt_e = arith.addi %x1i_e, %x2i_e : i64
  %to_e = arith.addi %q0_e, %xt_e : i64
  %len_e = arith.subi %to_e, %st_ms : i64
  %wp_e = func.call @tm_off(%src, %st_ms) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @tm_setv(%s, %wp_e, %len_e) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  return %z : i32
^ml_char:
  %isnl_ch = func.call @tm_pk(%s, %k0, %nl) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %isnl_ch, ^ml_nl, ^ml_step
^ml_nl:
  func.call @tm_nl(%s) : (!llvm.ptr) -> ()
  cf.br ^ml_step
^ml_step:
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  cf.br ^ml_loop
^sl:
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  %st_sl = func.call @tm_p(%s) : (!llvm.ptr) -> i64
  cf.br ^sl_loop
^sl_loop:
  %eof_sl = func.call @tm_eof(%s) : (!llvm.ptr) -> i1
  %lf_sl = func.call @tm_pk(%s, %k0, %nl) : (!llvm.ptr, i64, i8) -> i1
  %stop_sl = arith.ori %eof_sl, %lf_sl : i1
  cf.cond_br %stop_sl, ^fail(%e7 : i32), ^sl_char
^sl_char:
  %isq_sc = func.call @tm_pk(%s, %k0, %q) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %isq_sc, ^sl_end, ^sl_step
^sl_end:
  %p_se = func.call @tm_p(%s) : (!llvm.ptr) -> i64
  %len_se = arith.subi %p_se, %st_sl : i64
  %wp_se = func.call @tm_off(%src, %st_sl) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @tm_setv(%s, %wp_se, %len_se) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  return %z : i32
^sl_step:
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  cf.br ^sl_loop
^fail(%code: i32):
  return %code : i32
}

// ---- keys ----
// a (dotted) key: each part an event 0; 0 or an error code
func.func private @tm_key(%s: !llvm.ptr) -> i32 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k12 = arith.constant 12 : i64
  %k13 = arith.constant 13 : i64
  %z = arith.constant 0 : i32
  %e8 = arith.constant 8 : i32
  %e9 = arith.constant 9 : i32
  %dq = arith.constant 34 : i8
  %sq = arith.constant 39 : i8
  %dot = arith.constant 46 : i8
  %nul = arith.constant 0 : i8
  %src = func.call @tm_rp(%s, %k0) : (!llvm.ptr, i64) -> !llvm.ptr
  %bare = llvm.mlir.addressof @tm_bare : !llvm.ptr
  cf.br ^part
^part:
  func.call @tm_wsinline(%s) : (!llvm.ptr) -> ()
  %c_p = func.call @tm_peek(%s, %k0) : (!llvm.ptr, i64) -> i8
  %isd_p = arith.cmpi eq, %c_p, %dq : i8
  cf.cond_br %isd_p, ^basic, ^lit_q
^basic:
  %err_b = func.call @tm_basic(%s) : (!llvm.ptr) -> i32
  cf.br ^got(%err_b : i32)
^lit_q:
  %iss_l = arith.cmpi eq, %c_p, %sq : i8
  cf.cond_br %iss_l, ^lit, ^bare
^lit:
  %err_l = func.call @tm_literal(%s) : (!llvm.ptr) -> i32
  cf.br ^got(%err_l : i32)
^bare:
  %st_b = func.call @tm_p(%s) : (!llvm.ptr) -> i64
  %u_b = arith.constant 0 : i1
  %w_b = scf.while (%x = %u_b) : (i1) -> i1 {
    %c = func.call @tm_peek(%s, %k0) : (!llvm.ptr, i64) -> i8
    %go = func.call @tm_is(%bare, %c) : (!llvm.ptr, i8) -> i1
    scf.condition(%go) %go : i1
  } do {
  ^bb0(%y: i1):
    func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
    scf.yield %y : i1
  }
  %p_b = func.call @tm_p(%s) : (!llvm.ptr) -> i64
  %none_b = arith.cmpi eq, %p_b, %st_b : i64
  cf.cond_br %none_b, ^fail(%e8 : i32), ^bare_ok
^bare_ok:
  %len_bo = arith.subi %p_b, %st_b : i64
  %wp_bo = func.call @tm_off(%src, %st_b) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @tm_setv(%s, %wp_bo, %len_bo) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  cf.br ^got(%z : i32)
^got(%err: i32):
  %bad_g = arith.cmpi ne, %err, %z : i32
  cf.cond_br %bad_g, ^fail(%err : i32), ^nulq
^nulq:
  %wp_n = func.call @tm_rp(%s, %k12) : (!llvm.ptr, i64) -> !llvm.ptr
  %wn_n = func.call @tm_rd(%s, %k13) : (!llvm.ptr, i64) -> i64
  %hn_n = func.call @tm_has(%wp_n, %wn_n, %nul) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %hn_n, ^fail(%e9 : i32), ^emit
^emit:
  func.call @tm_ev(%s, %k0, %wp_n, %wn_n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @tm_wsinline(%s) : (!llvm.ptr) -> ()
  %isdot_e = func.call @tm_pk(%s, %k0, %dot) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %isdot_e, ^next, ^done
^next:
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  cf.br ^part
^done:
  return %z : i32
^fail(%code: i32):
  return %code : i32
}

// ---- dates and times ----
func.func private @tm_dig(%s: !llvm.ptr, %o: i64) -> i1 {
  %t = llvm.mlir.addressof @tm_digit : !llvm.ptr
  %c = func.call @tm_peek(%s, %o) : (!llvm.ptr, i64) -> i8
  %r = func.call @tm_is(%t, %c) : (!llvm.ptr, i8) -> i1
  return %r : i1
}
// YYYY-MM-DD or HH:MM:SS ahead
func.func private @tm_isdate(%s: !llvm.ptr) -> i1 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k2 = arith.constant 2 : i64
  %k3 = arith.constant 3 : i64
  %k4 = arith.constant 4 : i64
  %k5 = arith.constant 5 : i64
  %k6 = arith.constant 6 : i64
  %k7 = arith.constant 7 : i64
  %dash = arith.constant 45 : i8
  %colon = arith.constant 58 : i8
  %d0 = func.call @tm_dig(%s, %k0) : (!llvm.ptr, i64) -> i1
  %d1 = func.call @tm_dig(%s, %k1) : (!llvm.ptr, i64) -> i1
  %d2 = func.call @tm_dig(%s, %k2) : (!llvm.ptr, i64) -> i1
  %d3 = func.call @tm_dig(%s, %k3) : (!llvm.ptr, i64) -> i1
  %d4 = func.call @tm_dig(%s, %k4) : (!llvm.ptr, i64) -> i1
  %d5 = func.call @tm_dig(%s, %k5) : (!llvm.ptr, i64) -> i1
  %d6 = func.call @tm_dig(%s, %k6) : (!llvm.ptr, i64) -> i1
  %m4 = func.call @tm_pk(%s, %k4, %dash) : (!llvm.ptr, i64, i8) -> i1
  %m7 = func.call @tm_pk(%s, %k7, %dash) : (!llvm.ptr, i64, i8) -> i1
  %c2 = func.call @tm_pk(%s, %k2, %colon) : (!llvm.ptr, i64, i8) -> i1
  %c5 = func.call @tm_pk(%s, %k5, %colon) : (!llvm.ptr, i64, i8) -> i1
  %a1 = arith.andi %d0, %d1 : i1
  %a2 = arith.andi %a1, %d2 : i1
  %a3 = arith.andi %a2, %d3 : i1
  %a4 = arith.andi %a3, %m4 : i1
  %a5 = arith.andi %a4, %d5 : i1
  %a6 = arith.andi %a5, %d6 : i1
  %date = arith.andi %a6, %m7 : i1
  %b1 = arith.andi %a1, %c2 : i1
  %b2 = arith.andi %b1, %d3 : i1
  %b3 = arith.andi %b2, %d4 : i1
  %time = arith.andi %b3, %c5 : i1
  %r = arith.ori %date, %time : i1
  return %r : i1
}
// copy the run of class-t bytes at p into dec; how many
func.func private @tm_take(%s: !llvm.ptr, %t: !llvm.ptr) -> i64 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %r = scf.while (%n = %k0) : (i64) -> i64 {
    %c = func.call @tm_peek(%s, %k0) : (!llvm.ptr, i64) -> i8
    %go = func.call @tm_is(%t, %c) : (!llvm.ptr, i8) -> i1
    scf.condition(%go) %n : i64
  } do {
  ^bb0(%n1: i64):
    %c = func.call @tm_peek(%s, %k0) : (!llvm.ptr, i64) -> i8
    func.call @tm_put(%s, %c) : (!llvm.ptr, i8) -> ()
    func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
    %n2 = arith.addi %n1, %k1 : i64
    scf.yield %n2 : i64
  }
  return %r : i64
}
// a date / time at p in its normal form, into dec; its window in words 12 / 13
func.func private @tm_datetime(%s: !llvm.ptr) {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k3 = arith.constant 3 : i64
  %k4 = arith.constant 4 : i64
  %k6 = arith.constant 6 : i64
  %k8 = arith.constant 8 : i64
  %k9 = arith.constant 9 : i64
  %dash = arith.constant 45 : i8
  %bT = arith.constant 84 : i8
  %bt = arith.constant 116 : i8
  %sp = arith.constant 32 : i8
  %dot = arith.constant 46 : i8
  %bZ = arith.constant 90 : i8
  %bz = arith.constant 122 : i8
  %plus = arith.constant 43 : i8
  %zero = arith.constant 48 : i8
  %dt1 = llvm.mlir.addressof @tm_dt1 : !llvm.ptr
  %dt2 = llvm.mlir.addressof @tm_dt2 : !llvm.ptr
  %dg = llvm.mlir.addressof @tm_digit : !llvm.ptr
  %dec = func.call @tm_rp(%s, %k4) : (!llvm.ptr, i64) -> !llvm.ptr
  %d0 = func.call @tm_rd(%s, %k8) : (!llvm.ptr, i64) -> i64
  %n0 = func.call @tm_take(%s, %dt1) : (!llvm.ptr, !llvm.ptr) -> i64
  %w0 = func.call @tm_off(%dec, %d0) : (!llvm.ptr, i64) -> !llvm.ptr
  %hasdash = func.call @tm_has(%w0, %n0, %dash) : (!llvm.ptr, i64, i8) -> i1
  // the date-time separator
  %isT = func.call @tm_pk(%s, %k0, %bT) : (!llvm.ptr, i64, i8) -> i1
  %ist = func.call @tm_pk(%s, %k0, %bt) : (!llvm.ptr, i64, i8) -> i1
  %issp = func.call @tm_pk(%s, %k0, %sp) : (!llvm.ptr, i64, i8) -> i1
  %dig1 = func.call @tm_dig(%s, %k1) : (!llvm.ptr, i64) -> i1
  %spd = arith.andi %issp, %dig1 : i1
  %o1 = arith.ori %isT, %ist : i1
  %o2 = arith.ori %o1, %spd : i1
  %sep = arith.andi %o2, %hasdash : i1
  scf.if %sep {
    func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
    func.call @tm_put(%s, %bT) : (!llvm.ptr, i8) -> ()
    %n1 = func.call @tm_take(%s, %dt2) : (!llvm.ptr, !llvm.ptr) -> i64
  }
  // a fraction: at most 9 digits, padded with zeros to 3, 6 or 9
  %isdot = func.call @tm_pk(%s, %k0, %dot) : (!llvm.ptr, i64, i8) -> i1
  scf.if %isdot {
    func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
    func.call @tm_put(%s, %dot) : (!llvm.ptr, i8) -> ()
    %f = func.call @tm_take(%s, %dg) : (!llvm.ptr, !llvm.ptr) -> i64
    %le3 = arith.cmpi sle, %f, %k3 : i64
    %le6 = arith.cmpi sle, %f, %k6 : i64
    %p69 = arith.select %le6, %k6, %k9 : i64
    %pad = arith.select %le3, %k3, %p69 : i64
    %over = arith.cmpi sgt, %f, %k9 : i64
    %drop = arith.subi %f, %k9 : i64
    %dp = func.call @tm_rd(%s, %k8) : (!llvm.ptr, i64) -> i64
    %cut = arith.subi %dp, %drop : i64
    %dq = arith.select %over, %cut, %dp : i64
    func.call @tm_wr(%s, %k8, %dq) : (!llvm.ptr, i64, i64) -> ()
    %kept = arith.select %over, %k9, %f : i64
    %zs = arith.subi %pad, %kept : i64
    scf.for %i = %k0 to %zs step %k1 : i64 {
      func.call @tm_put(%s, %zero) : (!llvm.ptr, i8) -> ()
    }
  }
  // the offset: Z, or a sign and a time
  %isZ = func.call @tm_pk(%s, %k0, %bZ) : (!llvm.ptr, i64, i8) -> i1
  %isz = func.call @tm_pk(%s, %k0, %bz) : (!llvm.ptr, i64, i8) -> i1
  %zulu = arith.ori %isZ, %isz : i1
  scf.if %zulu {
    func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
    func.call @tm_put(%s, %bZ) : (!llvm.ptr, i8) -> ()
  } else {
    %c = func.call @tm_peek(%s, %k0) : (!llvm.ptr, i64) -> i8
    %pl = arith.cmpi eq, %c, %plus : i8
    %mi = arith.cmpi eq, %c, %dash : i8
    %sg = arith.ori %pl, %mi : i1
    %d1 = func.call @tm_dig(%s, %k1) : (!llvm.ptr, i64) -> i1
    %off = arith.andi %sg, %d1 : i1
    scf.if %off {
      func.call @tm_put(%s, %c) : (!llvm.ptr, i8) -> ()
      func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
      %n2 = func.call @tm_take(%s, %dt2) : (!llvm.ptr, !llvm.ptr) -> i64
    }
  }
  %d1e = func.call @tm_rd(%s, %k8) : (!llvm.ptr, i64) -> i64
  %len = arith.subi %d1e, %d0 : i64
  func.call @tm_setv(%s, %w0, %len) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  return
}

// ---- numbers ----
// the window without its underscores, into out; -1 when an underscore is not between two alphanumerics
func.func private @tm_strip(%x: !llvm.ptr, %n: i64, %out: !llvm.ptr) -> i64 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %m1 = arith.constant -1 : i64
  %us = arith.constant 95 : i8
  %f = arith.constant 0 : i1
  %t = arith.constant 1 : i1
  %an = llvm.mlir.addressof @tm_alnum : !llvm.ptr
  %last = arith.subi %n, %k1 : i64
  %r:2 = scf.for %i = %k0 to %n step %k1 iter_args(%j = %k0, %bad = %f) -> (i64, i1) : i64 {
    %c = func.call @tm_ld(%x, %i) : (!llvm.ptr, i64) -> i8
    %isu = arith.cmpi eq, %c, %us : i8
    %r2:2 = scf.if %isu -> (i64, i1) {
      %first = arith.cmpi eq, %i, %k0 : i64
      %i1 = arith.addi %i, %k1 : i64
      %end = arith.cmpi sge, %i1, %n : i64
      %ip = arith.subi %i, %k1 : i64
      %ipc = arith.select %first, %k0, %ip : i64
      %inc = arith.select %end, %last, %i1 : i64
      %cp = func.call @tm_ld(%x, %ipc) : (!llvm.ptr, i64) -> i8
      %cn = func.call @tm_ld(%x, %inc) : (!llvm.ptr, i64) -> i8
      %ap = func.call @tm_is(%an, %cp) : (!llvm.ptr, i8) -> i1
      %anx = func.call @tm_is(%an, %cn) : (!llvm.ptr, i8) -> i1
      %nap = arith.xori %ap, %t : i1
      %nan = arith.xori %anx, %t : i1
      %b1 = arith.ori %first, %end : i1
      %b2 = arith.ori %b1, %nap : i1
      %b3 = arith.ori %b2, %nan : i1
      %nb = arith.ori %bad, %b3 : i1
      scf.yield %j, %nb : i64, i1
    } else {
      func.call @tm_st(%out, %j, %c) : (!llvm.ptr, i64, i8) -> ()
      %j1 = arith.addi %j, %k1 : i64
      scf.yield %j1, %bad : i64, i1
    }
    scf.yield %r2#0, %r2#1 : i64, i1
  }
  %res = arith.select %r#1, %m1, %r#0 : i64
  return %res : i64
}
// strtoll / strtoull's reading in base b (composite readInteger): (value, overflow, consumed)
func.func private @tm_readint(%x: !llvm.ptr, %n: i64, %base: i64, %signed: i1) -> (i64, i1, i64) {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k2 = arith.constant 2 : i64
  %k3 = arith.constant 3 : i64
  %k16 = arith.constant 16 : i64
  %plus = arith.constant 43 : i8
  %minus = arith.constant 45 : i8
  %b0 = arith.constant 48 : i8
  %bx = arith.constant 120 : i8
  %bX = arith.constant 88 : i8
  %f = arith.constant 0 : i1
  %t = arith.constant 1 : i1
  %max = arith.constant 9223372036854775807 : i64
  %min = arith.constant -9223372036854775808 : i64
  %all = arith.constant -1 : i64
  %dv = llvm.mlir.addressof @tm_dval : !llvm.ptr
  %some = arith.cmpi sgt, %n, %k0 : i64
  %first = scf.if %some -> (i8) {
    %c = func.call @tm_ld(%x, %k0) : (!llvm.ptr, i64) -> i8
    scf.yield %c : i8
  } else {
    %z8 = arith.constant 0 : i8
    scf.yield %z8 : i8
  }
  %isp = arith.cmpi eq, %first, %plus : i8
  %ism = arith.cmpi eq, %first, %minus : i8
  %sg = arith.ori %isp, %ism : i1
  %pos0 = arith.extui %sg : i1 to i64
  // base 16: an optional 0x / 0X before a hex digit
  %is16 = arith.cmpi eq, %base, %k16 : i64
  %rem = arith.subi %n, %pos0 : i64
  %r3 = arith.cmpi sge, %rem, %k3 : i64
  %c16 = arith.andi %is16, %r3 : i1
  %pos = scf.if %c16 -> (i64) {
    %pa = arith.addi %pos0, %k1 : i64
    %pb = arith.addi %pos0, %k2 : i64
    %ca = func.call @tm_ld(%x, %pos0) : (!llvm.ptr, i64) -> i8
    %cb = func.call @tm_ld(%x, %pa) : (!llvm.ptr, i64) -> i8
    %cc = func.call @tm_ld(%x, %pb) : (!llvm.ptr, i64) -> i8
    %z0 = arith.cmpi eq, %ca, %b0 : i8
    %x1 = arith.cmpi eq, %cb, %bx : i8
    %x2 = arith.cmpi eq, %cb, %bX : i8
    %xx = arith.ori %x1, %x2 : i1
    %dc = func.call @tm_cv(%dv, %cc) : (!llvm.ptr, i8) -> i8
    %dc64 = arith.extui %dc : i8 to i64
    %hx = arith.cmpi ult, %dc64, %k16 : i64
    %a1 = arith.andi %z0, %xx : i1
    %a2 = arith.andi %a1, %hx : i1
    %skip = arith.select %a2, %k2, %k0 : i64
    %pp = arith.addi %pos0, %skip : i64
    scf.yield %pp : i64
  } else {
    scf.yield %pos0 : i64
  }
  // the limit: 2^63 for a negative signed reading, 2^63 - 1 a positive one, 2^64 - 1 unsigned
  %slim = arith.select %ism, %min, %max : i64
  %limit = arith.select %signed, %slim, %all : i64
  %res:3 = scf.while (%i = %pos, %v = %k0, %ov = %f) : (i64, i64, i1) -> (i64, i64, i1) {
    %in = arith.cmpi slt, %i, %n : i64
    %c = scf.if %in -> (i64) {
      %b = func.call @tm_ld(%x, %i) : (!llvm.ptr, i64) -> i8
      %d = func.call @tm_cv(%dv, %b) : (!llvm.ptr, i8) -> i8
      %d64 = arith.extui %d : i8 to i64
      scf.yield %d64 : i64
    } else {
      %big = arith.constant 99 : i64
      scf.yield %big : i64
    }
    %isd = arith.cmpi ult, %c, %base : i64
    %go = arith.andi %in, %isd : i1
    scf.condition(%go) %i, %v, %ov : i64, i64, i1
  } do {
  ^bb0(%i1: i64, %v1: i64, %ov1: i1):
    %b = func.call @tm_ld(%x, %i1) : (!llvm.ptr, i64) -> i8
    %d8 = func.call @tm_cv(%dv, %b) : (!llvm.ptr, i8) -> i8
    %d = arith.extui %d8 : i8 to i64
    %ld = arith.subi %limit, %d : i64
    %q = arith.divui %ld, %base : i64
    %gt = arith.cmpi ugt, %v1, %q : i64
    %sat = arith.ori %ov1, %gt : i1
    %vm = arith.muli %v1, %base : i64
    %va = arith.addi %vm, %d : i64
    %v2 = arith.select %sat, %limit, %va : i64
    %i2 = arith.addi %i1, %k1 : i64
    scf.yield %i2, %v2, %sat : i64, i64, i1
  }
  %digits = arith.subi %res#0, %pos : i64
  %none = arith.cmpi eq, %digits, %k0 : i64
  %neg = arith.subi %k0, %res#1 : i64
  %nno = arith.xori %res#2, %t : i1
  %negok = arith.andi %ism, %nno : i1
  %sneg = arith.select %ism, %min, %res#1 : i64
  %sval = arith.select %negok, %neg, %sneg : i64
  %uneg = arith.select %ism, %neg, %res#1 : i64
  %uval = arith.select %res#2, %all, %uneg : i64
  %val = arith.select %signed, %sval, %uval : i64
  %rv = arith.select %none, %k0, %val : i64
  %rov = arith.select %none, %f, %res#2 : i1
  %rc = arith.select %none, %k0, %res#0 : i64
  return %rv, %rov, %rc : i64, i1, i64
}
// a number at p (the run of alnum _ + - .): kind and bits in words 14 / 15; 0 or an error code
func.func private @tm_number(%s: !llvm.ptr) -> i32 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k2 = arith.constant 2 : i64
  %k3 = arith.constant 3 : i64
  %k4 = arith.constant 4 : i64
  %k8 = arith.constant 8 : i64
  %k10 = arith.constant 10 : i64
  %k14 = arith.constant 14 : i64
  %k15 = arith.constant 15 : i64
  %k16 = arith.constant 16 : i64
  %z = arith.constant 0 : i32
  %e10 = arith.constant 10 : i32
  %e11 = arith.constant 11 : i32
  %e12 = arith.constant 12 : i32
  %e13 = arith.constant 13 : i32
  %e14 = arith.constant 14 : i32
  %e15 = arith.constant 15 : i32
  %e16 = arith.constant 16 : i32
  %e17 = arith.constant 17 : i32
  %e18 = arith.constant 18 : i32
  %e19 = arith.constant 19 : i32
  %plus = arith.constant 43 : i8
  %minus = arith.constant 45 : i8
  %b0 = arith.constant 48 : i8
  %bx = arith.constant 120 : i8
  %bo = arith.constant 111 : i8
  %bb = arith.constant 98 : i8
  %bi = arith.constant 105 : i8
  %bn = arith.constant 110 : i8
  %bf = arith.constant 102 : i8
  %ba = arith.constant 97 : i8
  %dot = arith.constant 46 : i8
  %be = arith.constant 101 : i8
  %bE = arith.constant 69 : i8
  %nul = arith.constant 0 : i8
  %max = arith.constant 9223372036854775807 : i64
  %pinf = arith.constant 9218868437227405312 : i64
  %ninf = arith.constant -4503599627370496 : i64
  %qnan = arith.constant 9221120237041090560 : i64
  %t1 = arith.constant 1 : i1
  %f1 = arith.constant 0 : i1
  %src = func.call @tm_rp(%s, %k0) : (!llvm.ptr, i64) -> !llvm.ptr
  %dec = func.call @tm_rp(%s, %k4) : (!llvm.ptr, i64) -> !llvm.ptr
  %dp = func.call @tm_rd(%s, %k8) : (!llvm.ptr, i64) -> i64
  %scr = func.call @tm_off(%dec, %dp) : (!llvm.ptr, i64) -> !llvm.ptr
  %tok = llvm.mlir.addressof @tm_tok : !llvm.ptr
  %start = func.call @tm_p(%s) : (!llvm.ptr) -> i64
  %u0 = arith.constant 0 : i1
  %w0 = scf.while (%x = %u0) : (i1) -> i1 {
    %c = func.call @tm_peek(%s, %k0) : (!llvm.ptr, i64) -> i8
    %go = func.call @tm_is(%tok, %c) : (!llvm.ptr, i8) -> i1
    scf.condition(%go) %go : i1
  } do {
  ^bb0(%y: i1):
    func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
    scf.yield %y : i1
  }
  %end = func.call @tm_p(%s) : (!llvm.ptr) -> i64
  %len = arith.subi %end, %start : i64
  %t = func.call @tm_off(%src, %start) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @tm_setw(%s, %t, %len) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %empty = arith.cmpi eq, %len, %k0 : i64
  cf.cond_br %empty, ^fail(%e10 : i32), ^sign
^sign:
  %c0_s = func.call @tm_ld(%t, %k0) : (!llvm.ptr, i64) -> i8
  %isp_s = arith.cmpi eq, %c0_s, %plus : i8
  %ism_s = arith.cmpi eq, %c0_s, %minus : i8
  %sg_s = arith.ori %isp_s, %ism_s : i1
  %bs_s = arith.extui %sg_s : i1 to i64
  %body_s = func.call @tm_off(%t, %bs_s) : (!llvm.ptr, i64) -> !llvm.ptr
  %bl_s = arith.subi %len, %bs_s : i64
  %is3_s = arith.cmpi eq, %bl_s, %k3 : i64
  cf.cond_br %is3_s, ^word, ^radixq
^word:
  %w0_w = func.call @tm_ld(%body_s, %k0) : (!llvm.ptr, i64) -> i8
  %w1_w = func.call @tm_ld(%body_s, %k1) : (!llvm.ptr, i64) -> i8
  %w2_w = func.call @tm_ld(%body_s, %k2) : (!llvm.ptr, i64) -> i8
  %i0_w = arith.cmpi eq, %w0_w, %bi : i8
  %i1_w = arith.cmpi eq, %w1_w, %bn : i8
  %i2_w = arith.cmpi eq, %w2_w, %bf : i8
  %ia_w = arith.andi %i0_w, %i1_w : i1
  %inf_w = arith.andi %ia_w, %i2_w : i1
  %n0_w = arith.cmpi eq, %w0_w, %bn : i8
  %n1_w = arith.cmpi eq, %w1_w, %ba : i8
  %n2_w = arith.cmpi eq, %w2_w, %bn : i8
  %na_w = arith.andi %n0_w, %n1_w : i1
  %nan_w = arith.andi %na_w, %n2_w : i1
  %sinf_w = arith.select %ism_s, %ninf, %pinf : i64
  %fv_w = arith.select %inf_w, %sinf_w, %qnan : i64
  %spec_w = arith.ori %inf_w, %nan_w : i1
  cf.cond_br %spec_w, ^float(%fv_w : i64), ^radixq
^radixq:
  %gt2_r = arith.cmpi sgt, %bl_s, %k2 : i64
  cf.cond_br %gt2_r, ^radix0, ^decimal
^radix0:
  %r0_r = func.call @tm_ld(%body_s, %k0) : (!llvm.ptr, i64) -> i8
  %r1_r = func.call @tm_ld(%body_s, %k1) : (!llvm.ptr, i64) -> i8
  %z_r = arith.cmpi eq, %r0_r, %b0 : i8
  %x_r = arith.cmpi eq, %r1_r, %bx : i8
  %o_r = arith.cmpi eq, %r1_r, %bo : i8
  %b_r = arith.cmpi eq, %r1_r, %bb : i8
  %xo_r = arith.ori %x_r, %o_r : i1
  %xob_r = arith.ori %xo_r, %b_r : i1
  %rad_r = arith.andi %z_r, %xob_r : i1
  cf.cond_br %rad_r, ^radix, ^decimal
^radix:
  cf.cond_br %sg_s, ^fail(%e12 : i32), ^radix1
^radix1:
  %k8b_x = arith.constant 8 : i64
  %b8_x = arith.select %o_r, %k8b_x, %k2 : i64
  %base_x = arith.select %x_r, %k16, %b8_x : i64
  %dg_x = func.call @tm_off(%body_s, %k2) : (!llvm.ptr, i64) -> !llvm.ptr
  %dl_x = arith.subi %bl_s, %k2 : i64
  %m_x = func.call @tm_strip(%dg_x, %dl_x, %scr) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  %bad_x = arith.cmpi slt, %m_x, %k0 : i64
  cf.cond_br %bad_x, ^fail(%e11 : i32), ^radix2
^radix2:
  %v_y, %ov_y, %cn_y = func.call @tm_readint(%scr, %m_x, %base_x, %f1) : (!llvm.ptr, i64, i64, i1) -> (i64, i1, i64)
  %part_y = arith.cmpi ne, %cn_y, %m_x : i64
  cf.cond_br %part_y, ^fail(%e13 : i32), ^radix3
^radix3:
  %big_z = arith.cmpi ugt, %v_y, %max : i64
  %tl_z = arith.ori %ov_y, %big_z : i1
  cf.cond_br %tl_z, ^fail(%e14 : i32), ^int(%v_y : i64)
^decimal:
  %m_d = func.call @tm_strip(%t, %len, %scr) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  %bad_d = arith.cmpi slt, %m_d, %k0 : i64
  cf.cond_br %bad_d, ^fail(%e11 : i32), ^dec1
^dec1:
  %hd_1 = func.call @tm_has(%scr, %m_d, %dot) : (!llvm.ptr, i64, i8) -> i1
  %he_1 = func.call @tm_has(%scr, %m_d, %be) : (!llvm.ptr, i64, i8) -> i1
  %hE_1 = func.call @tm_has(%scr, %m_d, %bE) : (!llvm.ptr, i64, i8) -> i1
  %h1_1 = arith.ori %hd_1, %he_1 : i1
  %isf_1 = arith.ori %h1_1, %hE_1 : i1
  cf.cond_br %isf_1, ^strtod, ^decint
^strtod:
  func.call @tm_st(%scr, %m_d, %nul) : (!llvm.ptr, i64, i8) -> ()
  %one_t = arith.constant 1 : i64
  %slot_t = llvm.alloca %one_t x !llvm.ptr : (i64) -> !llvm.ptr
  %dv_t = func.call @strtod(%scr, %slot_t) : (!llvm.ptr, !llvm.ptr) -> f64
  %ep_t = llvm.load %slot_t : !llvm.ptr -> !llvm.ptr
  %ei_t = llvm.ptrtoint %ep_t : !llvm.ptr to i64
  %si_t = llvm.ptrtoint %scr : !llvm.ptr to i64
  %used_t = arith.subi %ei_t, %si_t : i64
  %all_t = arith.cmpi eq, %used_t, %m_d : i64
  %bits_t = arith.bitcast %dv_t : f64 to i64
  cf.cond_br %all_t, ^float(%bits_t : i64), ^fail(%e15 : i32)
^decint:
  %c0_i = func.call @tm_ld(%scr, %k0) : (!llvm.ptr, i64) -> i8
  %sp_i = arith.cmpi eq, %c0_i, %plus : i8
  %sm_i = arith.cmpi eq, %c0_i, %minus : i8
  %sg_i = arith.ori %sp_i, %sm_i : i1
  %so_i = arith.extui %sg_i : i1 to i64
  %dl_i = arith.subi %m_d, %so_i : i64
  %long_i = arith.cmpi sgt, %dl_i, %k1 : i64
  cf.cond_br %long_i, ^lead, ^decint2
^lead:
  %l0_l = func.call @tm_ld(%scr, %so_i) : (!llvm.ptr, i64) -> i8
  %lz_l = arith.cmpi eq, %l0_l, %b0 : i8
  cf.cond_br %lz_l, ^fail(%e16 : i32), ^decint2
^decint2:
  %v_2, %ov_2, %cn_2 = func.call @tm_readint(%scr, %m_d, %k10, %t1) : (!llvm.ptr, i64, i64, i1) -> (i64, i1, i64)
  %part_2 = arith.cmpi ne, %cn_2, %m_d : i64
  cf.cond_br %part_2, ^fail(%e17 : i32), ^decint3
^decint3:
  %small_3 = arith.select %sm_i, %e18, %e19 : i32
  cf.cond_br %ov_2, ^fail(%small_3 : i32), ^int(%v_2 : i64)
^int(%iv: i64):
  func.call @tm_wr(%s, %k14, %k2) : (!llvm.ptr, i64, i64) -> ()
  func.call @tm_wr(%s, %k15, %iv) : (!llvm.ptr, i64, i64) -> ()
  return %z : i32
^float(%fv: i64):
  func.call @tm_wr(%s, %k14, %k3) : (!llvm.ptr, i64, i64) -> ()
  func.call @tm_wr(%s, %k15, %fv) : (!llvm.ptr, i64, i64) -> ()
  return %z : i32
^fail(%code: i32):
  return %code : i32
}

// ---- the document ----
func.func @nixev_ts_toml_scan(%s: !llvm.ptr) -> i32 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k2 = arith.constant 2 : i64
  %k3 = arith.constant 3 : i64
  %k4 = arith.constant 4 : i64
  %k5 = arith.constant 5 : i64
  %k6 = arith.constant 6 : i64
  %k7 = arith.constant 7 : i64
  %k8 = arith.constant 8 : i64
  %k9 = arith.constant 9 : i64
  %k10 = arith.constant 10 : i64
  %k12 = arith.constant 12 : i64
  %k13 = arith.constant 13 : i64
  %k14 = arith.constant 14 : i64
  %k15 = arith.constant 15 : i64
  %z = arith.constant 0 : i32
  %e20 = arith.constant 20 : i32
  %e21 = arith.constant 21 : i32
  %e22 = arith.constant 22 : i32
  %e23 = arith.constant 23 : i32
  %e24 = arith.constant 24 : i32
  %e25 = arith.constant 25 : i32
  %e26 = arith.constant 26 : i32
  %e27 = arith.constant 27 : i32
  %e28 = arith.constant 28 : i32
  %lb = arith.constant 91 : i8
  %rb = arith.constant 93 : i8
  %lc = arith.constant 123 : i8
  %rc = arith.constant 125 : i8
  %eq = arith.constant 61 : i8
  %comma = arith.constant 44 : i8
  %dq = arith.constant 34 : i8
  %sq = arith.constant 39 : i8
  %nul = arith.constant 0 : i8
  %s1 = arith.constant 1 : i8
  %s2 = arith.constant 2 : i8
  %bt = arith.constant 116 : i8
  %br = arith.constant 114 : i8
  %bu = arith.constant 117 : i8
  %be = arith.constant 101 : i8
  %bf = arith.constant 102 : i8
  %ba = arith.constant 97 : i8
  %bl = arith.constant 108 : i8
  %bs = arith.constant 115 : i8
  %t1 = arith.constant 1 : i1
  %bare = llvm.mlir.addressof @tm_bare : !llvm.ptr
  cf.br ^top
^top:
  %e_t = func.call @tm_wsall(%s) : (!llvm.ptr) -> i32
  %bad_t = arith.cmpi ne, %e_t, %z : i32
  cf.cond_br %bad_t, ^fail(%e_t : i32), ^top2
^top2:
  %eof_2 = func.call @tm_eof(%s) : (!llvm.ptr) -> i1
  cf.cond_br %eof_2, ^ok, ^top3
^top3:
  %hdr_3 = func.call @tm_pk(%s, %k0, %lb) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %hdr_3, ^hdr, ^kvtop
^hdr:
  %aot_h = func.call @tm_pk(%s, %k1, %lb) : (!llvm.ptr, i64, i8) -> i1
  %skip_h = arith.select %aot_h, %k2, %k1 : i64
  func.call @tm_adv(%s, %skip_h) : (!llvm.ptr, i64) -> ()
  %ek_h = func.call @tm_key(%s) : (!llvm.ptr) -> i32
  %bk_h = arith.cmpi ne, %ek_h, %z : i32
  cf.cond_br %bk_h, ^fail(%ek_h : i32), ^hdr2
^hdr2:
  func.call @tm_wsinline(%s) : (!llvm.ptr) -> ()
  %r0_2 = func.call @tm_pk(%s, %k0, %rb) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %aot_h, ^hdr_aot, ^hdr_one
^hdr_aot:
  %r1_a = func.call @tm_pk(%s, %k1, %rb) : (!llvm.ptr, i64, i8) -> i1
  %rr_a = arith.andi %r0_2, %r1_a : i1
  cf.cond_br %rr_a, ^hdr3(%k2 : i64), ^fail(%e24 : i32)
^hdr_one:
  cf.cond_br %r0_2, ^hdr3(%k1 : i64), ^fail(%e25 : i32)
^hdr3(%close: i64):
  func.call @tm_adv(%s, %close) : (!llvm.ptr, i64) -> ()
  %aoti_3 = arith.extui %aot_h : i1 to i64
  func.call @tm_ev0(%s, %k10, %aoti_3) : (!llvm.ptr, i64, i64) -> ()
  func.call @tm_wsinline(%s) : (!llvm.ptr) -> ()
  %ec_3 = func.call @tm_comment(%s) : (!llvm.ptr) -> i32
  %bc_3 = arith.cmpi ne, %ec_3, %z : i32
  cf.cond_br %bc_3, ^fail(%ec_3 : i32), ^hdr4
^hdr4:
  %le_4 = func.call @tm_lineend(%s) : (!llvm.ptr) -> i1
  cf.cond_br %le_4, ^top, ^fail(%e26 : i32)
^kvtop:
  %ek_k = func.call @tm_key(%s) : (!llvm.ptr) -> i32
  %bk_k = arith.cmpi ne, %ek_k, %z : i32
  cf.cond_br %bk_k, ^fail(%ek_k : i32), ^kv2
^kv2:
  func.call @tm_wsinline(%s) : (!llvm.ptr) -> ()
  %iseq_2 = func.call @tm_pk(%s, %k0, %eq) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %iseq_2, ^kv3, ^fail(%e27 : i32)
^kv3:
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  func.call @tm_wsinline(%s) : (!llvm.ptr) -> ()
  cf.br ^value
^value:
  %c_v = func.call @tm_peek(%s, %k0) : (!llvm.ptr, i64) -> i8
  %isdq_v = arith.cmpi eq, %c_v, %dq : i8
  cf.cond_br %isdq_v, ^vbasic, ^v1
^v1:
  %issq_1 = arith.cmpi eq, %c_v, %sq : i8
  cf.cond_br %issq_1, ^vlit, ^v2
^v2:
  // true / false not followed by a bare-key character
  %t0_2 = func.call @tm_pk(%s, %k0, %bt) : (!llvm.ptr, i64, i8) -> i1
  %t1_2 = func.call @tm_pk(%s, %k1, %br) : (!llvm.ptr, i64, i8) -> i1
  %t2_2 = func.call @tm_pk(%s, %k2, %bu) : (!llvm.ptr, i64, i8) -> i1
  %t3_2 = func.call @tm_pk(%s, %k3, %be) : (!llvm.ptr, i64, i8) -> i1
  %c4_2 = func.call @tm_peek(%s, %k4) : (!llvm.ptr, i64) -> i8
  %b4_2 = func.call @tm_is(%bare, %c4_2) : (!llvm.ptr, i8) -> i1
  %nb4_2 = arith.xori %b4_2, %t1 : i1
  %ta_2 = arith.andi %t0_2, %t1_2 : i1
  %tb_2 = arith.andi %ta_2, %t2_2 : i1
  %tc_2 = arith.andi %tb_2, %t3_2 : i1
  %true_2 = arith.andi %tc_2, %nb4_2 : i1
  cf.cond_br %true_2, ^vbool(%k4, %k1 : i64, i64), ^v3
^v3:
  %f0_3 = func.call @tm_pk(%s, %k0, %bf) : (!llvm.ptr, i64, i8) -> i1
  %f1_3 = func.call @tm_pk(%s, %k1, %ba) : (!llvm.ptr, i64, i8) -> i1
  %f2_3 = func.call @tm_pk(%s, %k2, %bl) : (!llvm.ptr, i64, i8) -> i1
  %f3_3 = func.call @tm_pk(%s, %k3, %bs) : (!llvm.ptr, i64, i8) -> i1
  %f4_3 = func.call @tm_pk(%s, %k4, %be) : (!llvm.ptr, i64, i8) -> i1
  %c5_3 = func.call @tm_peek(%s, %k5) : (!llvm.ptr, i64) -> i8
  %b5_3 = func.call @tm_is(%bare, %c5_3) : (!llvm.ptr, i8) -> i1
  %nb5_3 = arith.xori %b5_3, %t1 : i1
  %fa_3 = arith.andi %f0_3, %f1_3 : i1
  %fb_3 = arith.andi %fa_3, %f2_3 : i1
  %fc_3 = arith.andi %fb_3, %f3_3 : i1
  %fd_3 = arith.andi %fc_3, %f4_3 : i1
  %false_3 = arith.andi %fd_3, %nb5_3 : i1
  cf.cond_br %false_3, ^vbool(%k5, %k0 : i64, i64), ^v4
^v4:
  %isarr_4 = arith.cmpi eq, %c_v, %lb : i8
  cf.cond_br %isarr_4, ^varr, ^v5
^v5:
  %istab_5 = arith.cmpi eq, %c_v, %lc : i8
  cf.cond_br %istab_5, ^vtab, ^v6
^v6:
  %isdate_6 = func.call @tm_isdate(%s) : (!llvm.ptr) -> i1
  cf.cond_br %isdate_6, ^vdate, ^vnum
^vbasic:
  %eb_b = func.call @tm_basic(%s) : (!llvm.ptr) -> i32
  %bb_b = arith.cmpi ne, %eb_b, %z : i32
  cf.cond_br %bb_b, ^fail(%eb_b : i32), ^vbasic2
^vbasic2:
  %wp_b2 = func.call @tm_rp(%s, %k12) : (!llvm.ptr, i64) -> !llvm.ptr
  %wn_b2 = func.call @tm_rd(%s, %k13) : (!llvm.ptr, i64) -> i64
  %hn_b2 = func.call @tm_has(%wp_b2, %wn_b2, %nul) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %hn_b2, ^fail(%e20 : i32), ^vstr(%k1 : i64)
^vlit:
  %el_l = func.call @tm_literal(%s) : (!llvm.ptr) -> i32
  %bl_l = arith.cmpi ne, %el_l, %z : i32
  cf.cond_br %bl_l, ^fail(%el_l : i32), ^vstr(%k1 : i64)
^vdate:
  func.call @tm_datetime(%s) : (!llvm.ptr) -> ()
  cf.br ^vstr(%k5 : i64)
^vstr(%kind: i64):
  %wp_s = func.call @tm_rp(%s, %k12) : (!llvm.ptr, i64) -> !llvm.ptr
  %wn_s = func.call @tm_rd(%s, %k13) : (!llvm.ptr, i64) -> i64
  func.call @tm_ev(%s, %kind, %wp_s, %wn_s) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  cf.br ^after
^vbool(%adv: i64, %bv: i64):
  func.call @tm_adv(%s, %adv) : (!llvm.ptr, i64) -> ()
  func.call @tm_ev0(%s, %k4, %bv) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^after
^vnum:
  %en_n = func.call @tm_number(%s) : (!llvm.ptr) -> i32
  %bn_n = arith.cmpi ne, %en_n, %z : i32
  cf.cond_br %bn_n, ^fail(%en_n : i32), ^vnum2
^vnum2:
  %kd_n2 = func.call @tm_rd(%s, %k14) : (!llvm.ptr, i64) -> i64
  %vv_n2 = func.call @tm_rd(%s, %k15) : (!llvm.ptr, i64) -> i64
  func.call @tm_ev0(%s, %kd_n2, %vv_n2) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^after
^varr:
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  func.call @tm_push(%s, %s1) : (!llvm.ptr, i8) -> ()
  func.call @tm_ev0(%s, %k6, %k0) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^arrelem
^arrelem:
  %ew_ae = func.call @tm_wsall(%s) : (!llvm.ptr) -> i32
  %bw_ae = arith.cmpi ne, %ew_ae, %z : i32
  cf.cond_br %bw_ae, ^fail(%ew_ae : i32), ^arrelem2
^arrelem2:
  %cl_a2 = func.call @tm_pk(%s, %k0, %rb) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %cl_a2, ^arrclose, ^value
^arrclose:
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  func.call @tm_pop(%s) : (!llvm.ptr) -> ()
  func.call @tm_ev0(%s, %k7, %k0) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^after
^vtab:
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  func.call @tm_push(%s, %s2) : (!llvm.ptr, i8) -> ()
  func.call @tm_ev0(%s, %k8, %k0) : (!llvm.ptr, i64, i64) -> ()
  func.call @tm_wsinline(%s) : (!llvm.ptr) -> ()
  %cl_vt = func.call @tm_pk(%s, %k0, %rc) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %cl_vt, ^tabclose, ^tabkey
^tabkey:
  %ek_tk = func.call @tm_key(%s) : (!llvm.ptr) -> i32
  %bk_tk = arith.cmpi ne, %ek_tk, %z : i32
  cf.cond_br %bk_tk, ^fail(%ek_tk : i32), ^tabkey2
^tabkey2:
  func.call @tm_wsinline(%s) : (!llvm.ptr) -> ()
  %iseq_t2 = func.call @tm_pk(%s, %k0, %eq) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %iseq_t2, ^kv3, ^fail(%e22 : i32)
^tabclose:
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  func.call @tm_pop(%s) : (!llvm.ptr) -> ()
  func.call @tm_ev0(%s, %k9, %k0) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^after
^after:
  %top_a = func.call @tm_top(%s) : (!llvm.ptr) -> i8
  %indoc_a = arith.cmpi eq, %top_a, %nul : i8
  cf.cond_br %indoc_a, ^afterdoc, ^after2
^after2:
  %inarr_a2 = arith.cmpi eq, %top_a, %s1 : i8
  cf.cond_br %inarr_a2, ^afterarr, ^aftertab
^afterdoc:
  func.call @tm_wsinline(%s) : (!llvm.ptr) -> ()
  %ec_ad = func.call @tm_comment(%s) : (!llvm.ptr) -> i32
  %bc_ad = arith.cmpi ne, %ec_ad, %z : i32
  cf.cond_br %bc_ad, ^fail(%ec_ad : i32), ^afterdoc2
^afterdoc2:
  %le_ad2 = func.call @tm_lineend(%s) : (!llvm.ptr) -> i1
  cf.cond_br %le_ad2, ^top, ^fail(%e28 : i32)
^afterarr:
  %ew_aa = func.call @tm_wsall(%s) : (!llvm.ptr) -> i32
  %bw_aa = arith.cmpi ne, %ew_aa, %z : i32
  cf.cond_br %bw_aa, ^fail(%ew_aa : i32), ^afterarr2
^afterarr2:
  %cm_aa2 = func.call @tm_pk(%s, %k0, %comma) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %cm_aa2, ^arrnext, ^afterarr3
^arrnext:
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  cf.br ^arrelem
^afterarr3:
  %cl_aa3 = func.call @tm_pk(%s, %k0, %rb) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %cl_aa3, ^arrclose, ^fail(%e21 : i32)
^aftertab:
  func.call @tm_wsinline(%s) : (!llvm.ptr) -> ()
  %cm_at = func.call @tm_pk(%s, %k0, %comma) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %cm_at, ^tabnext, ^aftertab2
^tabnext:
  func.call @tm_adv(%s, %k1) : (!llvm.ptr, i64) -> ()
  cf.br ^tabkey
^aftertab2:
  %cl_at2 = func.call @tm_pk(%s, %k0, %rc) : (!llvm.ptr, i64, i8) -> i1
  cf.cond_br %cl_at2, ^tabclose, ^fail(%e23 : i32)
^ok:
  return %z : i32
^fail(%code: i32):
  return %code : i32
}

// ---- the messages ----
// "while parsing TOML: " pre w post [" (line " N ")"]: one combine of slices of the word blob, the window and the
// line's digits, drained once into room the caller reserved (200 + wn); the bytes written
memref.global "private" constant @tm_mblob : memref<905xi8> = dense<"0x7768696c652070617273696e6720544f4d4c3a2020286c696e652029636f6e74726f6c2063686172616374657220696e20636f6d6d656e74696e76616c696420756e69636f646520657363617065696e76616c6964206573636170652073657175656e636520275c756e7465726d696e61746564206d756c74692d6c696e6520737472696e67756e7465726d696e6174656420737472696e67756e7465726d696e61746564206d756c74692d6c696e65206c69746572616c20737472696e67756e7465726d696e61746564206c69746572616c20737472696e6765787065637465642061206b65796b657920636f6e7461696e732061204e554c2062797465657870656374656420612076616c7565696e76616c696420756e64657273636f726520696e206e756d6265727369676e206e6f7420616c6c6f776564206f6e206e6f6e2d646563696d616c20696e7465676572696e76616c696420696e7465676572746f6f206c6172676520696e7465676572696e76616c696420666c6f617420276c656164696e67207a65726f7320617265206e6f7420616c6c6f776564696e76616c69642076616c756520275b6572726f725d20746f6d6c3a3a70617273655f6465635f696e74656765723a20746f6f20736d616c6c20696e74656765723a2063757272656e74206d696e20646967697473203d202d325e36335b6572726f725d20746f6d6c3a3a70617273655f6465635f696e74656765723a20746f6f206c6172676520696e74656765723a2063757272656e74206d617820646967697473203d20325e3633737472696e6720636f6e7461696e732061204e554c2062797465657870656374656420272c27206f7220275d2720696e206172726179657870656374656420273d2720696e20696e6c696e65207461626c65657870656374656420272c27206f7220277d2720696e20696e6c696e65207461626c65657870656374656420275d5d27657870656374656420275d276578706563746564206e65776c696e65206166746572207461626c6520686561646572657870656374656420273d27206166746572206b65796578706563746564206e65776c696e652061667465722076616c756563616e6e6f74207265646566696e65206b657920276475706c6963617465206b657920277461626c652027446174657320616e642074696d657320617265206e6f7420737570706f72746564272720616c726561647920646566696e6564">
memref.global "private" constant @tm_moff : memref<38xi32> = dense<[0, 20, 27, 28, 56, 78, 104, 134, 153, 191, 218, 232, 255, 271, 299, 338, 353, 370, 385, 414, 429, 507, 584, 610, 638, 666, 701, 714, 726, 761, 783, 811, 832, 847, 854, 887, 888, 905]>
memref.global "private" constant @tm_mlen : memref<38xi32> = dense<[20, 7, 1, 28, 22, 26, 30, 19, 38, 27, 14, 23, 16, 28, 39, 15, 17, 15, 29, 15, 78, 77, 26, 28, 28, 35, 13, 12, 35, 22, 28, 21, 15, 7, 33, 1, 17, 0]>
memref.global "private" constant @tm_mpost : memref<33xi32> = dense<[37, 37, 37, 35, 37, 37, 37, 37, 37, 37, 37, 37, 37, 37, 37, 35, 37, 35, 37, 37, 37, 37, 37, 37, 37, 37, 37, 37, 37, 35, 35, 36, 37]>
memref.global "private" constant @tm_mline : memref<33xi32> = dense<[0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0]>
memref.global "private" constant @tm_pow : memref<19xi64> = dense<[1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000, 10000000000, 100000000000, 1000000000000, 10000000000000, 100000000000000, 1000000000000000, 10000000000000000, 100000000000000000, 1000000000000000000]>
func.func private @tm_bounds(%wid: index) -> (index, index) {
  %og = memref.get_global @tm_moff : memref<38xi32>
  %offs = trikeshed.text %og : memref<38xi32> -> !s32
  %lg = memref.get_global @tm_mlen : memref<38xi32>
  %lens = trikeshed.text %lg : memref<38xi32> -> !s32
  %o = trikeshed.at %offs[%wid] : !s32, index -> i32
  %l = trikeshed.at %lens[%wid] : !s32, index -> i32
  %oi = arith.index_cast %o : i32 to index
  %li = arith.index_cast %l : i32 to index
  return %oi, %li : index, index
}
func.func @nixev_ts_toml_msg(%code: i64, %line: i64, %wp: !llvm.ptr, %wn: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c18 = arith.constant 18 : index
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %ten = arith.constant 10 : i64
  %d0 = arith.constant 48 : i8
  %z32 = arith.constant 0 : i32
  %u = llvm.mlir.undef : !d
  %ia = llvm.insertvalue %into, %u[0] : !d
  %ib = llvm.insertvalue %into, %ia[1] : !d
  %ic = llvm.insertvalue %z, %ib[2] : !d
  %ie = llvm.insertvalue %cap, %ic[3, 0] : !d
  %ig = llvm.insertvalue %one, %ie[4, 0] : !d
  %mi = builtin.unrealized_conversion_cast %ig : !d to !m8
  %wa = llvm.insertvalue %wp, %u[0] : !d
  %wb = llvm.insertvalue %wp, %wa[1] : !d
  %wc = llvm.insertvalue %z, %wb[2] : !d
  // the window only for the codes whose message names one (those with a closing word)
  %ci0 = arith.index_cast %code : i64 to index
  %tg0 = memref.get_global @tm_mpost : memref<33xi32>
  %posts0 = trikeshed.text %tg0 : memref<33xi32> -> !s32
  %pid0 = trikeshed.at %posts0[%ci0] : !s32, index -> i32
  %none = arith.constant 37 : i32
  %hasw = arith.cmpi ne, %pid0, %none : i32
  %wnn = arith.select %hasw, %wn, %z : i64
  %we = llvm.insertvalue %wnn, %wc[3, 0] : !d
  %wf = llvm.insertvalue %one, %we[4, 0] : !d
  %wm = builtin.unrealized_conversion_cast %wf : !d to !m8
  %w = builtin.unrealized_conversion_cast %wm : !m8 to !text
  %bg = memref.get_global @tm_mblob : memref<905xi8>
  %blob = trikeshed.text %bg : memref<905xi8> -> !text
  %pg = memref.get_global @tm_pow : memref<19xi64>
  %powers = trikeshed.text %pg : memref<19xi64> -> !s64
  %above = trikeshed.slice %powers[%c1, %c18] : !s64 -> !s64
  %ci = arith.index_cast %code : i64 to index
  %hs, %hl = func.call @tm_bounds(%c0) : (index) -> (index, index)
  %head = trikeshed.slice %blob[%hs, %hl] : !text -> !text
  %preid = arith.addi %ci, %c2 : index
  %ps, %pl = func.call @tm_bounds(%preid) : (index) -> (index, index)
  %pre = trikeshed.slice %blob[%ps, %pl] : !text -> !text
  %tg = memref.get_global @tm_mpost : memref<33xi32>
  %posts = trikeshed.text %tg : memref<33xi32> -> !s32
  %postid32 = trikeshed.at %posts[%ci] : !s32, index -> i32
  %postid = arith.index_cast %postid32 : i32 to index
  %qs, %ql = func.call @tm_bounds(%postid) : (index) -> (index, index)
  %post = trikeshed.slice %blob[%qs, %ql] : !text -> !text
  %lg = memref.get_global @tm_mline : memref<33xi32>
  %lines = trikeshed.text %lg : memref<33xi32> -> !s32
  %hasl32 = trikeshed.at %lines[%ci] : !s32, index -> i32
  %hasl = arith.cmpi ne, %hasl32, %z32 : i32
  %ls, %ll = func.call @tm_bounds(%c1) : (index) -> (index, index)
  %lll = arith.select %hasl, %ll, %c0 : index
  %lopen = trikeshed.slice %blob[%ls, %lll] : !text -> !text
  %cs, %cl = func.call @tm_bounds(%c2) : (index) -> (index, index)
  %cll = arith.select %hasl, %cl, %c0 : index
  %lclose = trikeshed.slice %blob[%cs, %cll] : !text -> !text
  %count1 = trikeshed.fold %above, %c1 : !s64, index -> index {
  ^bb0(%acc: index, %p: i64):
    %reach = arith.cmpi uge, %line, %p : i64
    %more = arith.addi %acc, %c1 : index
    %rr = arith.select %reach, %more, %acc : index
    trikeshed.yield %rr : index
  }
  %count = arith.select %hasl, %count1, %c0 : index
  %digits = trikeshed.series %count : !text {
  ^bb0(%k: index):
    %last = arith.subi %count, %c1 : index
    %e = arith.subi %last, %k : index
    %p = trikeshed.at %powers[%e] : !s64, index -> i64
    %q = arith.divui %line, %p : i64
    %dd = arith.remui %q, %ten : i64
    %d8 = arith.trunci %dd : i64 to i8
    %ch = arith.addi %d8, %d0 : i8
    trikeshed.yield %ch : i8
  }
  %all = trikeshed.combine %head, %pre, %w, %post, %lopen, %digits, %lclose : !text, !text, !text, !text, !text, !text, !text -> !text
  %end = trikeshed.drain %all, %mi : !text, !m8 -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}
