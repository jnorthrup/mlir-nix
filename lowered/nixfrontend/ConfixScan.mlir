// The Nix delimiter scan (nixfe::confix::Bands), the body of the confix dialect's confix.bands op: the lexer's state
// machine (Parser.cpp's DEFAULT, STRING, IND_STRING, INPATH, INPATH_SLASH, with the same stack) without tokens, only the
// transitions and the delimiters.  The character classes are the tables below (Nix/LexRules.h's isIdStart / isIdChar /
// isPathChar / isDigit, and the stop bytes of a "..." or ''...'' string); the longest-match choice among the rules that
// can begin a token stays in LexRules.h, shared with the lexer, called back per general token (nixfe_confix_match).
//
// confix_scan_nix reads and writes the record of Confix.td's confix.bands (the caller owns it): src, n, start, rooted,
// span, kind, stmts, ends, rows, nends, rowCap, endCap.  It returns 0 when the source balances, 1 when it does not, 2
// when the room ran out (the caller doubles the arrays and scans again, as confix.scan's YAML retry on Room).  The band
// columns are written as the scan meets delimiters: span is open << 32 | close (TwInt), kind the BandKind byte, stmts
// first << 32 | count into ends.  The open bands, their owed semicolons and the pending ends are the state struct's
// stacks (the C++ Layers); the arrays are sized for the text (a band, a state or an end needs at least one byte).
//
// Lowered at build time by lib/CMakeLists.txt's mlnix_lower_trikeshed (the stock buffer pipeline, its cf loops lifted to
// scf first) and linked into NixFrontend; the C++ bridge (lib/Frontend/Confix.cpp) sizes the Bands and adopts the rows.

!rec = !llvm.struct<(ptr, i64, i64, i64, ptr, ptr, ptr, ptr, i64, i64, i64, i64)>
!stt = !llvm.struct<(i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr)>

llvm.mlir.global internal constant @nx_idstart(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @nx_idchar(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @nx_idcharnq(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @nx_pathchar(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @nx_digit(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @nx_stopdq(dense<[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @nx_stopind(dense<[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @nx_ws(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>

func.func private @nixfe_confix_match(!llvm.ptr, i64, i64) -> i64

// ---- the record and the state, read and written by field (the state's scalars are i64, its pointers ptr) ----
func.func private @nx_rd(%s: !llvm.ptr, %k: i64) -> i64 {
  %p = llvm.getelementptr %s[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %p : !llvm.ptr -> i64
  llvm.return %v : i64
}
func.func private @nx_wr(%s: !llvm.ptr, %k: i64, %v: i64) {
  %p = llvm.getelementptr %s[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %p : i64, !llvm.ptr
  llvm.return
}
func.func private @nx_rp(%s: !llvm.ptr, %k: i64) -> !llvm.ptr {
  %p = llvm.getelementptr %s[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %p : !llvm.ptr -> !llvm.ptr
  llvm.return %v : !llvm.ptr
}
func.func private @nx_wp(%s: !llvm.ptr, %k: i64, %v: !llvm.ptr) {
  %p = llvm.getelementptr %s[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %p : !llvm.ptr, !llvm.ptr
  llvm.return
}
func.func private @nx_a64(%p: !llvm.ptr, %i: i64) -> i64 {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %q : !llvm.ptr -> i64
  llvm.return %v : i64
}
func.func private @nx_a8(%p: !llvm.ptr, %i: i64) -> i8 {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %v = llvm.load %q : !llvm.ptr -> i8
  llvm.return %v : i8
}
func.func private @nx_a32(%p: !llvm.ptr, %i: i64) -> i32 {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i32
  %v = llvm.load %q : !llvm.ptr -> i32
  llvm.return %v : i32
}
func.func private @nx_s64(%p: !llvm.ptr, %i: i64, %v: i64) {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %q : i64, !llvm.ptr
  llvm.return
}
func.func private @nx_s8(%p: !llvm.ptr, %i: i64, %v: i8) {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %v, %q : i8, !llvm.ptr
  llvm.return
}
func.func private @nx_s32(%p: !llvm.ptr, %i: i64, %v: i32) {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i32
  llvm.store %v, %q : i32, !llvm.ptr
  llvm.return
}

// the byte at i, 0 past the end (lex::Rules::at)
func.func private @nx_at(%src: !llvm.ptr, %n: i64, %i: i64) -> i8 {
  %in = arith.cmpi ult, %i, %n : i64
  %z = arith.constant 0 : i8
  %c = scf.if %in -> (i8) {
    %p = llvm.getelementptr %src[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %v = llvm.load %p : !llvm.ptr -> i8
    scf.yield %v : i8
  } else {
    scf.yield %z : i8
  }
  llvm.return %c : i8
}
// whether a byte is in a class table
func.func private @nx_cls(%t: !llvm.ptr, %c: i8) -> i1 {
  %i = arith.extui %c : i8 to i32
  %p = llvm.getelementptr %t[%i] : (!llvm.ptr, i32) -> !llvm.ptr, i8
  %v = llvm.load %p : !llvm.ptr -> i8
  %z = arith.constant 0 : i8
  %r = arith.cmpi ne, %v, %z : i8
  llvm.return %r : i1
}
// the end of the run of class bytes from j (the character-class scanning loops)
func.func private @nx_run(%src: !llvm.ptr, %n: i64, %j: i64, %t: !llvm.ptr) -> i64 {
  %r = scf.while (%j0 = %j) : (i64) -> i64 {
    %in = arith.cmpi ult, %j0, %n : i64
    %c = func.call @nx_at(%src, %n, %j0) : (!llvm.ptr, i64, i64) -> i8
    %m = func.call @nx_cls(%t, %c) : (!llvm.ptr, i8) -> i1
    %go = arith.andi %in, %m : i1
    scf.condition(%go) %j0 : i64
  } do {
  ^bb0(%j1: i64):
    %one = arith.constant 1 : i64
    %j2 = arith.addi %j1, %one : i64
    scf.yield %j2 : i64
  }
  llvm.return %r : i64
}
// past a # comment's text, to its newline (not consumed)
func.func private @nx_skipline(%src: !llvm.ptr, %n: i64, %j: i64) -> i64 {
  %nl = arith.constant 10 : i8
  %cr = arith.constant 13 : i8
  %r = scf.while (%j0 = %j) : (i64) -> i64 {
    %in = arith.cmpi ult, %j0, %n : i64
    %c = func.call @nx_at(%src, %n, %j0) : (!llvm.ptr, i64, i64) -> i8
    %a = arith.cmpi ne, %c, %nl : i8
    %b = arith.cmpi ne, %c, %cr : i8
    %m = arith.andi %a, %b : i1
    %go = arith.andi %in, %m : i1
    scf.condition(%go) %j0 : i64
  } do {
  ^bb0(%j1: i64):
    %one = arith.constant 1 : i64
    %j2 = arith.addi %j1, %one : i64
    scf.yield %j2 : i64
  }
  llvm.return %r : i64
}
// {PATH_CHAR}*\/ : the run and its slash, or 0 (lex::Rules::mPathSeg)
func.func private @nx_pathseg(%src: !llvm.ptr, %n: i64, %i: i64) -> i64 {
  %t = llvm.mlir.addressof @nx_pathchar : !llvm.ptr
  %j = func.call @nx_run(%src, %n, %i, %t) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %c = func.call @nx_at(%src, %n, %j) : (!llvm.ptr, i64, i64) -> i8
  %sl = arith.constant 47 : i8
  %is = arith.cmpi eq, %c, %sl : i8
  %one = arith.constant 1 : i64
  %j1 = arith.addi %j, %one : i64
  %l = arith.subi %j1, %i : i64
  %z = arith.constant 0 : i64
  %r = arith.select %is, %l, %z : i64
  llvm.return %r : i64
}
// {PATH_CHAR}*(\/{PATH_CHAR}+)+\/? (lex::Rules::mPath)
func.func private @nx_path(%src: !llvm.ptr, %n: i64, %i: i64) -> i64 {
  %t = llvm.mlir.addressof @nx_pathchar : !llvm.ptr
  %j0 = func.call @nx_run(%src, %n, %i, %t) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %sl = arith.constant 47 : i8
  cf.br ^loop(%j0, %z, %z : i64, i64, i64)
^loop(%j: i64, %segs: i64, %end: i64):
  %cj = func.call @nx_at(%src, %n, %j) : (!llvm.ptr, i64, i64) -> i8
  %is = arith.cmpi eq, %cj, %sl : i8
  %j1 = arith.addi %j, %one : i64
  %cn = func.call @nx_at(%src, %n, %j1) : (!llvm.ptr, i64, i64) -> i8
  %pc = func.call @nx_cls(%t, %cn) : (!llvm.ptr, i8) -> i1
  %go = arith.andi %is, %pc : i1
  cf.cond_br %go, ^body, ^done
^body:
  %j2 = func.call @nx_run(%src, %n, %j1, %t) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %segs1 = arith.addi %segs, %one : i64
  cf.br ^loop(%j2, %segs1, %j2 : i64, i64, i64)
^done:
  %has = arith.cmpi ugt, %segs, %z : i64
  cf.cond_br %has, ^trail, ^zero
^zero:
  llvm.return %z : i64
^trail:
  %ce = func.call @nx_at(%src, %n, %end) : (!llvm.ptr, i64, i64) -> i8
  %ist = arith.cmpi eq, %ce, %sl : i8
  %end1 = arith.addi %end, %one : i64
  %e = arith.select %ist, %end1, %end : i64
  %l = arith.subi %e, %i : i64
  llvm.return %l : i64
}
// \/\*([^*]|\*+[^*/])*\*+\/ (lex::Rules::mLongComment)
func.func private @nx_longcomment(%src: !llvm.ptr, %n: i64, %i: i64) -> i64 {
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %two = arith.constant 2 : i64
  %sl = arith.constant 47 : i8
  %st = arith.constant 42 : i8
  %c0 = func.call @nx_at(%src, %n, %i) : (!llvm.ptr, i64, i64) -> i8
  %is0 = arith.cmpi eq, %c0, %sl : i8
  %i1 = arith.addi %i, %one : i64
  %c1 = func.call @nx_at(%src, %n, %i1) : (!llvm.ptr, i64, i64) -> i8
  %is1 = arith.cmpi eq, %c1, %st : i8
  %ok = arith.andi %is0, %is1 : i1
  cf.cond_br %ok, ^start, ^zero
^zero:
  llvm.return %z : i64
^start:
  %i2 = arith.addi %i, %two : i64
  cf.br ^loop(%i2 : i64)
^loop(%j: i64):
  %end = arith.cmpi uge, %j, %n : i64
  cf.cond_br %end, ^zero, ^body
^body:
  %c = func.call @nx_at(%src, %n, %j) : (!llvm.ptr, i64, i64) -> i8
  %is = arith.cmpi eq, %c, %st : i8
  cf.cond_br %is, ^stars(%j : i64), ^step
^step:
  %j1 = arith.addi %j, %one : i64
  cf.br ^loop(%j1 : i64)
^stars(%k: i64):
  %ck = func.call @nx_at(%src, %n, %k) : (!llvm.ptr, i64, i64) -> i8
  %isk = arith.cmpi eq, %ck, %st : i8
  cf.cond_br %isk, ^stars_next, ^after
^stars_next:
  %k1 = arith.addi %k, %one : i64
  cf.br ^stars(%k1 : i64)
^after:
  %ck2 = func.call @nx_at(%src, %n, %k) : (!llvm.ptr, i64, i64) -> i8
  %iss = arith.cmpi eq, %ck2, %sl : i8
  cf.cond_br %iss, ^found, ^eofchk
^found:
  %k2 = arith.addi %k, %one : i64
  %l = arith.subi %k2, %i : i64
  llvm.return %l : i64
^eofchk:
  %eof = arith.cmpi uge, %k, %n : i64
  cf.cond_br %eof, ^zero, ^resume
^resume:
  %k3 = arith.addi %k, %one : i64
  cf.br ^loop(%k3 : i64)
}
// whether the next token after j (blanks and comments between) is '{' (Scanner::braceNext)
func.func private @nx_bracenext(%src: !llvm.ptr, %n: i64, %j: i64) -> i1 {
  %t = llvm.mlir.addressof @nx_ws : !llvm.ptr
  %h = arith.constant 35 : i8
  %lb = arith.constant 123 : i8
  %one = arith.constant 1 : i64
  %z = arith.constant 0 : i64
  cf.br ^loop(%j : i64)
^loop(%j0: i64):
  %j1 = func.call @nx_run(%src, %n, %j0, %t) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %c = func.call @nx_at(%src, %n, %j1) : (!llvm.ptr, i64, i64) -> i8
  %ish = arith.cmpi eq, %c, %h : i8
  cf.cond_br %ish, ^hash, ^comment
^hash:
  %j2 = arith.addi %j1, %one : i64
  %j3 = func.call @nx_skipline(%src, %n, %j2) : (!llvm.ptr, i64, i64) -> i64
  cf.br ^loop(%j3 : i64)
^comment:
  %l = func.call @nx_longcomment(%src, %n, %j1) : (!llvm.ptr, i64, i64) -> i64
  %has = arith.cmpi ugt, %l, %z : i64
  cf.cond_br %has, ^skip, ^done
^skip:
  %j4 = arith.addi %j1, %l : i64
  cf.br ^loop(%j4 : i64)
^done:
  %r = arith.cmpi eq, %c, %lb : i8
  llvm.return %r : i1
}

// ---- the layers: the open bands, their owed semicolons, the pending ends (Nix/Confix.h's Layers) ----
func.func private @nx_push(%s: !llvm.ptr, %v: i64) {
  %c2 = arith.constant 2 : i64
  %c13 = arith.constant 13 : i64
  %sp = func.call @nx_rd(%s, %c2) : (!llvm.ptr, i64) -> i64
  %st = func.call @nx_rp(%s, %c13) : (!llvm.ptr, i64) -> !llvm.ptr
  %v8 = arith.trunci %v : i64 to i8
  func.call @nx_s8(%st, %sp, %v8) : (!llvm.ptr, i64, i8) -> ()
  %one = arith.constant 1 : i64
  %sp1 = arith.addi %sp, %one : i64
  func.call @nx_wr(%s, %c2, %sp1) : (!llvm.ptr, i64, i64) -> ()
  llvm.return
}
// (the helpers below name the state fields by their index: 2 sp, 3 lp, 4 np, 5 owedRoot, 6 r, 7 e, 9 rowCap,
//  10 endCap, 11 rooted, 14 stack, 15 pend, 16 span, 17 kind, 18 stmts, 19 ends)
func.func private @nx_open(%s: !llvm.ptr, %k: i64, %at: i64) -> i32 {
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c6 = arith.constant 6 : i64
  %c9 = arith.constant 9 : i64
  %c14 = arith.constant 14 : i64
  %c16 = arith.constant 16 : i64
  %c17 = arith.constant 17 : i64
  %c18 = arith.constant 18 : i64
  %c32 = arith.constant 32 : i64
  %one = arith.constant 1 : i64
  %z = arith.constant 0 : i64
  %two32 = arith.constant 2 : i32
  %z32 = arith.constant 0 : i32
  %r = func.call @nx_rd(%s, %c6) : (!llvm.ptr, i64) -> i64
  %cap = func.call @nx_rd(%s, %c9) : (!llvm.ptr, i64) -> i64
  %full = arith.cmpi uge, %r, %cap : i64
  cf.cond_br %full, ^room, ^body
^room:
  llvm.return %two32 : i32
^body:
  %span = func.call @nx_rp(%s, %c16) : (!llvm.ptr, i64) -> !llvm.ptr
  %sh = arith.shli %at, %c32 : i64
  func.call @nx_s64(%span, %r, %sh) : (!llvm.ptr, i64, i64) -> ()
  %kind = func.call @nx_rp(%s, %c17) : (!llvm.ptr, i64) -> !llvm.ptr
  %k8 = arith.trunci %k : i64 to i8
  func.call @nx_s8(%kind, %r, %k8) : (!llvm.ptr, i64, i8) -> ()
  %stmts = func.call @nx_rp(%s, %c18) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @nx_s64(%stmts, %r, %z) : (!llvm.ptr, i64, i64) -> ()
  %lp = func.call @nx_rd(%s, %c3) : (!llvm.ptr, i64) -> i64
  %stack = func.call @nx_rp(%s, %c14) : (!llvm.ptr, i64) -> !llvm.ptr
  %b = arith.muli %lp, %c3 : i64
  func.call @nx_s64(%stack, %b, %r) : (!llvm.ptr, i64, i64) -> ()
  %b1 = arith.addi %b, %one : i64
  func.call @nx_s64(%stack, %b1, %z) : (!llvm.ptr, i64, i64) -> ()
  %np = func.call @nx_rd(%s, %c4) : (!llvm.ptr, i64) -> i64
  %b2 = arith.addi %b, %c2 : i64
  func.call @nx_s64(%stack, %b2, %np) : (!llvm.ptr, i64, i64) -> ()
  %lp1 = arith.addi %lp, %one : i64
  func.call @nx_wr(%s, %c3, %lp1) : (!llvm.ptr, i64, i64) -> ()
  %r1 = arith.addi %r, %one : i64
  func.call @nx_wr(%s, %c6, %r1) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
}
func.func private @nx_close(%s: !llvm.ptr, %a: i64, %b: i64, %at: i64) -> i32 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c7 = arith.constant 7 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %c14 = arith.constant 14 : i64
  %c15 = arith.constant 15 : i64
  %c16 = arith.constant 16 : i64
  %c17 = arith.constant 17 : i64
  %c18 = arith.constant 18 : i64
  %c19 = arith.constant 19 : i64
  %c32 = arith.constant 32 : i64
  %one32 = arith.constant 1 : i32
  %two32 = arith.constant 2 : i32
  %z32 = arith.constant 0 : i32
  %lp = func.call @nx_rd(%s, %c3) : (!llvm.ptr, i64) -> i64
  %empty = arith.cmpi eq, %lp, %c0 : i64
  cf.cond_br %empty, ^fail, ^body
^fail:
  llvm.return %one32 : i32
^body:
  %top = arith.subi %lp, %c1 : i64
  %stack = func.call @nx_rp(%s, %c14) : (!llvm.ptr, i64) -> !llvm.ptr
  %b0 = arith.muli %top, %c3 : i64
  %row = func.call @nx_a64(%stack, %b0) : (!llvm.ptr, i64) -> i64
  %kind = func.call @nx_rp(%s, %c17) : (!llvm.ptr, i64) -> !llvm.ptr
  %k8 = func.call @nx_a8(%kind, %row) : (!llvm.ptr, i64) -> i8
  %k = arith.extui %k8 : i8 to i64
  %isa = arith.cmpi eq, %k, %a : i64
  %isb = arith.cmpi eq, %k, %b : i64
  %ok = arith.ori %isa, %isb : i1
  cf.cond_br %ok, ^match, ^fail
^match:
  %np = func.call @nx_rd(%s, %c4) : (!llvm.ptr, i64) -> i64
  %b2 = arith.addi %b0, %c2 : i64
  %from = func.call @nx_a64(%stack, %b2) : (!llvm.ptr, i64) -> i64
  %count = arith.subi %np, %from : i64
  %e = func.call @nx_rd(%s, %c7) : (!llvm.ptr, i64) -> i64
  %ecap = func.call @nx_rd(%s, %c10) : (!llvm.ptr, i64) -> i64
  %need = arith.addi %e, %count : i64
  %over = arith.cmpi ugt, %need, %ecap : i64
  cf.cond_br %over, ^room, ^write
^room:
  llvm.return %two32 : i32
^write:
  func.call @nx_wr(%s, %c3, %top) : (!llvm.ptr, i64, i64) -> ()
  %span = func.call @nx_rp(%s, %c16) : (!llvm.ptr, i64) -> !llvm.ptr
  %old = func.call @nx_a64(%span, %row) : (!llvm.ptr, i64) -> i64
  %open = arith.shrui %old, %c32 : i64
  %sh = arith.shli %open, %c32 : i64
  %new = arith.ori %sh, %at : i64
  func.call @nx_s64(%span, %row, %new) : (!llvm.ptr, i64, i64) -> ()
  %stmts = func.call @nx_rp(%s, %c18) : (!llvm.ptr, i64) -> !llvm.ptr
  %esh = arith.shli %e, %c32 : i64
  %stv = arith.ori %esh, %count : i64
  func.call @nx_s64(%stmts, %row, %stv) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^copy(%from, %e : i64, i64)
^copy(%j: i64, %w: i64):
  %done = arith.cmpi uge, %j, %np : i64
  cf.cond_br %done, ^copied, ^cbody
^cbody:
  %pend = func.call @nx_rp(%s, %c15) : (!llvm.ptr, i64) -> !llvm.ptr
  %v = func.call @nx_a64(%pend, %j) : (!llvm.ptr, i64) -> i64
  %v32 = arith.trunci %v : i64 to i32
  %ends = func.call @nx_rp(%s, %c19) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @nx_s32(%ends, %w, %v32) : (!llvm.ptr, i64, i32) -> ()
  %j1 = arith.addi %j, %c1 : i64
  %w1 = arith.addi %w, %c1 : i64
  cf.br ^copy(%j1, %w1 : i64, i64)
^copied:
  func.call @nx_wr(%s, %c7, %need) : (!llvm.ptr, i64, i64) -> ()
  func.call @nx_wr(%s, %c4, %from) : (!llvm.ptr, i64, i64) -> ()
  %rooted = func.call @nx_rd(%s, %c11) : (!llvm.ptr, i64) -> i64
  %isr = arith.cmpi ne, %rooted, %c0 : i64
  %bal = arith.cmpi eq, %top, %c0 : i64
  %set = arith.andi %isr, %bal : i1
  cf.cond_br %set, ^setstop, ^ok
^setstop:
  %stop = arith.addi %at, %c1 : i64
  func.call @nx_wr(%s, %c1, %stop) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^ok
^ok:
  llvm.return %z32 : i32
}
func.func private @nx_owe(%s: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c5 = arith.constant 5 : i64
  %c14 = arith.constant 14 : i64
  %lp = func.call @nx_rd(%s, %c3) : (!llvm.ptr, i64) -> i64
  %empty = arith.cmpi eq, %lp, %c0 : i64
  cf.cond_br %empty, ^root, ^top
^root:
  %oR = func.call @nx_rd(%s, %c5) : (!llvm.ptr, i64) -> i64
  %oR1 = arith.addi %oR, %c1 : i64
  func.call @nx_wr(%s, %c5, %oR1) : (!llvm.ptr, i64, i64) -> ()
  llvm.return
^top:
  %stack = func.call @nx_rp(%s, %c14) : (!llvm.ptr, i64) -> !llvm.ptr
  %top = arith.subi %lp, %c1 : i64
  %b = arith.muli %top, %c3 : i64
  %b1 = arith.addi %b, %c1 : i64
  %oT = func.call @nx_a64(%stack, %b1) : (!llvm.ptr, i64) -> i64
  %oT1 = arith.addi %oT, %c1 : i64
  func.call @nx_s64(%stack, %b1, %oT1) : (!llvm.ptr, i64, i64) -> ()
  llvm.return
}
func.func private @nx_semi(%s: !llvm.ptr, %at: i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c14 = arith.constant 14 : i64
  %c15 = arith.constant 15 : i64
  %lp = func.call @nx_rd(%s, %c3) : (!llvm.ptr, i64) -> i64
  %empty = arith.cmpi eq, %lp, %c0 : i64
  cf.cond_br %empty, ^root, ^top
^root:
  %oR = func.call @nx_rd(%s, %c5) : (!llvm.ptr, i64) -> i64
  %hasR = arith.cmpi ugt, %oR, %c0 : i64
  cf.cond_br %hasR, ^dec_root, ^ret
^dec_root:
  %oR1 = arith.subi %oR, %c1 : i64
  func.call @nx_wr(%s, %c5, %oR1) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^ret
^top:
  %stack = func.call @nx_rp(%s, %c14) : (!llvm.ptr, i64) -> !llvm.ptr
  %top = arith.subi %lp, %c1 : i64
  %b = arith.muli %top, %c3 : i64
  %b1 = arith.addi %b, %c1 : i64
  %oT = func.call @nx_a64(%stack, %b1) : (!llvm.ptr, i64) -> i64
  %hasT = arith.cmpi ugt, %oT, %c0 : i64
  cf.cond_br %hasT, ^dec_top, ^pend
^dec_top:
  %oT1 = arith.subi %oT, %c1 : i64
  func.call @nx_s64(%stack, %b1, %oT1) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^ret
^pend:
  %np = func.call @nx_rd(%s, %c4) : (!llvm.ptr, i64) -> i64
  %pend = func.call @nx_rp(%s, %c15) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @nx_s64(%pend, %np, %at) : (!llvm.ptr, i64, i64) -> ()
  %np1 = arith.addi %np, %c1 : i64
  func.call @nx_wr(%s, %c4, %np1) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^ret
^ret:
  llvm.return
}
func.func private @nx_comma(%s: !llvm.ptr, %at: i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c14 = arith.constant 14 : i64
  %c15 = arith.constant 15 : i64
  %lp = func.call @nx_rd(%s, %c3) : (!llvm.ptr, i64) -> i64
  %empty = arith.cmpi eq, %lp, %c0 : i64
  cf.cond_br %empty, ^ret, ^pend
^pend:
  %np = func.call @nx_rd(%s, %c4) : (!llvm.ptr, i64) -> i64
  %pend = func.call @nx_rp(%s, %c15) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @nx_s64(%pend, %np, %at) : (!llvm.ptr, i64, i64) -> ()
  %np1 = arith.addi %np, %c1 : i64
  func.call @nx_wr(%s, %c4, %np1) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^ret
^ret:
  llvm.return
}
// an identifier [i, i+len): with/assert owe their band's next semicolon; let opens a band (unless a '{' follows)
// that its in closes (Scanner::word)
func.func private @nx_word(%s: !llvm.ptr, %i: i64, %len: i64) -> i32 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c8 = arith.constant 8 : i64
  %c12 = arith.constant 12 : i64
  %c108 = arith.constant 108 : i64
  %z32 = arith.constant 0 : i32
  %src = func.call @nx_rp(%s, %c12) : (!llvm.ptr, i64) -> !llvm.ptr
  %n = func.call @nx_rd(%s, %c8) : (!llvm.ptr, i64) -> i64
  %l4 = arith.cmpi eq, %len, %c4 : i64
  cf.cond_br %l4, ^w_with, ^l6
^w_with:
  %a1 = func.call @nx_at(%src, %n, %i) : (!llvm.ptr, i64, i64) -> i8
  %i11 = arith.addi %i, %c1 : i64
  %b1 = func.call @nx_at(%src, %n, %i11) : (!llvm.ptr, i64, i64) -> i8
  %i12 = arith.addi %i, %c2 : i64
  %c1v = func.call @nx_at(%src, %n, %i12) : (!llvm.ptr, i64, i64) -> i8
  %i13 = arith.addi %i, %c3 : i64
  %d1 = func.call @nx_at(%src, %n, %i13) : (!llvm.ptr, i64, i64) -> i8
  %wa = arith.constant 119 : i8
  %wi = arith.constant 105 : i8
  %wt = arith.constant 116 : i8
  %wh = arith.constant 104 : i8
  %m11 = arith.cmpi eq, %a1, %wa : i8
  %m12v = arith.cmpi eq, %b1, %wi : i8
  %m13 = arith.cmpi eq, %c1v, %wt : i8
  %m14 = arith.cmpi eq, %d1, %wh : i8
  %m1a = arith.andi %m11, %m12v : i1
  %m1b = arith.andi %m13, %m14 : i1
  %is1 = arith.andi %m1a, %m1b : i1
  cf.cond_br %is1, ^owe, ^l6
^l6:
  %l6c = arith.cmpi eq, %len, %c6 : i64
  cf.cond_br %l6c, ^w_assert, ^l3
^w_assert:
  %a2 = func.call @nx_at(%src, %n, %i) : (!llvm.ptr, i64, i64) -> i8
  %i21 = arith.addi %i, %c1 : i64
  %b2 = func.call @nx_at(%src, %n, %i21) : (!llvm.ptr, i64, i64) -> i8
  %i22 = arith.addi %i, %c2 : i64
  %c2v = func.call @nx_at(%src, %n, %i22) : (!llvm.ptr, i64, i64) -> i8
  %i23 = arith.addi %i, %c3 : i64
  %d2 = func.call @nx_at(%src, %n, %i23) : (!llvm.ptr, i64, i64) -> i8
  %i24 = arith.addi %i, %c4 : i64
  %e2 = func.call @nx_at(%src, %n, %i24) : (!llvm.ptr, i64, i64) -> i8
  %i25 = arith.addi %i, %c5 : i64
  %f2 = func.call @nx_at(%src, %n, %i25) : (!llvm.ptr, i64, i64) -> i8
  %aa = arith.constant 97 : i8
  %ss = arith.constant 115 : i8
  %tt = arith.constant 116 : i8
  %ee = arith.constant 101 : i8
  %rr = arith.constant 114 : i8
  %m21 = arith.cmpi eq, %a2, %aa : i8
  %m22 = arith.cmpi eq, %b2, %ss : i8
  %m23 = arith.cmpi eq, %c2v, %ss : i8
  %m24 = arith.cmpi eq, %d2, %ee : i8
  %m25 = arith.cmpi eq, %e2, %rr : i8
  %m26 = arith.cmpi eq, %f2, %tt : i8
  %m2a = arith.andi %m21, %m22 : i1
  %m2b = arith.andi %m23, %m24 : i1
  %m2c = arith.andi %m25, %m26 : i1
  %m2ab = arith.andi %m2a, %m2b : i1
  %is2 = arith.andi %m2ab, %m2c : i1
  cf.cond_br %is2, ^owe, ^l3
^l3:
  %l3c = arith.cmpi eq, %len, %c3 : i64
  cf.cond_br %l3c, ^w_let, ^l2
^w_let:
  %a3 = func.call @nx_at(%src, %n, %i) : (!llvm.ptr, i64, i64) -> i8
  %i31 = arith.addi %i, %c1 : i64
  %b3 = func.call @nx_at(%src, %n, %i31) : (!llvm.ptr, i64, i64) -> i8
  %i32 = arith.addi %i, %c2 : i64
  %c3v = func.call @nx_at(%src, %n, %i32) : (!llvm.ptr, i64, i64) -> i8
  %ll = arith.constant 108 : i8
  %le = arith.constant 101 : i8
  %lt = arith.constant 116 : i8
  %m31 = arith.cmpi eq, %a3, %ll : i8
  %m32 = arith.cmpi eq, %b3, %le : i8
  %m33 = arith.cmpi eq, %c3v, %lt : i8
  %m3a = arith.andi %m31, %m32 : i1
  %is3 = arith.andi %m3a, %m33 : i1
  cf.cond_br %is3, ^let, ^l2
^l2:
  %l2c = arith.cmpi eq, %len, %c2 : i64
  cf.cond_br %l2c, ^w_in, ^ok
^w_in:
  %a4 = func.call @nx_at(%src, %n, %i) : (!llvm.ptr, i64, i64) -> i8
  %i41 = arith.addi %i, %c1 : i64
  %b4 = func.call @nx_at(%src, %n, %i41) : (!llvm.ptr, i64, i64) -> i8
  %ii = arith.constant 105 : i8
  %nn = arith.constant 110 : i8
  %m41 = arith.cmpi eq, %a4, %ii : i8
  %m42 = arith.cmpi eq, %b4, %nn : i8
  %is4 = arith.andi %m41, %m42 : i1
  cf.cond_br %is4, ^in, ^ok
^owe:
  func.call @nx_owe(%s) : (!llvm.ptr) -> ()
  cf.br ^ok
^let:
  %i33 = arith.addi %i, %c3 : i64
  %bn = func.call @nx_bracenext(%src, %n, %i33) : (!llvm.ptr, i64, i64) -> i1
  %true = arith.constant 1 : i1
  %nb = arith.xori %bn, %true : i1
  cf.cond_br %nb, ^letopen, ^ok
^letopen:
  %st1 = func.call @nx_open(%s, %c108, %i) : (!llvm.ptr, i64, i64) -> i32
  cf.br ^ret(%st1 : i32)
^in:
  %st2 = func.call @nx_close(%s, %c108, %c108, %i) : (!llvm.ptr, i64, i64, i64) -> i32
  cf.br ^ret(%st2 : i32)
^ok:
  cf.br ^ret(%z32 : i32)
^ret(%stR: i32):
  llvm.return %stR : i32
}

// ---- the scan: the state machine's main loop and its four states ----
func.func @confix_scan_nix(%rec: !llvm.ptr) -> i32 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c32 = arith.constant 32 : i64
  %mask = arith.constant 4294967295 : i64
  %true = arith.constant 1 : i1
  %z8 = arith.constant 0 : i8
  %z32 = arith.constant 0 : i32
  %o32 = arith.constant 1 : i32
  %t32 = arith.constant 2 : i32
  %f0 = llvm.getelementptr %rec[0, 0] : (!llvm.ptr) -> !llvm.ptr, !rec
  %src0 = llvm.load %f0 : !llvm.ptr -> !llvm.ptr
  %f1 = llvm.getelementptr %rec[0, 1] : (!llvm.ptr) -> !llvm.ptr, !rec
  %n0 = llvm.load %f1 : !llvm.ptr -> i64
  %f2 = llvm.getelementptr %rec[0, 2] : (!llvm.ptr) -> !llvm.ptr, !rec
  %start0 = llvm.load %f2 : !llvm.ptr -> i64
  %f3 = llvm.getelementptr %rec[0, 3] : (!llvm.ptr) -> !llvm.ptr, !rec
  %rooted0 = llvm.load %f3 : !llvm.ptr -> i64
  %f4 = llvm.getelementptr %rec[0, 4] : (!llvm.ptr) -> !llvm.ptr, !rec
  %span0 = llvm.load %f4 : !llvm.ptr -> !llvm.ptr
  %f5 = llvm.getelementptr %rec[0, 5] : (!llvm.ptr) -> !llvm.ptr, !rec
  %kind0 = llvm.load %f5 : !llvm.ptr -> !llvm.ptr
  %f6 = llvm.getelementptr %rec[0, 6] : (!llvm.ptr) -> !llvm.ptr, !rec
  %stmts0 = llvm.load %f6 : !llvm.ptr -> !llvm.ptr
  %f7 = llvm.getelementptr %rec[0, 7] : (!llvm.ptr) -> !llvm.ptr, !rec
  %ends0 = llvm.load %f7 : !llvm.ptr -> !llvm.ptr
  %f8 = llvm.getelementptr %rec[0, 8] : (!llvm.ptr) -> !llvm.ptr, !rec
  %rows0 = llvm.load %f8 : !llvm.ptr -> i64
  %f9 = llvm.getelementptr %rec[0, 9] : (!llvm.ptr) -> !llvm.ptr, !rec
  %nends0 = llvm.load %f9 : !llvm.ptr -> i64
  %f10 = llvm.getelementptr %rec[0, 10] : (!llvm.ptr) -> !llvm.ptr, !rec
  %rowcap0 = llvm.load %f10 : !llvm.ptr -> i64
  %f11 = llvm.getelementptr %rec[0, 11] : (!llvm.ptr) -> !llvm.ptr, !rec
  %endcap0 = llvm.load %f11 : !llvm.ptr -> i64
  %s = llvm.alloca %c1 x !stt : (i64) -> !llvm.ptr
  %c1001 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1001, %start0) : (!llvm.ptr, i64, i64) -> ()
  %c1002 = arith.constant 1 : i64
  func.call @nx_wr(%s, %c1002, %n0) : (!llvm.ptr, i64, i64) -> ()
  %c1003 = arith.constant 2 : i64
  func.call @nx_wr(%s, %c1003, %c1) : (!llvm.ptr, i64, i64) -> ()
  %c1004 = arith.constant 3 : i64
  func.call @nx_wr(%s, %c1004, %c0) : (!llvm.ptr, i64, i64) -> ()
  %c1005 = arith.constant 4 : i64
  func.call @nx_wr(%s, %c1005, %c0) : (!llvm.ptr, i64, i64) -> ()
  %c1006 = arith.constant 5 : i64
  func.call @nx_wr(%s, %c1006, %c0) : (!llvm.ptr, i64, i64) -> ()
  %c1007 = arith.constant 6 : i64
  func.call @nx_wr(%s, %c1007, %rows0) : (!llvm.ptr, i64, i64) -> ()
  %c1008 = arith.constant 7 : i64
  func.call @nx_wr(%s, %c1008, %nends0) : (!llvm.ptr, i64, i64) -> ()
  %c1009 = arith.constant 8 : i64
  func.call @nx_wr(%s, %c1009, %n0) : (!llvm.ptr, i64, i64) -> ()
  %c1010 = arith.constant 9 : i64
  func.call @nx_wr(%s, %c1010, %rowcap0) : (!llvm.ptr, i64, i64) -> ()
  %c1011 = arith.constant 10 : i64
  func.call @nx_wr(%s, %c1011, %endcap0) : (!llvm.ptr, i64, i64) -> ()
  %c1012 = arith.constant 11 : i64
  func.call @nx_wr(%s, %c1012, %rooted0) : (!llvm.ptr, i64, i64) -> ()
  %c1013 = arith.constant 12 : i64
  func.call @nx_wp(%s, %c1013, %src0) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %c1014 = arith.constant 16 : i64
  func.call @nx_wp(%s, %c1014, %span0) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %c1015 = arith.constant 17 : i64
  func.call @nx_wp(%s, %c1015, %kind0) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %c1016 = arith.constant 18 : i64
  func.call @nx_wp(%s, %c1016, %stmts0) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %c1017 = arith.constant 19 : i64
  func.call @nx_wp(%s, %c1017, %ends0) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %n1 = arith.addi %n0, %c1 : i64
  %ni = arith.index_cast %n1 : i64 to index
  %stm = memref.alloc(%ni) : memref<?xi8>
  %sti = memref.extract_aligned_pointer_as_index %stm : memref<?xi8> -> index
  %st64 = arith.index_cast %sti : index to i64
  %c1018 = arith.constant 13 : i64
  func.call @nx_wr(%s, %c1018, %st64) : (!llvm.ptr, i64, i64) -> ()
  %n3 = arith.muli %n1, %c3 : i64
  %n3i = arith.index_cast %n3 : i64 to index
  %stackm = memref.alloc(%n3i) : memref<?xi64>
  %stacki = memref.extract_aligned_pointer_as_index %stackm : memref<?xi64> -> index
  %stack64 = arith.index_cast %stacki : index to i64
  %c1019 = arith.constant 14 : i64
  func.call @nx_wr(%s, %c1019, %stack64) : (!llvm.ptr, i64, i64) -> ()
  %pendm = memref.alloc(%ni) : memref<?xi64>
  %pendi = memref.extract_aligned_pointer_as_index %pendm : memref<?xi64> -> index
  %pend64 = arith.index_cast %pendi : index to i64
  %c1020 = arith.constant 15 : i64
  func.call @nx_wr(%s, %c1020, %pend64) : (!llvm.ptr, i64, i64) -> ()
  %stp = llvm.inttoptr %st64 : i64 to !llvm.ptr
  func.call @nx_s8(%stp, %c0, %z8) : (!llvm.ptr, i64, i8) -> ()
  cf.br ^main
^ok:
  %rO = func.call @nx_finish(%s, %rec, %z32) : (!llvm.ptr, !llvm.ptr, i32) -> i32
  llvm.return %rO : i32
^bad:
  %rB = func.call @nx_finish(%s, %rec, %o32) : (!llvm.ptr, !llvm.ptr, i32) -> i32
  llvm.return %rB : i32
^room:
  %rR = func.call @nx_finish(%s, %rec, %t32) : (!llvm.ptr, !llvm.ptr, i32) -> i32
  llvm.return %rR : i32
^main:
  %c1021 = arith.constant 0 : i64
  %v1022 = func.call @nx_rd(%s, %c1021) : (!llvm.ptr, i64) -> i64
  %c1023 = arith.constant 1 : i64
  %v1024 = func.call @nx_rd(%s, %c1023) : (!llvm.ptr, i64) -> i64
  %v1025 = arith.cmpi uge, %v1022, %v1024 : i64
  %v1026 = arith.cmpi ult, %v1024, %n0 : i64
  %v1027 = arith.andi %v1025, %v1026 : i1
  cf.cond_br %v1027, ^ok, ^main2
^main2:
  %c1028 = arith.constant 0 : i64
  %v1029 = func.call @nx_rd(%s, %c1028) : (!llvm.ptr, i64) -> i64
  %v1030 = arith.cmpi uge, %v1029, %n0 : i64
  cf.cond_br %v1030, ^atend, ^dispatch
^dispatch:
  %c1031 = arith.constant 2 : i64
  %v1032 = func.call @nx_rd(%s, %c1031) : (!llvm.ptr, i64) -> i64
  %v1033 = arith.subi %v1032, %c1 : i64
  %c1034 = arith.constant 13 : i64
  %v1035 = func.call @nx_rp(%s, %c1034) : (!llvm.ptr, i64) -> !llvm.ptr
  %v1036 = func.call @nx_a8(%v1035, %v1033) : (!llvm.ptr, i64) -> i8
  %v1037 = arith.extui %v1036 : i8 to i64
  %v1038 = arith.cmpi eq, %v1037, %c2 : i64
  %v1039 = arith.cmpi eq, %v1037, %c3 : i64
  %v1040 = arith.cmpi eq, %v1037, %c4 : i64
  %v1041 = arith.cmpi eq, %v1037, %c5 : i64
  %v1042 = arith.ori %v1040, %v1041 : i1
  cf.cond_br %v1038, ^string, ^b1
^b1:
  cf.cond_br %v1039, ^ind, ^b2
^b2:
  cf.cond_br %v1042, ^inpath, ^deflt
^atend:
  %c1043 = arith.constant 2 : i64
  %v1044 = func.call @nx_rd(%s, %c1043) : (!llvm.ptr, i64) -> i64
  %v1045 = arith.subi %v1044, %c1 : i64
  %c1046 = arith.constant 13 : i64
  %v1047 = func.call @nx_rp(%s, %c1046) : (!llvm.ptr, i64) -> !llvm.ptr
  %v1048 = func.call @nx_a8(%v1047, %v1045) : (!llvm.ptr, i64) -> i8
  %v1049 = arith.extui %v1048 : i8 to i64
  %v1050 = arith.cmpi eq, %v1049, %c4 : i64
  cf.cond_br %v1050, ^atend_pop, ^atend2
^atend_pop:
  %c1051 = arith.constant 2 : i64
  %v1052 = func.call @nx_rd(%s, %c1051) : (!llvm.ptr, i64) -> i64
  %v1053 = arith.subi %v1052, %c1 : i64
  %c1054 = arith.constant 2 : i64
  func.call @nx_wr(%s, %c1054, %v1053) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^main
^atend2:
  %c1055 = arith.constant 2 : i64
  %v1056 = func.call @nx_rd(%s, %c1055) : (!llvm.ptr, i64) -> i64
  %v1057 = arith.subi %v1056, %c1 : i64
  %c1058 = arith.constant 13 : i64
  %v1059 = func.call @nx_rp(%s, %c1058) : (!llvm.ptr, i64) -> !llvm.ptr
  %v1060 = func.call @nx_a8(%v1059, %v1057) : (!llvm.ptr, i64) -> i8
  %v1061 = arith.extui %v1060 : i8 to i64
  %v1062 = arith.cmpi eq, %v1061, %c5 : i64
  cf.cond_br %v1062, ^bad, ^final
^final:
  %c1063 = arith.constant 2 : i64
  %v1064 = func.call @nx_rd(%s, %c1063) : (!llvm.ptr, i64) -> i64
  %c1065 = arith.constant 3 : i64
  %v1066 = func.call @nx_rd(%s, %c1065) : (!llvm.ptr, i64) -> i64
  %v1067 = arith.cmpi eq, %v1064, %c1 : i64
  %v1068 = arith.cmpi eq, %v1066, %c0 : i64
  %v1069 = arith.andi %v1067, %v1068 : i1
  cf.cond_br %v1069, ^ok, ^bad
^deflt:
  %c1070 = arith.constant 0 : i64
  %v1071 = func.call @nx_rd(%s, %c1070) : (!llvm.ptr, i64) -> i64
  %c1072 = arith.constant 1 : i64
  %v1073 = func.call @nx_rd(%s, %c1072) : (!llvm.ptr, i64) -> i64
  %v1074 = arith.cmpi uge, %v1071, %v1073 : i64
  cf.cond_br %v1074, ^main, ^d_body
^d_body:
  %c1075 = arith.constant 0 : i64
  %v1076 = func.call @nx_rd(%s, %c1075) : (!llvm.ptr, i64) -> i64
  %v1077 = func.call @nx_at(%src0, %n0, %v1076) : (!llvm.ptr, i64, i64) -> i8
  %t1078 = llvm.mlir.addressof @nx_idstart : !llvm.ptr
  %v1079 = func.call @nx_cls(%t1078, %v1077) : (!llvm.ptr, i8) -> i1
  cf.cond_br %v1079, ^d_id, ^d_sw
^d_sw:
  %c1080 = arith.constant 32 : i8
  %v1081 = arith.cmpi eq, %v1077, %c1080 : i8
  %c1082 = arith.constant 9 : i8
  %v1083 = arith.cmpi eq, %v1077, %c1082 : i8
  %c1084 = arith.constant 13 : i8
  %v1085 = arith.cmpi eq, %v1077, %c1084 : i8
  %c1086 = arith.constant 10 : i8
  %v1087 = arith.cmpi eq, %v1077, %c1086 : i8
  %v1088 = arith.ori %v1081, %v1083 : i1
  %v1089 = arith.ori %v1088, %v1085 : i1
  %v1090 = arith.ori %v1089, %v1087 : i1
  cf.cond_br %v1090, ^d_ws, ^b3
^b3:
  %c1091 = arith.constant 35 : i8
  %v1092 = arith.cmpi eq, %v1077, %c1091 : i8
  cf.cond_br %v1092, ^d_hash, ^b4
^b4:
  %c1093 = arith.constant 40 : i8
  %v1094 = arith.cmpi eq, %v1077, %c1093 : i8
  cf.cond_br %v1094, ^d_lparen, ^b5
^b5:
  %c1095 = arith.constant 41 : i8
  %v1096 = arith.cmpi eq, %v1077, %c1095 : i8
  cf.cond_br %v1096, ^d_rparen, ^b6
^b6:
  %c1097 = arith.constant 91 : i8
  %v1098 = arith.cmpi eq, %v1077, %c1097 : i8
  cf.cond_br %v1098, ^d_lbracket, ^b7
^b7:
  %c1099 = arith.constant 93 : i8
  %v1100 = arith.cmpi eq, %v1077, %c1099 : i8
  cf.cond_br %v1100, ^d_rbracket, ^b8
^b8:
  %c1101 = arith.constant 123 : i8
  %v1102 = arith.cmpi eq, %v1077, %c1101 : i8
  cf.cond_br %v1102, ^d_lbrace, ^b9
^b9:
  %c1103 = arith.constant 125 : i8
  %v1104 = arith.cmpi eq, %v1077, %c1103 : i8
  cf.cond_br %v1104, ^d_rbrace, ^b10
^b10:
  %c1105 = arith.constant 34 : i8
  %v1106 = arith.cmpi eq, %v1077, %c1105 : i8
  cf.cond_br %v1106, ^d_dquote, ^b11
^b11:
  %c1107 = arith.constant 36 : i8
  %v1108 = arith.cmpi eq, %v1077, %c1107 : i8
  cf.cond_br %v1108, ^d_dollar, ^b12
^b12:
  %c1109 = arith.constant 39 : i8
  %v1110 = arith.cmpi eq, %v1077, %c1109 : i8
  cf.cond_br %v1110, ^d_quote, ^b13
^b13:
  %c1111 = arith.constant 59 : i8
  %v1112 = arith.cmpi eq, %v1077, %c1111 : i8
  cf.cond_br %v1112, ^d_semi, ^b14
^b14:
  %c1113 = arith.constant 44 : i8
  %v1114 = arith.cmpi eq, %v1077, %c1113 : i8
  cf.cond_br %v1114, ^d_comma, ^b15
^b15:
  %c1115 = arith.constant 64 : i8
  %v1116 = arith.cmpi eq, %v1077, %c1115 : i8
  %c1117 = arith.constant 63 : i8
  %v1118 = arith.cmpi eq, %v1077, %c1117 : i8
  %c1119 = arith.constant 42 : i8
  %v1120 = arith.cmpi eq, %v1077, %c1119 : i8
  %c1121 = arith.constant 61 : i8
  %v1122 = arith.cmpi eq, %v1077, %c1121 : i8
  %c1123 = arith.constant 58 : i8
  %v1124 = arith.cmpi eq, %v1077, %c1123 : i8
  %c1125 = arith.constant 33 : i8
  %v1126 = arith.cmpi eq, %v1077, %c1125 : i8
  %c1127 = arith.constant 38 : i8
  %v1128 = arith.cmpi eq, %v1077, %c1127 : i8
  %c1129 = arith.constant 124 : i8
  %v1130 = arith.cmpi eq, %v1077, %c1129 : i8
  %c1131 = arith.constant 62 : i8
  %v1132 = arith.cmpi eq, %v1077, %c1131 : i8
  %v1133 = arith.ori %v1116, %v1118 : i1
  %v1134 = arith.ori %v1133, %v1120 : i1
  %v1135 = arith.ori %v1134, %v1122 : i1
  %v1136 = arith.ori %v1135, %v1124 : i1
  %v1137 = arith.ori %v1136, %v1126 : i1
  %v1138 = arith.ori %v1137, %v1128 : i1
  %v1139 = arith.ori %v1138, %v1130 : i1
  %v1140 = arith.ori %v1139, %v1132 : i1
  cf.cond_br %v1140, ^d_op, ^b16
^b16:
  %c1141 = arith.constant 60 : i8
  %v1142 = arith.cmpi eq, %v1077, %c1141 : i8
  cf.cond_br %v1142, ^d_lt, ^b17
^b17:
  %c1143 = arith.constant 46 : i8
  %v1144 = arith.cmpi eq, %v1077, %c1143 : i8
  %c1145 = arith.constant 45 : i8
  %v1146 = arith.cmpi eq, %v1077, %c1145 : i8
  %c1147 = arith.constant 43 : i8
  %v1148 = arith.cmpi eq, %v1077, %c1147 : i8
  %v1149 = arith.ori %v1144, %v1146 : i1
  %v1150 = arith.ori %v1149, %v1148 : i1
  cf.cond_br %v1150, ^d_dot, ^b18
^b18:
  %t1151 = llvm.mlir.addressof @nx_digit : !llvm.ptr
  %v1152 = func.call @nx_cls(%t1151, %v1077) : (!llvm.ptr, i8) -> i1
  cf.cond_br %v1152, ^d_digit, ^b19
^b19:
  %c1153 = arith.constant 47 : i8
  %v1154 = arith.cmpi eq, %v1077, %c1153 : i8
  cf.cond_br %v1154, ^d_slash, ^b20
^b20:
  %c1155 = arith.constant 126 : i8
  %v1156 = arith.cmpi eq, %v1077, %c1155 : i8
  cf.cond_br %v1156, ^d_general, ^b21
^b21:
  cf.br ^d_skip
^d_ws:
  %v1157 = arith.addi %v1076, %c1 : i64
  %t1158 = llvm.mlir.addressof @nx_ws : !llvm.ptr
  %v1159 = func.call @nx_run(%src0, %n0, %v1157, %t1158) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %c1160 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1160, %v1159) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_hash:
  %v1161 = arith.addi %v1076, %c1 : i64
  %v1162 = func.call @nx_skipline(%src0, %n0, %v1161) : (!llvm.ptr, i64, i64) -> i64
  %c1163 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1163, %v1162) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_lparen:
  %c1164 = arith.constant 40 : i64
  %v1165 = func.call @nx_open(%s, %c1164, %v1076) : (!llvm.ptr, i64, i64) -> i32
  %c1166 = arith.constant 2 : i32
  %v1167 = arith.cmpi eq, %v1165, %c1166 : i32
  cf.cond_br %v1167, ^room, ^b22
^b22:
  %v1168 = arith.addi %v1076, %c1 : i64
  %c1169 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1169, %v1168) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_rparen:
  %c1170 = arith.constant 40 : i64
  %c1171 = arith.constant 40 : i64
  %v1172 = func.call @nx_close(%s, %c1170, %c1171, %v1076) : (!llvm.ptr, i64, i64, i64) -> i32
  %c1173 = arith.constant 1 : i32
  %v1174 = arith.cmpi eq, %v1172, %c1173 : i32
  cf.cond_br %v1174, ^bad, ^b23
^b23:
  %c1175 = arith.constant 2 : i32
  %v1176 = arith.cmpi eq, %v1172, %c1175 : i32
  cf.cond_br %v1176, ^room, ^b24
^b24:
  %v1177 = arith.addi %v1076, %c1 : i64
  %c1178 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1178, %v1177) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_lbracket:
  %c1179 = arith.constant 91 : i64
  %v1180 = func.call @nx_open(%s, %c1179, %v1076) : (!llvm.ptr, i64, i64) -> i32
  %c1181 = arith.constant 2 : i32
  %v1182 = arith.cmpi eq, %v1180, %c1181 : i32
  cf.cond_br %v1182, ^room, ^b25
^b25:
  %v1183 = arith.addi %v1076, %c1 : i64
  %c1184 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1184, %v1183) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_rbracket:
  %c1185 = arith.constant 91 : i64
  %c1186 = arith.constant 91 : i64
  %v1187 = func.call @nx_close(%s, %c1185, %c1186, %v1076) : (!llvm.ptr, i64, i64, i64) -> i32
  %c1188 = arith.constant 1 : i32
  %v1189 = arith.cmpi eq, %v1187, %c1188 : i32
  cf.cond_br %v1189, ^bad, ^b26
^b26:
  %c1190 = arith.constant 2 : i32
  %v1191 = arith.cmpi eq, %v1187, %c1190 : i32
  cf.cond_br %v1191, ^room, ^b27
^b27:
  %v1192 = arith.addi %v1076, %c1 : i64
  %c1193 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1193, %v1192) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_lbrace:
  func.call @nx_push(%s, %c1) : (!llvm.ptr, i64) -> ()
  %c1194 = arith.constant 123 : i64
  %v1195 = func.call @nx_open(%s, %c1194, %v1076) : (!llvm.ptr, i64, i64) -> i32
  %c1196 = arith.constant 2 : i32
  %v1197 = arith.cmpi eq, %v1195, %c1196 : i32
  cf.cond_br %v1197, ^room, ^b28
^b28:
  %v1198 = arith.addi %v1076, %c1 : i64
  %c1199 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1199, %v1198) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_rbrace:
  %c1200 = arith.constant 2 : i64
  %v1201 = func.call @nx_rd(%s, %c1200) : (!llvm.ptr, i64) -> i64
  %v1202 = arith.subi %v1201, %c1 : i64
  %c1203 = arith.constant 13 : i64
  %v1204 = func.call @nx_rp(%s, %c1203) : (!llvm.ptr, i64) -> !llvm.ptr
  %v1205 = func.call @nx_a8(%v1204, %v1202) : (!llvm.ptr, i64) -> i8
  %v1206 = arith.extui %v1205 : i8 to i64
  %v1207 = arith.cmpi ne, %v1206, %c0 : i64
  %v1208 = arith.select %v1207, %v1202, %v1201 : i64
  %c1209 = arith.constant 2 : i64
  func.call @nx_wr(%s, %c1209, %v1208) : (!llvm.ptr, i64, i64) -> ()
  %c1210 = arith.constant 123 : i64
  %c1211 = arith.constant 36 : i64
  %v1212 = func.call @nx_close(%s, %c1210, %c1211, %v1076) : (!llvm.ptr, i64, i64, i64) -> i32
  %c1213 = arith.constant 1 : i32
  %v1214 = arith.cmpi eq, %v1212, %c1213 : i32
  cf.cond_br %v1214, ^bad, ^b29
^b29:
  %c1215 = arith.constant 2 : i32
  %v1216 = arith.cmpi eq, %v1212, %c1215 : i32
  cf.cond_br %v1216, ^room, ^b30
^b30:
  %v1217 = arith.addi %v1076, %c1 : i64
  %c1218 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1218, %v1217) : (!llvm.ptr, i64, i64) -> ()
  %c1219 = arith.constant 2 : i64
  %v1220 = func.call @nx_rd(%s, %c1219) : (!llvm.ptr, i64) -> i64
  %v1221 = arith.subi %v1220, %c1 : i64
  %c1222 = arith.constant 13 : i64
  %v1223 = func.call @nx_rp(%s, %c1222) : (!llvm.ptr, i64) -> !llvm.ptr
  %v1224 = func.call @nx_a8(%v1223, %v1221) : (!llvm.ptr, i64) -> i8
  %v1225 = arith.extui %v1224 : i8 to i64
  %v1226 = arith.cmpi ule, %v1225, %c1 : i64
  cf.cond_br %v1226, ^deflt, ^main
^d_dquote:
  func.call @nx_push(%s, %c2) : (!llvm.ptr, i64) -> ()
  %c1227 = arith.constant 34 : i64
  %v1228 = func.call @nx_open(%s, %c1227, %v1076) : (!llvm.ptr, i64, i64) -> i32
  %c1229 = arith.constant 2 : i32
  %v1230 = arith.cmpi eq, %v1228, %c1229 : i32
  cf.cond_br %v1230, ^room, ^b31
^b31:
  %v1231 = arith.addi %v1076, %c1 : i64
  %c1232 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1232, %v1231) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^main
^d_dollar:
  %v1233 = arith.addi %v1076, %c1 : i64
  %v1234 = func.call @nx_at(%src0, %n0, %v1233) : (!llvm.ptr, i64, i64) -> i8
  %c1235 = arith.constant 123 : i8
  %v1236 = arith.cmpi eq, %v1234, %c1235 : i8
  cf.cond_br %v1236, ^d_dollar_interp, ^d_dollar_skip
^d_dollar_interp:
  func.call @nx_push(%s, %c1) : (!llvm.ptr, i64) -> ()
  %c1237 = arith.constant 36 : i64
  %v1238 = func.call @nx_open(%s, %c1237, %v1076) : (!llvm.ptr, i64, i64) -> i32
  %c1239 = arith.constant 2 : i32
  %v1240 = arith.cmpi eq, %v1238, %c1239 : i32
  cf.cond_br %v1240, ^room, ^b32
^b32:
  %v1241 = arith.addi %v1076, %c2 : i64
  %c1242 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1242, %v1241) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_dollar_skip:
  %v1243 = arith.addi %v1076, %c1 : i64
  %c1244 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1244, %v1243) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_quote:
  %v1245 = arith.addi %v1076, %c1 : i64
  %v1246 = func.call @nx_at(%src0, %n0, %v1245) : (!llvm.ptr, i64, i64) -> i8
  %c1247 = arith.constant 39 : i8
  %v1248 = arith.cmpi eq, %v1246, %c1247 : i8
  cf.cond_br %v1248, ^d_general, ^d_quote_skip
^d_quote_skip:
  %v1249 = arith.addi %v1076, %c1 : i64
  %c1250 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1250, %v1249) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_semi:
  func.call @nx_semi(%s, %v1076) : (!llvm.ptr, i64) -> ()
  %v1251 = arith.addi %v1076, %c1 : i64
  %c1252 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1252, %v1251) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_comma:
  func.call @nx_comma(%s, %v1076) : (!llvm.ptr, i64) -> ()
  %v1253 = arith.addi %v1076, %c1 : i64
  %c1254 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1254, %v1253) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_op:
  %v1255 = arith.addi %v1076, %c1 : i64
  %c1256 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1256, %v1255) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_lt:
  %v1257 = arith.addi %v1076, %c1 : i64
  %v1258 = func.call @nx_at(%src0, %n0, %v1257) : (!llvm.ptr, i64, i64) -> i8
  %t1259 = llvm.mlir.addressof @nx_pathchar : !llvm.ptr
  %v1260 = func.call @nx_cls(%t1259, %v1258) : (!llvm.ptr, i8) -> i1
  cf.cond_br %v1260, ^d_general, ^d_lt_skip
^d_lt_skip:
  %v1261 = arith.addi %v1076, %c1 : i64
  %c1262 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1262, %v1261) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_dot:
  %v1263 = arith.addi %v1076, %c1 : i64
  %t1264 = llvm.mlir.addressof @nx_pathchar : !llvm.ptr
  %v1265 = func.call @nx_run(%src0, %n0, %v1263, %t1264) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %v1266 = func.call @nx_at(%src0, %n0, %v1265) : (!llvm.ptr, i64, i64) -> i8
  %c1267 = arith.constant 47 : i8
  %v1268 = arith.cmpi eq, %v1266, %c1267 : i8
  cf.cond_br %v1268, ^d_general, ^d_dot_skip
^d_dot_skip:
  %v1269 = arith.addi %v1076, %c1 : i64
  %c1270 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1270, %v1269) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_digit:
  %v1271 = arith.addi %v1076, %c1 : i64
  %t1272 = llvm.mlir.addressof @nx_pathchar : !llvm.ptr
  %v1273 = func.call @nx_run(%src0, %n0, %v1271, %t1272) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %v1274 = func.call @nx_at(%src0, %n0, %v1273) : (!llvm.ptr, i64, i64) -> i8
  %c1275 = arith.constant 47 : i8
  %v1276 = arith.cmpi eq, %v1274, %c1275 : i8
  cf.cond_br %v1276, ^d_general, ^d_digit2
^d_digit2:
  %v1277 = arith.addi %v1076, %c1 : i64
  %t1278 = llvm.mlir.addressof @nx_digit : !llvm.ptr
  %v1279 = func.call @nx_run(%src0, %n0, %v1277, %t1278) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %c1280 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1280, %v1279) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_slash:
  %v1281 = arith.addi %v1076, %c1 : i64
  %v1282 = func.call @nx_at(%src0, %n0, %v1281) : (!llvm.ptr, i64, i64) -> i8
  %c1283 = arith.constant 47 : i8
  %v1284 = arith.cmpi eq, %v1282, %c1283 : i8
  cf.cond_br %v1284, ^d_slash_op, ^d_slash2
^d_slash_op:
  %v1285 = arith.addi %v1076, %c2 : i64
  %c1286 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1286, %v1285) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_slash2:
  %c1287 = arith.constant 42 : i8
  %v1288 = arith.cmpi eq, %v1282, %c1287 : i8
  %c1289 = arith.constant 36 : i8
  %v1290 = arith.cmpi eq, %v1282, %c1289 : i8
  %t1291 = llvm.mlir.addressof @nx_pathchar : !llvm.ptr
  %v1292 = func.call @nx_cls(%t1291, %v1282) : (!llvm.ptr, i8) -> i1
  %v1293 = arith.ori %v1288, %v1290 : i1
  %v1294 = arith.ori %v1293, %v1292 : i1
  cf.cond_br %v1294, ^d_general, ^d_slash_skip
^d_slash_skip:
  %v1295 = arith.addi %v1076, %c1 : i64
  %c1296 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1296, %v1295) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_skip:
  %v1297 = arith.addi %v1076, %c1 : i64
  %c1298 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1298, %v1297) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_id:
  %v1299 = arith.addi %v1076, %c1 : i64
  %t1300 = llvm.mlir.addressof @nx_idcharnq : !llvm.ptr
  %v1301 = func.call @nx_run(%src0, %n0, %v1299, %t1300) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %v1302 = func.call @nx_at(%src0, %n0, %v1301) : (!llvm.ptr, i64, i64) -> i8
  %c1303 = arith.constant 46 : i8
  %v1304 = arith.cmpi eq, %v1302, %c1303 : i8
  %c1305 = arith.constant 43 : i8
  %v1306 = arith.cmpi eq, %v1302, %c1305 : i8
  %v1307 = arith.ori %v1304, %v1306 : i1
  %c1308 = arith.constant 39 : i8
  %v1309 = arith.cmpi eq, %v1302, %c1308 : i8
  %v1310 = arith.ori %v1307, %v1309 : i1
  %c1311 = arith.constant 47 : i8
  %v1312 = arith.cmpi eq, %v1302, %c1311 : i8
  %v1313 = arith.ori %v1310, %v1312 : i1
  %c1314 = arith.constant 58 : i8
  %v1315 = arith.cmpi eq, %v1302, %c1314 : i8
  %v1316 = arith.ori %v1313, %v1315 : i1
  cf.cond_br %v1316, ^d_id_path, ^d_id_word
^d_id_word:
  %v1317 = arith.subi %v1301, %v1076 : i64
  %v1318 = arith.cmpi ule, %v1317, %c6 : i64
  cf.cond_br %v1318, ^d_id_word6, ^d_id_word_done
^d_id_word6:
  %v1319 = func.call @nx_word(%s, %v1076, %v1317) : (!llvm.ptr, i64, i64) -> i32
  %c1320 = arith.constant 1 : i32
  %v1321 = arith.cmpi eq, %v1319, %c1320 : i32
  cf.cond_br %v1321, ^bad, ^b33
^b33:
  %c1322 = arith.constant 2 : i32
  %v1323 = arith.cmpi eq, %v1319, %c1322 : i32
  cf.cond_br %v1323, ^room, ^b34
^b34:
  cf.br ^d_id_word_done
^d_id_word_done:
  %c1324 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1324, %v1301) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_id_path:
  %t1325 = llvm.mlir.addressof @nx_pathchar : !llvm.ptr
  %v1326 = func.call @nx_run(%src0, %n0, %v1301, %t1325) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %v1327 = func.call @nx_at(%src0, %n0, %v1326) : (!llvm.ptr, i64, i64) -> i8
  %c1328 = arith.constant 47 : i8
  %v1329 = arith.cmpi eq, %v1327, %c1328 : i8
  %c1330 = arith.constant 58 : i8
  %v1331 = arith.cmpi eq, %v1327, %c1330 : i8
  %v1332 = arith.ori %v1329, %v1331 : i1
  cf.cond_br %v1332, ^d_general, ^d_id_mid
^d_id_mid:
  %v1333 = arith.addi %v1076, %c1 : i64
  %t1334 = llvm.mlir.addressof @nx_idchar : !llvm.ptr
  %v1335 = func.call @nx_run(%src0, %n0, %v1333, %t1334) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %v1336 = arith.subi %v1335, %v1076 : i64
  %v1337 = arith.cmpi ule, %v1336, %c6 : i64
  cf.cond_br %v1337, ^d_id_mid6, ^d_id_mid_done
^d_id_mid6:
  %v1338 = func.call @nx_word(%s, %v1076, %v1336) : (!llvm.ptr, i64, i64) -> i32
  %c1339 = arith.constant 1 : i32
  %v1340 = arith.cmpi eq, %v1338, %c1339 : i32
  cf.cond_br %v1340, ^bad, ^b35
^b35:
  %c1341 = arith.constant 2 : i32
  %v1342 = arith.cmpi eq, %v1338, %c1341 : i32
  cf.cond_br %v1342, ^room, ^b36
^b36:
  cf.br ^d_id_mid_done
^d_id_mid_done:
  %v1343 = arith.addi %v1076, %v1336 : i64
  %c1344 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1344, %v1343) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^deflt
^d_general:
  %v1345 = func.call @nixfe_confix_match(%src0, %n0, %v1076) : (!llvm.ptr, i64, i64) -> i64
  %v1346 = arith.shrui %v1345, %c32 : i64
  %v1347 = arith.andi %v1345, %mask : i64
  %v1348 = arith.addi %v1076, %v1346 : i64
  %c1349 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1349, %v1348) : (!llvm.ptr, i64, i64) -> ()
  %c1350 = arith.constant 10 : i64
  %v1351 = arith.cmpi ult, %v1347, %c1350 : i64
  cf.cond_br %v1351, ^d_gen_word, ^d_gen_sw
^d_gen_word:
  %v1352 = func.call @nx_word(%s, %v1076, %v1346) : (!llvm.ptr, i64, i64) -> i32
  %c1353 = arith.constant 1 : i32
  %v1354 = arith.cmpi eq, %v1352, %c1353 : i32
  cf.cond_br %v1354, ^bad, ^b37
^b37:
  %c1355 = arith.constant 2 : i32
  %v1356 = arith.cmpi eq, %v1352, %c1355 : i32
  cf.cond_br %v1356, ^room, ^b38
^b38:
  cf.br ^d_gen_sw
^d_gen_sw:
  %c1357 = arith.constant 33 : i64
  %v1358 = arith.cmpi eq, %v1347, %c1357 : i64
  cf.cond_br %v1358, ^g_interp, ^b39
^b39:
  %c1359 = arith.constant 34 : i64
  %v1360 = arith.cmpi eq, %v1347, %c1359 : i64
  cf.cond_br %v1360, ^g_rbrace, ^b40
^b40:
  %c1361 = arith.constant 35 : i64
  %v1362 = arith.cmpi eq, %v1347, %c1361 : i64
  cf.cond_br %v1362, ^g_lbrace, ^b41
^b41:
  %c1363 = arith.constant 36 : i64
  %v1364 = arith.cmpi eq, %v1347, %c1363 : i64
  cf.cond_br %v1364, ^g_dquote, ^b42
^b42:
  %c1365 = arith.constant 37 : i64
  %v1366 = arith.cmpi eq, %v1347, %c1365 : i64
  cf.cond_br %v1366, ^g_ind, ^b43
^b43:
  %c1367 = arith.constant 38 : i64
  %v1368 = arith.cmpi eq, %v1347, %c1367 : i64
  cf.cond_br %v1368, ^g_pathstart, ^b44
^b44:
  %c1369 = arith.constant 39 : i64
  %v1370 = arith.cmpi eq, %v1347, %c1369 : i64
  cf.cond_br %v1370, ^g_path, ^b45
^b45:
  %c1371 = arith.constant 40 : i64
  %v1372 = arith.cmpi eq, %v1347, %c1371 : i64
  cf.cond_br %v1372, ^g_path, ^b46
^b46:
  cf.br ^deflt
^g_interp:
  func.call @nx_push(%s, %c1) : (!llvm.ptr, i64) -> ()
  %c1373 = arith.constant 36 : i64
  %v1374 = func.call @nx_open(%s, %c1373, %v1076) : (!llvm.ptr, i64, i64) -> i32
  %c1375 = arith.constant 2 : i32
  %v1376 = arith.cmpi eq, %v1374, %c1375 : i32
  cf.cond_br %v1376, ^room, ^b47
^b47:
  cf.br ^deflt
^g_rbrace:
  %c1377 = arith.constant 2 : i64
  %v1378 = func.call @nx_rd(%s, %c1377) : (!llvm.ptr, i64) -> i64
  %v1379 = arith.subi %v1378, %c1 : i64
  %c1380 = arith.constant 13 : i64
  %v1381 = func.call @nx_rp(%s, %c1380) : (!llvm.ptr, i64) -> !llvm.ptr
  %v1382 = func.call @nx_a8(%v1381, %v1379) : (!llvm.ptr, i64) -> i8
  %v1383 = arith.extui %v1382 : i8 to i64
  %v1384 = arith.cmpi ne, %v1383, %c0 : i64
  %v1385 = arith.select %v1384, %v1379, %v1378 : i64
  %c1386 = arith.constant 2 : i64
  func.call @nx_wr(%s, %c1386, %v1385) : (!llvm.ptr, i64, i64) -> ()
  %c1387 = arith.constant 123 : i64
  %c1388 = arith.constant 36 : i64
  %v1389 = func.call @nx_close(%s, %c1387, %c1388, %v1076) : (!llvm.ptr, i64, i64, i64) -> i32
  %c1390 = arith.constant 1 : i32
  %v1391 = arith.cmpi eq, %v1389, %c1390 : i32
  cf.cond_br %v1391, ^bad, ^b48
^b48:
  %c1392 = arith.constant 2 : i32
  %v1393 = arith.cmpi eq, %v1389, %c1392 : i32
  cf.cond_br %v1393, ^room, ^b49
^b49:
  %c1394 = arith.constant 2 : i64
  %v1395 = func.call @nx_rd(%s, %c1394) : (!llvm.ptr, i64) -> i64
  %v1396 = arith.subi %v1395, %c1 : i64
  %c1397 = arith.constant 13 : i64
  %v1398 = func.call @nx_rp(%s, %c1397) : (!llvm.ptr, i64) -> !llvm.ptr
  %v1399 = func.call @nx_a8(%v1398, %v1396) : (!llvm.ptr, i64) -> i8
  %v1400 = arith.extui %v1399 : i8 to i64
  %v1401 = arith.cmpi ule, %v1400, %c1 : i64
  cf.cond_br %v1401, ^deflt, ^main
^g_lbrace:
  func.call @nx_push(%s, %c1) : (!llvm.ptr, i64) -> ()
  %c1402 = arith.constant 123 : i64
  %v1403 = func.call @nx_open(%s, %c1402, %v1076) : (!llvm.ptr, i64, i64) -> i32
  %c1404 = arith.constant 2 : i32
  %v1405 = arith.cmpi eq, %v1403, %c1404 : i32
  cf.cond_br %v1405, ^room, ^b50
^b50:
  cf.br ^deflt
^g_dquote:
  func.call @nx_push(%s, %c2) : (!llvm.ptr, i64) -> ()
  %c1406 = arith.constant 34 : i64
  %v1407 = func.call @nx_open(%s, %c1406, %v1076) : (!llvm.ptr, i64, i64) -> i32
  %c1408 = arith.constant 2 : i32
  %v1409 = arith.cmpi eq, %v1407, %c1408 : i32
  cf.cond_br %v1409, ^room, ^b51
^b51:
  cf.br ^main
^g_ind:
  func.call @nx_push(%s, %c3) : (!llvm.ptr, i64) -> ()
  %c1410 = arith.constant 39 : i64
  %v1411 = func.call @nx_open(%s, %c1410, %v1076) : (!llvm.ptr, i64, i64) -> i32
  %c1412 = arith.constant 2 : i32
  %v1413 = arith.cmpi eq, %v1411, %c1412 : i32
  cf.cond_br %v1413, ^room, ^b52
^b52:
  cf.br ^main
^g_pathstart:
  %c1414 = arith.constant 126 : i8
  %v1415 = arith.cmpi eq, %v1077, %c1414 : i8
  %v1416 = func.call @nx_pathseg(%src0, %n0, %v1076) : (!llvm.ptr, i64, i64) -> i64
  %v1417 = arith.addi %v1076, %c2 : i64
  %v1418 = arith.addi %v1076, %v1416 : i64
  %v1419 = arith.select %v1415, %v1417, %v1418 : i64
  %c1420 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1420, %v1419) : (!llvm.ptr, i64, i64) -> ()
  func.call @nx_push(%s, %c5) : (!llvm.ptr, i64) -> ()
  cf.br ^main
^g_path:
  %v1421 = arith.subi %v1346, %c1 : i64
  %v1422 = arith.addi %v1076, %v1421 : i64
  %v1423 = func.call @nx_at(%src0, %n0, %v1422) : (!llvm.ptr, i64, i64) -> i8
  %c1424 = arith.constant 47 : i8
  %v1425 = arith.cmpi eq, %v1423, %c1424 : i8
  %v1426 = arith.select %v1425, %c5, %c4 : i64
  func.call @nx_push(%s, %v1426) : (!llvm.ptr, i64) -> ()
  cf.br ^main
^string:
  %c1427 = arith.constant 0 : i64
  %v1428 = func.call @nx_rd(%s, %c1427) : (!llvm.ptr, i64) -> i64
  %v1429 = arith.cmpi uge, %v1428, %n0 : i64
  cf.cond_br %v1429, ^bad, ^s_body
^s_body:
  %c1430 = arith.constant 0 : i64
  %v1431 = func.call @nx_rd(%s, %c1430) : (!llvm.ptr, i64) -> i64
  %v1432 = func.call @nx_at(%src0, %n0, %v1431) : (!llvm.ptr, i64, i64) -> i8
  %c1433 = arith.constant 36 : i8
  %v1434 = arith.cmpi eq, %v1432, %c1433 : i8
  %v1435 = arith.addi %v1431, %c1 : i64
  %v1436 = func.call @nx_at(%src0, %n0, %v1435) : (!llvm.ptr, i64, i64) -> i8
  %c1437 = arith.constant 123 : i8
  %v1438 = arith.cmpi eq, %v1436, %c1437 : i8
  %v1439 = arith.andi %v1434, %v1438 : i1
  cf.cond_br %v1439, ^s_interp, ^s_quote
^s_interp:
  func.call @nx_push(%s, %c1) : (!llvm.ptr, i64) -> ()
  %c1440 = arith.constant 36 : i64
  %v1441 = func.call @nx_open(%s, %c1440, %v1431) : (!llvm.ptr, i64, i64) -> i32
  %c1442 = arith.constant 2 : i32
  %v1443 = arith.cmpi eq, %v1441, %c1442 : i32
  cf.cond_br %v1443, ^room, ^b53
^b53:
  %v1444 = arith.addi %v1431, %c2 : i64
  %c1445 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1445, %v1444) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^main
^s_quote:
  %c1446 = arith.constant 34 : i8
  %v1447 = arith.cmpi eq, %v1432, %c1446 : i8
  cf.cond_br %v1447, ^s_close, ^s_run_init
^s_close:
  %c1448 = arith.constant 2 : i64
  %v1449 = func.call @nx_rd(%s, %c1448) : (!llvm.ptr, i64) -> i64
  %v1450 = arith.subi %v1449, %c1 : i64
  %c1451 = arith.constant 2 : i64
  func.call @nx_wr(%s, %c1451, %v1450) : (!llvm.ptr, i64, i64) -> ()
  %c1452 = arith.constant 34 : i64
  %c1453 = arith.constant 34 : i64
  %v1454 = func.call @nx_close(%s, %c1452, %c1453, %v1431) : (!llvm.ptr, i64, i64, i64) -> i32
  %c1455 = arith.constant 1 : i32
  %v1456 = arith.cmpi eq, %v1454, %c1455 : i32
  cf.cond_br %v1456, ^bad, ^b54
^b54:
  %c1457 = arith.constant 2 : i32
  %v1458 = arith.cmpi eq, %v1454, %c1457 : i32
  cf.cond_br %v1458, ^room, ^b55
^b55:
  %v1459 = arith.addi %v1431, %c1 : i64
  %c1460 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1460, %v1459) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^main
^s_run_init:
  cf.br ^s_run(%v1431 : i64)
^s_run(%js: i64):
  %v1461 = arith.cmpi uge, %js, %n0 : i64
  cf.cond_br %v1461, ^s_end(%js : i64), ^s_r1
^s_r1:
  %v1462 = func.call @nx_at(%src0, %n0, %js) : (!llvm.ptr, i64, i64) -> i8
  %t1463 = llvm.mlir.addressof @nx_stopdq : !llvm.ptr
  %v1464 = func.call @nx_cls(%t1463, %v1462) : (!llvm.ptr, i8) -> i1
  %v1465 = arith.xori %v1464, %true : i1
  cf.cond_br %v1465, ^s_step, ^s_r2
^s_step:
  %v1466 = arith.addi %js, %c1 : i64
  cf.br ^s_run(%v1466 : i64)
^s_r2:
  %c1467 = arith.constant 34 : i8
  %v1468 = arith.cmpi eq, %v1462, %c1467 : i8
  cf.cond_br %v1468, ^s_end(%js : i64), ^s_r3
^s_r3:
  %v1469 = arith.cmpi eq, %v1462, %z8 : i8
  cf.cond_br %v1469, ^bad, ^s_r4
^s_r4:
  %c1470 = arith.constant 92 : i8
  %v1471 = arith.cmpi eq, %v1462, %c1470 : i8
  cf.cond_br %v1471, ^s_bs, ^s_dollar
^s_bs:
  %v1472 = arith.addi %js, %c1 : i64
  %v1473 = arith.cmpi uge, %v1472, %n0 : i64
  cf.cond_br %v1473, ^s_end(%js : i64), ^s_bs2
^s_bs2:
  %v1474 = func.call @nx_at(%src0, %n0, %v1472) : (!llvm.ptr, i64, i64) -> i8
  %v1475 = arith.cmpi eq, %v1474, %z8 : i8
  cf.cond_br %v1475, ^bad, ^s_bs3
^s_bs3:
  %v1476 = arith.addi %js, %c2 : i64
  cf.br ^s_run(%v1476 : i64)
^s_dollar:
  %v1477 = arith.addi %js, %c1 : i64
  %v1478 = arith.cmpi uge, %v1477, %n0 : i64
  cf.cond_br %v1478, ^s_end(%js : i64), ^s_d2
^s_d2:
  %v1479 = func.call @nx_at(%src0, %n0, %v1477) : (!llvm.ptr, i64, i64) -> i8
  %c1480 = arith.constant 123 : i8
  %v1481 = arith.cmpi eq, %v1479, %c1480 : i8
  cf.cond_br %v1481, ^s_end(%js : i64), ^s_d3
^s_d3:
  %c1482 = arith.constant 34 : i8
  %v1483 = arith.cmpi eq, %v1479, %c1482 : i8
  cf.cond_br %v1483, ^s_dq, ^s_d4
^s_dq:
  cf.br ^s_end(%v1477 : i64)
^s_d4:
  %v1484 = arith.cmpi eq, %v1479, %z8 : i8
  cf.cond_br %v1484, ^bad, ^s_d5
^s_d5:
  %c1485 = arith.constant 92 : i8
  %v1486 = arith.cmpi eq, %v1479, %c1485 : i8
  cf.cond_br %v1486, ^s_dbs, ^s_dskip
^s_dbs:
  %v1487 = arith.addi %js, %c2 : i64
  %v1488 = arith.cmpi uge, %v1487, %n0 : i64
  cf.cond_br %v1488, ^s_end(%js : i64), ^s_dbs2
^s_dbs2:
  %v1489 = func.call @nx_at(%src0, %n0, %v1487) : (!llvm.ptr, i64, i64) -> i8
  %v1490 = arith.cmpi eq, %v1489, %z8 : i8
  cf.cond_br %v1490, ^bad, ^s_dbs3
^s_dbs3:
  %v1491 = arith.addi %js, %c3 : i64
  cf.br ^s_run(%v1491 : i64)
^s_dskip:
  %v1492 = arith.addi %js, %c2 : i64
  cf.br ^s_run(%v1492 : i64)
^s_end(%je: i64):
  %v1493 = arith.cmpi eq, %je, %v1431 : i64
  cf.cond_br %v1493, ^bad, ^s_end2
^s_end2:
  %c1494 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1494, %je) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^string
^ind:
  %c1495 = arith.constant 0 : i64
  %v1496 = func.call @nx_rd(%s, %c1495) : (!llvm.ptr, i64) -> i64
  %v1497 = arith.cmpi uge, %v1496, %n0 : i64
  cf.cond_br %v1497, ^bad, ^i_body
^i_body:
  %c1498 = arith.constant 0 : i64
  %v1499 = func.call @nx_rd(%s, %c1498) : (!llvm.ptr, i64) -> i64
  cf.br ^i_run(%v1499 : i64)
^i_run(%ji: i64):
  %v1500 = arith.cmpi uge, %ji, %n0 : i64
  cf.cond_br %v1500, ^b56, ^i_r1
^b56:
  cf.br ^i_runend(%ji : i64)
^i_r1:
  %v1501 = func.call @nx_at(%src0, %n0, %ji) : (!llvm.ptr, i64, i64) -> i8
  %t1502 = llvm.mlir.addressof @nx_stopind : !llvm.ptr
  %v1503 = func.call @nx_cls(%t1502, %v1501) : (!llvm.ptr, i8) -> i1
  %v1504 = arith.xori %v1503, %true : i1
  cf.cond_br %v1504, ^i_step, ^i_r2
^i_step:
  %v1505 = arith.addi %ji, %c1 : i64
  cf.br ^i_run(%v1505 : i64)
^i_r2:
  %v1506 = arith.cmpi eq, %v1501, %z8 : i8
  cf.cond_br %v1506, ^bad, ^i_r3
^i_r3:
  %v1507 = arith.addi %ji, %c1 : i64
  %v1508 = arith.cmpi uge, %v1507, %n0 : i64
  cf.cond_br %v1508, ^b57, ^i_r4
^b57:
  cf.br ^i_runend(%ji : i64)
^i_r4:
  %v1509 = func.call @nx_at(%src0, %n0, %v1507) : (!llvm.ptr, i64, i64) -> i8
  %v1510 = arith.cmpi eq, %v1509, %z8 : i8
  cf.cond_br %v1510, ^bad, ^i_r5
^i_r5:
  %c1511 = arith.constant 36 : i8
  %v1512 = arith.cmpi eq, %v1501, %c1511 : i8
  %c1513 = arith.constant 123 : i8
  %v1514 = arith.cmpi ne, %v1509, %c1513 : i8
  %c1515 = arith.constant 39 : i8
  %v1516 = arith.cmpi ne, %v1509, %c1515 : i8
  %v1517 = arith.andi %v1514, %v1516 : i1
  %v1518 = arith.andi %v1512, %v1517 : i1
  cf.cond_br %v1518, ^i_adv2, ^i_r6
^i_r6:
  %v1519 = arith.cmpi eq, %v1501, %c1515 : i8
  %v1520 = arith.cmpi ne, %v1509, %c1515 : i8
  %v1521 = arith.cmpi ne, %v1509, %c1511 : i8
  %v1522 = arith.andi %v1520, %v1521 : i1
  %v1523 = arith.andi %v1519, %v1522 : i1
  cf.cond_br %v1523, ^i_adv2, ^b58
^b58:
  cf.br ^i_runend(%ji : i64)
^i_adv2:
  %v1524 = arith.addi %ji, %c2 : i64
  cf.br ^i_run(%v1524 : i64)
^i_runend(%jie: i64):
  %v1525 = arith.cmpi ugt, %jie, %v1499 : i64
  cf.cond_br %v1525, ^i_adv, ^i_stop
^i_adv:
  %c1526 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1526, %jie) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^ind
^i_stop:
  %v1527 = func.call @nx_at(%src0, %n0, %v1499) : (!llvm.ptr, i64, i64) -> i8
  %v1528 = arith.addi %v1499, %c1 : i64
  %v1529 = func.call @nx_at(%src0, %n0, %v1528) : (!llvm.ptr, i64, i64) -> i8
  %c1530 = arith.constant 39 : i8
  %v1531 = arith.cmpi eq, %v1527, %c1530 : i8
  %v1532 = arith.cmpi eq, %v1529, %c1530 : i8
  %v1533 = arith.andi %v1531, %v1532 : i1
  cf.cond_br %v1533, ^i_ind2, ^i_interp_chk
^i_ind2:
  %v1534 = arith.addi %v1499, %c2 : i64
  %v1535 = func.call @nx_at(%src0, %n0, %v1534) : (!llvm.ptr, i64, i64) -> i8
  %c1536 = arith.constant 36 : i8
  %v1537 = arith.cmpi eq, %v1535, %c1536 : i8
  cf.cond_br %v1537, ^i_skip3, ^i_ind3
^i_ind3:
  %v1538 = arith.cmpi eq, %v1535, %c1530 : i8
  cf.cond_br %v1538, ^i_skip3, ^i_ind4
^i_ind4:
  %c1539 = arith.constant 92 : i8
  %v1540 = arith.cmpi eq, %v1535, %c1539 : i8
  %v1541 = arith.addi %v1499, %c3 : i64
  %v1542 = arith.cmpi ult, %v1541, %n0 : i64
  %v1543 = arith.andi %v1540, %v1542 : i1
  cf.cond_br %v1543, ^i_skip4, ^i_close
^i_skip3:
  %v1544 = arith.addi %v1499, %c3 : i64
  %c1545 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1545, %v1544) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^ind
^i_skip4:
  %v1546 = arith.addi %v1499, %c4 : i64
  %c1547 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1547, %v1546) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^ind
^i_close:
  %c1548 = arith.constant 2 : i64
  %v1549 = func.call @nx_rd(%s, %c1548) : (!llvm.ptr, i64) -> i64
  %v1550 = arith.subi %v1549, %c1 : i64
  %c1551 = arith.constant 2 : i64
  func.call @nx_wr(%s, %c1551, %v1550) : (!llvm.ptr, i64, i64) -> ()
  %c1552 = arith.constant 39 : i64
  %c1553 = arith.constant 39 : i64
  %v1554 = func.call @nx_close(%s, %c1552, %c1553, %v1499) : (!llvm.ptr, i64, i64, i64) -> i32
  %c1555 = arith.constant 1 : i32
  %v1556 = arith.cmpi eq, %v1554, %c1555 : i32
  cf.cond_br %v1556, ^bad, ^b59
^b59:
  %c1557 = arith.constant 2 : i32
  %v1558 = arith.cmpi eq, %v1554, %c1557 : i32
  cf.cond_br %v1558, ^room, ^b60
^b60:
  %v1559 = arith.addi %v1499, %c2 : i64
  %c1560 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1560, %v1559) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^main
^i_interp_chk:
  %c1561 = arith.constant 36 : i8
  %v1562 = arith.cmpi eq, %v1527, %c1561 : i8
  %c1563 = arith.constant 123 : i8
  %v1564 = arith.cmpi eq, %v1529, %c1563 : i8
  %v1565 = arith.andi %v1562, %v1564 : i1
  cf.cond_br %v1565, ^i_interp, ^i_single
^i_interp:
  func.call @nx_push(%s, %c1) : (!llvm.ptr, i64) -> ()
  %c1566 = arith.constant 36 : i64
  %v1567 = func.call @nx_open(%s, %c1566, %v1499) : (!llvm.ptr, i64, i64) -> i32
  %c1568 = arith.constant 2 : i32
  %v1569 = arith.cmpi eq, %v1567, %c1568 : i32
  cf.cond_br %v1569, ^room, ^b61
^b61:
  %v1570 = arith.addi %v1499, %c2 : i64
  %c1571 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1571, %v1570) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^main
^i_single:
  %v1572 = arith.cmpi eq, %v1527, %c1561 : i8
  %v1573 = arith.cmpi eq, %v1527, %c1530 : i8
  %v1574 = arith.ori %v1572, %v1573 : i1
  cf.cond_br %v1574, ^i_skip1, ^bad
^i_skip1:
  %v1575 = arith.addi %v1499, %c1 : i64
  %c1576 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1576, %v1575) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^ind
^inpath:
  %c1577 = arith.constant 0 : i64
  %v1578 = func.call @nx_rd(%s, %c1577) : (!llvm.ptr, i64) -> i64
  %v1579 = func.call @nx_at(%src0, %n0, %v1578) : (!llvm.ptr, i64, i64) -> i8
  %v1580 = arith.addi %v1578, %c1 : i64
  %v1581 = func.call @nx_at(%src0, %n0, %v1580) : (!llvm.ptr, i64, i64) -> i8
  %c1582 = arith.constant 36 : i8
  %v1583 = arith.cmpi eq, %v1579, %c1582 : i8
  %c1584 = arith.constant 123 : i8
  %v1585 = arith.cmpi eq, %v1581, %c1584 : i8
  %v1586 = arith.andi %v1583, %v1585 : i1
  cf.cond_br %v1586, ^p_interp, ^p_run
^p_interp:
  %c1587 = arith.constant 2 : i64
  %v1588 = func.call @nx_rd(%s, %c1587) : (!llvm.ptr, i64) -> i64
  %v1589 = arith.subi %v1588, %c1 : i64
  %c1590 = arith.constant 2 : i64
  func.call @nx_wr(%s, %c1590, %v1589) : (!llvm.ptr, i64, i64) -> ()
  func.call @nx_push(%s, %c4) : (!llvm.ptr, i64) -> ()
  func.call @nx_push(%s, %c1) : (!llvm.ptr, i64) -> ()
  %c1591 = arith.constant 36 : i64
  %v1592 = func.call @nx_open(%s, %c1591, %v1578) : (!llvm.ptr, i64, i64) -> i32
  %c1593 = arith.constant 2 : i32
  %v1594 = arith.cmpi eq, %v1592, %c1593 : i32
  cf.cond_br %v1594, ^room, ^b62
^b62:
  %v1595 = arith.addi %v1578, %c2 : i64
  %c1596 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1596, %v1595) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^main
^p_run:
  %t1597 = llvm.mlir.addressof @nx_pathchar : !llvm.ptr
  %v1598 = func.call @nx_run(%src0, %n0, %v1578, %t1597) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %v1599 = arith.subi %v1598, %v1578 : i64
  %v1600 = func.call @nx_path(%src0, %n0, %v1578) : (!llvm.ptr, i64, i64) -> i64
  %v1601 = func.call @nx_pathseg(%src0, %n0, %v1578) : (!llvm.ptr, i64, i64) -> i64
  %v1602 = arith.maxsi %v1600, %v1601 : i64
  %v1603 = arith.maxsi %v1602, %v1599 : i64
  %v1604 = arith.cmpi ugt, %v1603, %c0 : i64
  cf.cond_br %v1604, ^p_cont, ^p_end
^p_cont:
  %c1605 = arith.constant 2 : i64
  %v1606 = func.call @nx_rd(%s, %c1605) : (!llvm.ptr, i64) -> i64
  %v1607 = arith.subi %v1606, %c1 : i64
  %c1608 = arith.constant 2 : i64
  func.call @nx_wr(%s, %c1608, %v1607) : (!llvm.ptr, i64, i64) -> ()
  %v1609 = arith.subi %v1603, %c1 : i64
  %v1610 = arith.addi %v1578, %v1609 : i64
  %v1611 = func.call @nx_at(%src0, %n0, %v1610) : (!llvm.ptr, i64, i64) -> i8
  %c1612 = arith.constant 47 : i8
  %v1613 = arith.cmpi eq, %v1611, %c1612 : i8
  %v1614 = arith.select %v1613, %c5, %c4 : i64
  func.call @nx_push(%s, %v1614) : (!llvm.ptr, i64) -> ()
  %v1615 = arith.addi %v1578, %v1603 : i64
  %c1616 = arith.constant 0 : i64
  func.call @nx_wr(%s, %c1616, %v1615) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^main
^p_end:
  %c1617 = arith.constant 2 : i64
  %v1618 = func.call @nx_rd(%s, %c1617) : (!llvm.ptr, i64) -> i64
  %v1619 = arith.subi %v1618, %c1 : i64
  %c1620 = arith.constant 13 : i64
  %v1621 = func.call @nx_rp(%s, %c1620) : (!llvm.ptr, i64) -> !llvm.ptr
  %v1622 = func.call @nx_a8(%v1621, %v1619) : (!llvm.ptr, i64) -> i8
  %v1623 = arith.extui %v1622 : i8 to i64
  %v1624 = arith.cmpi eq, %v1623, %c5 : i64
  cf.cond_br %v1624, ^bad, ^p_pop
^p_pop:
  %c1625 = arith.constant 2 : i64
  %v1626 = func.call @nx_rd(%s, %c1625) : (!llvm.ptr, i64) -> i64
  %v1627 = arith.subi %v1626, %c1 : i64
  %c1628 = arith.constant 2 : i64
  func.call @nx_wr(%s, %c1628, %v1627) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^main
}

// write the counts back to the record and give the status
func.func private @nx_finish(%s: !llvm.ptr, %rec: !llvm.ptr, %code: i32) -> i32 {
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %r = func.call @nx_rd(%s, %c6) : (!llvm.ptr, i64) -> i64
  %e = func.call @nx_rd(%s, %c7) : (!llvm.ptr, i64) -> i64
  %f8 = llvm.getelementptr %rec[0, 8] : (!llvm.ptr) -> !llvm.ptr, !rec
  llvm.store %r, %f8 : i64, !llvm.ptr
  %f9 = llvm.getelementptr %rec[0, 9] : (!llvm.ptr) -> !llvm.ptr, !rec
  llvm.store %e, %f9 : i64, !llvm.ptr
  llvm.return %code : i32
}
