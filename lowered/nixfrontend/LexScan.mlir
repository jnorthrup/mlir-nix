// The Nix lexer's token state machine (nixfe::Lexer::nextToken), hollowed from lib/Frontend/Parser.cpp into lowered
// MLIR: the DEFAULT, STRING, IND_STRING, INPATH, INPATH_SLASH start conditions with the same state stack, producing
// one Token per call.  The character classes are the 256-byte tables below (Nix/LexRules.h's isIdStart / isIdChar /
// isPathChar / isDigit, the blanks, and the single-character tokens).  The longest-match choice among the rules that
// can begin a default token is the kursive grammar lowered/kursive/LexDefault.mlir, shared with the Confix scan, called
// back per general token (nixfe_confix_match).  Keyword symbolization, integer/float reading and position accounting stay C++ callbacks
// (nixfe_lex_keyword / nixfe_lex_int / nixfe_lex_float / nixfe_lex_pos); the Token struct, the derived-text pool, the
// state stack storage, reposition and the parser integration stay in the Parser.cpp bridge.
//
// nixfe_lex_next reads and writes the record (the caller owns it): src, n, p (in/out), lex (opaque, for the position
// callback), pipeOps, stack (u8 states), sp (in/out), stackCap, then the token out fields tok, ch, hasIndent, offset,
// span (TwInt), value (int bits / double bits), posLine, posCol, errCode, errOff, dFrom, dTo, dkind.  It returns 0 when
// a token was produced, 1 at end of input (no token; the bridge makes T_EOF), 2 on a lex error (errCode/errOff; the
// bridge throws with the wording), 3 when the state stack ran out of room (the bridge doubles it and calls again).
// dkind: 0 the span is a slice of the input, 1 a fixed derived text (span = index<<32|1), 2 an unescape request
// (dFrom..dTo; the bridge calls nixfe_lex_unescape, appends the text and rewrites the span).
//
// Lowered at build time by lib/CMakeLists.txt's mlnix_lower_trikeshed (its cf loops lifted to scf first) and linked
// into NixFrontend; the C++ bridge (lib/Frontend/Parser.cpp) owns the Token and calls this entry.

!rec = !llvm.struct<(ptr, i64, i64, ptr, i64, ptr, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64)>

llvm.mlir.global internal constant @lx_idstart(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @lx_idchar(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @lx_pathchar(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @lx_digit(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @lx_ws(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>
llvm.mlir.global internal constant @lx_single(dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : tensor<256xi8>) {addr_space = 0 : i32} : !llvm.array<256 x i8>


func.func private @nixfe_confix_match(!llvm.ptr, i64, i64) -> i64
func.func private @nixfe_lex_pos(!llvm.ptr, i64) -> i64
func.func private @nixfe_lex_keyword(!llvm.ptr, i64, i64, i64) -> i64
func.func private @nixfe_lex_int(!llvm.ptr, i64, i64, i64, !llvm.ptr) -> i64
func.func private @nixfe_lex_float(!llvm.ptr, i64, i64, i64, !llvm.ptr) -> i64

// ---- record field access by index (the scalars are i64, the pointers ptr) ----
func.func private @lx_rd(%s: !llvm.ptr, %k: i64) -> i64 {
  %p = llvm.getelementptr %s[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %p : !llvm.ptr -> i64
  llvm.return %v : i64
}
func.func private @lx_wr(%s: !llvm.ptr, %k: i64, %v: i64) {
  %p = llvm.getelementptr %s[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %p : i64, !llvm.ptr
  llvm.return
}
func.func private @lx_rp(%s: !llvm.ptr, %k: i64) -> !llvm.ptr {
  %p = llvm.getelementptr %s[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %p : !llvm.ptr -> !llvm.ptr
  llvm.return %v : !llvm.ptr
}
func.func private @lx_a8(%p: !llvm.ptr, %i: i64) -> i8 {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %v = llvm.load %q : !llvm.ptr -> i8
  llvm.return %v : i8
}
func.func private @lx_s8(%p: !llvm.ptr, %i: i64, %v: i8) {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %v, %q : i8, !llvm.ptr
  llvm.return
}
// the byte at i, 0 past the end (lex::Rules::at)
func.func private @lx_at(%src: !llvm.ptr, %n: i64, %i: i64) -> i8 {
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
func.func private @lx_cls(%t: !llvm.ptr, %c: i8) -> i1 {
  %i = arith.extui %c : i8 to i32
  %p = llvm.getelementptr %t[%i] : (!llvm.ptr, i32) -> !llvm.ptr, i8
  %v = llvm.load %p : !llvm.ptr -> i8
  %z = arith.constant 0 : i8
  %r = arith.cmpi ne, %v, %z : i8
  llvm.return %r : i1
}
// the end of the run of class bytes from j
func.func private @lx_run(%src: !llvm.ptr, %n: i64, %j: i64, %t: !llvm.ptr) -> i64 {
  %r = scf.while (%j0 = %j) : (i64) -> i64 {
    %in = arith.cmpi ult, %j0, %n : i64
    %c = func.call @lx_at(%src, %n, %j0) : (!llvm.ptr, i64, i64) -> i8
    %m = func.call @lx_cls(%t, %c) : (!llvm.ptr, i8) -> i1
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
func.func private @lx_skipline(%src: !llvm.ptr, %n: i64, %j: i64) -> i64 {
  %nl = arith.constant 10 : i8
  %cr = arith.constant 13 : i8
  %r = scf.while (%j0 = %j) : (i64) -> i64 {
    %in = arith.cmpi ult, %j0, %n : i64
    %c = func.call @lx_at(%src, %n, %j0) : (!llvm.ptr, i64, i64) -> i8
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
// an identifier's length at i (lex::Rules::mId)
func.func private @lx_mid(%src: !llvm.ptr, %n: i64, %i: i64) -> i64 {
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %t = llvm.mlir.addressof @lx_idstart : !llvm.ptr
  %tc = llvm.mlir.addressof @lx_idchar : !llvm.ptr
  %true = arith.constant 1 : i1
  %c0 = func.call @lx_at(%src, %n, %i) : (!llvm.ptr, i64, i64) -> i8
  %is = func.call @lx_cls(%t, %c0) : (!llvm.ptr, i8) -> i1
  %eof = arith.cmpi uge, %i, %n : i64
  %noteof = arith.xori %eof, %true : i1
  %ok = arith.andi %is, %noteof : i1
  cf.cond_br %ok, ^run, ^zero
^zero:
  llvm.return %z : i64
^run:
  %i1__run = arith.addi %i, %one : i64
  %j__run = func.call @lx_run(%src, %n, %i1__run, %tc) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %l__run = arith.subi %j__run, %i : i64
  llvm.return %l__run : i64
}
// {PATH_CHAR}*\/ : the run and its slash, or 0 (lex::Rules::mPathSeg)
func.func private @lx_pathseg(%src: !llvm.ptr, %n: i64, %i: i64) -> i64 {
  %t = llvm.mlir.addressof @lx_pathchar : !llvm.ptr
  %j = func.call @lx_run(%src, %n, %i, %t) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %c = func.call @lx_at(%src, %n, %j) : (!llvm.ptr, i64, i64) -> i8
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
func.func private @lx_path(%src: !llvm.ptr, %n: i64, %i: i64) -> i64 {
  %t = llvm.mlir.addressof @lx_pathchar : !llvm.ptr
  %j0 = func.call @lx_run(%src, %n, %i, %t) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %sl = arith.constant 47 : i8
  cf.br ^loop(%j0, %z, %z : i64, i64, i64)
^loop(%j__loop: i64, %segs__loop: i64, %end__loop: i64):
  %cj__loop = func.call @lx_at(%src, %n, %j__loop) : (!llvm.ptr, i64, i64) -> i8
  %is__loop = arith.cmpi eq, %cj__loop, %sl : i8
  %j1__loop = arith.addi %j__loop, %one : i64
  %cn__loop = func.call @lx_at(%src, %n, %j1__loop) : (!llvm.ptr, i64, i64) -> i8
  %pc__loop = func.call @lx_cls(%t, %cn__loop) : (!llvm.ptr, i8) -> i1
  %go__loop = arith.andi %is__loop, %pc__loop : i1
  cf.cond_br %go__loop, ^body, ^done
^body:
  %j2__body = func.call @lx_run(%src, %n, %j1__loop, %t) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %segs1__body = arith.addi %segs__loop, %one : i64
  cf.br ^loop(%j2__body, %segs1__body, %j2__body : i64, i64, i64)
^done:
  %has__done = arith.cmpi ugt, %segs__loop, %z : i64
  cf.cond_br %has__done, ^trail, ^zero
^zero:
  llvm.return %z : i64
^trail:
  %ce__trail = func.call @lx_at(%src, %n, %end__loop) : (!llvm.ptr, i64, i64) -> i8
  %ist__trail = arith.cmpi eq, %ce__trail, %sl : i8
  %end1__trail = arith.addi %end__loop, %one : i64
  %e__trail = arith.select %ist__trail, %end1__trail, %end__loop : i64
  %l__trail = arith.subi %e__trail, %i : i64
  llvm.return %l__trail : i64
}
// ---- the state stack (field 5 ptr, 6 sp, 7 cap); states 0 INITIAL 1 DEFAULT 2 STRING 3 IND_STRING 4 INPATH 5 INPATH_SLASH ----
func.func private @lx_top(%s: !llvm.ptr) -> i64 {
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %one = arith.constant 1 : i64
  %sp = func.call @lx_rd(%s, %c6) : (!llvm.ptr, i64) -> i64
  %idx = arith.subi %sp, %one : i64
  %stack = func.call @lx_rp(%s, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  %v = func.call @lx_a8(%stack, %idx) : (!llvm.ptr, i64) -> i8
  %r = arith.extui %v : i8 to i64
  llvm.return %r : i64
}
func.func private @lx_push(%s: !llvm.ptr, %v: i64) -> i32 {
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %one = arith.constant 1 : i64
  %z32 = arith.constant 0 : i32
  %t32 = arith.constant 3 : i32
  %sp = func.call @lx_rd(%s, %c6) : (!llvm.ptr, i64) -> i64
  %cap = func.call @lx_rd(%s, %c7) : (!llvm.ptr, i64) -> i64
  %full = arith.cmpi uge, %sp, %cap : i64
  cf.cond_br %full, ^room, ^body
^room:
  llvm.return %t32 : i32
^body:
  %stack__body = func.call @lx_rp(%s, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  %v8__body = arith.trunci %v : i64 to i8
  func.call @lx_s8(%stack__body, %sp, %v8__body) : (!llvm.ptr, i64, i8) -> ()
  %sp1__body = arith.addi %sp, %one : i64
  func.call @lx_wr(%s, %c6, %sp1__body) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
}
func.func private @lx_pop(%s: !llvm.ptr) {
  %c6 = arith.constant 6 : i64
  %one = arith.constant 1 : i64
  %sp = func.call @lx_rd(%s, %c6) : (!llvm.ptr, i64) -> i64
  %gt = arith.cmpi ugt, %sp, %one : i64
  cf.cond_br %gt, ^dec, ^ret
^dec:
  %sp1__dec = arith.subi %sp, %one : i64
  func.call @lx_wr(%s, %c6, %sp1__dec) : (!llvm.ptr, i64, i64) -> ()
  llvm.return
^ret:
  llvm.return
}
// pos = posAt(off) via the C++ callback (field 3 lex); writes posLine (14), posCol (15)
func.func private @lx_setpos(%s: !llvm.ptr, %off: i64) {
  %c3 = arith.constant 3 : i64
  %c14 = arith.constant 14 : i64
  %c15 = arith.constant 15 : i64
  %c32 = arith.constant 32 : i64
  %mask = arith.constant 4294967295 : i64
  %lex = func.call @lx_rp(%s, %c3) : (!llvm.ptr, i64) -> !llvm.ptr
  %packed = func.call @nixfe_lex_pos(%lex, %off) : (!llvm.ptr, i64) -> i64
  %line = arith.shrui %packed, %c32 : i64
  %col = arith.andi %packed, %mask : i64
  func.call @lx_wr(%s, %c14, %line) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c15, %col) : (!llvm.ptr, i64, i64) -> ()
  llvm.return
}
// flags over [i,j): bit0 a '\\' or '\r' (needs unescape), bit1 a NUL byte
func.func private @lx_strflags(%src: !llvm.ptr, %n: i64, %i: i64, %j: i64) -> i64 {
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %two = arith.constant 2 : i64
  %bs = arith.constant 92 : i8
  %cr = arith.constant 13 : i8
  %nul = arith.constant 0 : i8
  cf.br ^loop(%i, %z : i64, i64)
^loop(%k__loop: i64, %fl__loop: i64):
  %done__loop = arith.cmpi uge, %k__loop, %j : i64
  cf.cond_br %done__loop, ^ret, ^body
^body:
  %c__body = func.call @lx_at(%src, %n, %k__loop) : (!llvm.ptr, i64, i64) -> i8
  %isbs__body = arith.cmpi eq, %c__body, %bs : i8
  %iscr__body = arith.cmpi eq, %c__body, %cr : i8
  %esc__body = arith.ori %isbs__body, %iscr__body : i1
  %isnul__body = arith.cmpi eq, %c__body, %nul : i8
  %eb__body = arith.select %esc__body, %one, %z : i64
  %nb__body = arith.select %isnul__body, %two, %z : i64
  %f1__body = arith.ori %fl__loop, %eb__body : i64
  %f2__body = arith.ori %f1__body, %nb__body : i64
  %k1__body = arith.addi %k__loop, %one : i64
  cf.br ^loop(%k1__body, %f2__body : i64, i64)
^ret:
  llvm.return %fl__loop : i64
}

// ---- unescapeStr: resolve a string piece's escapes into out (output <= input); returns the bytes written ----
func.func @nixfe_lex_unescape(%src: !llvm.ptr, %n: i64, %from: i64, %to: i64, %out: !llvm.ptr, %cap: i64) -> i64 {
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %bs = arith.constant 92 : i8
  %cr = arith.constant 13 : i8
  %nl = arith.constant 10 : i8
  %cc_n = arith.constant 110 : i8
  %cc_r = arith.constant 114 : i8
  %cc_t = arith.constant 116 : i8
  %out_n = arith.constant 10 : i8
  %out_r = arith.constant 13 : i8
  %out_t = arith.constant 9 : i8
  %z8 = arith.constant 0 : i8
  cf.br ^loop(%from, %z : i64, i64)
^loop(%i__loop: i64, %w__loop: i64):
  %done__loop = arith.cmpi uge, %i__loop, %to : i64
  cf.cond_br %done__loop, ^ret, ^body
^body:
  %c__body = func.call @lx_at(%src, %n, %i__loop) : (!llvm.ptr, i64, i64) -> i8
  %i1__body = arith.addi %i__loop, %one : i64
  %isbs__body = arith.cmpi eq, %c__body, %bs : i8
  cf.cond_br %isbs__body, ^escape, ^crchk
^crchk:
  %iscr__crchk = arith.cmpi eq, %c__body, %cr : i8
  cf.cond_br %iscr__crchk, ^carriage, ^plain
^plain:
  func.call @lx_s8(%out, %w__loop, %c__body) : (!llvm.ptr, i64, i8) -> ()
  %w1__plain = arith.addi %w__loop, %one : i64
  cf.br ^loop(%i1__body, %w1__plain : i64, i64)
^escape:
  %in__escape = arith.cmpi ult, %i1__body, %to : i64
  %cc__escape = scf.if %in__escape -> (i8) {
    %v = func.call @lx_at(%src, %n, %i1__body) : (!llvm.ptr, i64, i64) -> i8
    scf.yield %v : i8
  } else {
    scf.yield %z8 : i8
  }
  %i2b__escape = arith.addi %i1__body, %one : i64
  %i2c__escape = arith.select %in__escape, %i2b__escape, %i1__body : i64
  %isn__escape = arith.cmpi eq, %cc__escape, %cc_n : i8
  %isr__escape = arith.cmpi eq, %cc__escape, %cc_r : i8
  %ist__escape = arith.cmpi eq, %cc__escape, %cc_t : i8
  %vn__escape = arith.select %isn__escape, %out_n, %cc__escape : i8
  %vr__escape = arith.select %isr__escape, %out_r, %vn__escape : i8
  %vt__escape = arith.select %ist__escape, %out_t, %vr__escape : i8
  func.call @lx_s8(%out, %w__loop, %vt__escape) : (!llvm.ptr, i64, i8) -> ()
  %w1__escape = arith.addi %w__loop, %one : i64
  cf.br ^loop(%i2c__escape, %w1__escape : i64, i64)
^carriage:
  func.call @lx_s8(%out, %w__loop, %out_n) : (!llvm.ptr, i64, i8) -> ()
  %w1__carriage = arith.addi %w__loop, %one : i64
  %in__carriage = arith.cmpi ult, %i1__body, %to : i64
  %cn__carriage = func.call @lx_at(%src, %n, %i1__body) : (!llvm.ptr, i64, i64) -> i8
  %isnl__carriage = arith.cmpi eq, %cn__carriage, %nl : i8
  %skip__carriage = arith.andi %in__carriage, %isnl__carriage : i1
  %i2__carriage = arith.addi %i1__body, %one : i64
  %i3__carriage = arith.select %skip__carriage, %i2__carriage, %i1__body : i64
  cf.br ^loop(%i3__carriage, %w1__carriage : i64, i64)
^ret:
  llvm.return %w__loop : i64
}

// ---- lexString (S_STRING): a "..." piece, ${, the closing quote, or EOF ----
func.func private @lx_string(%s: !llvm.ptr) -> i32 {
  %c0i = arith.constant 0 : i64
  %c1i = arith.constant 1 : i64
  %c2i = arith.constant 2 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %c12 = arith.constant 12 : i64
  %c16 = arith.constant 16 : i64
  %c17 = arith.constant 17 : i64
  %c18 = arith.constant 18 : i64
  %c19 = arith.constant 19 : i64
  %c20 = arith.constant 20 : i64
  %c32 = arith.constant 32 : i64
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %two = arith.constant 2 : i64
  %three = arith.constant 3 : i64
  %z32 = arith.constant 0 : i32
  %t32 = arith.constant 3 : i32
  %e32 = arith.constant 2 : i32
  %dollar = arith.constant 36 : i8
  %lbrace = arith.constant 123 : i8
  %quote = arith.constant 34 : i8
  %bs = arith.constant 92 : i8
  %src = func.call @lx_rp(%s, %c0i) : (!llvm.ptr, i64) -> !llvm.ptr
  %n = func.call @lx_rd(%s, %c1i) : (!llvm.ptr, i64) -> i64
  %i = func.call @lx_rd(%s, %c2i) : (!llvm.ptr, i64) -> i64
  %a0 = func.call @lx_at(%src, %n, %i) : (!llvm.ptr, i64, i64) -> i8
  %i1 = arith.addi %i, %one : i64
  %a1 = func.call @lx_at(%src, %n, %i1) : (!llvm.ptr, i64, i64) -> i8
  %isd = arith.cmpi eq, %a0, %dollar : i8
  %isl = arith.cmpi eq, %a1, %lbrace : i8
  %both = arith.andi %isd, %isl : i1
  cf.cond_br %both, ^dollar, ^quotechk
^dollar:
  %st__dollar = func.call @lx_push(%s, %one) : (!llvm.ptr, i64) -> i32
  %room__dollar = arith.cmpi ne, %st__dollar, %z32 : i32
  cf.cond_br %room__dollar, ^ret3, ^dollar_ok
^dollar_ok:
  %p2__dollar_ok = arith.addi %i, %two : i64
  func.call @lx_wr(%s, %c2i, %p2__dollar_ok) : (!llvm.ptr, i64, i64) -> ()
  %tok__dollar_ok = arith.constant 11 : i64
  func.call @lx_wr(%s, %c8, %tok__dollar_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^ret3:
  llvm.return %t32 : i32
^quotechk:
  %isq__quotechk = arith.cmpi eq, %a0, %quote : i8
  cf.cond_br %isq__quotechk, ^quote_yes, ^scan
^quote_yes:
  func.call @lx_pop(%s) : (!llvm.ptr) -> ()
  %p1__quote_yes = arith.addi %i, %one : i64
  func.call @lx_wr(%s, %c2i, %p1__quote_yes) : (!llvm.ptr, i64, i64) -> ()
  %tok__quote_yes = arith.constant 36 : i64
  func.call @lx_wr(%s, %c8, %tok__quote_yes) : (!llvm.ptr, i64, i64) -> ()
  %ch__quote_yes = arith.constant 34 : i64
  func.call @lx_wr(%s, %c9, %ch__quote_yes) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^scan:
  cf.br ^loop(%i : i64)
^loop(%j__loop: i64):
  %eof__loop = arith.cmpi uge, %j__loop, %n : i64
  cf.cond_br %eof__loop, ^after(%j__loop : i64), ^body
^body:
  %c__body = func.call @lx_at(%src, %n, %j__loop) : (!llvm.ptr, i64, i64) -> i8
  %isq__body = arith.cmpi eq, %c__body, %quote : i8
  cf.cond_br %isq__body, ^after(%j__loop : i64), ^bschk
^bschk:
  %isbs__bschk = arith.cmpi eq, %c__body, %bs : i8
  cf.cond_br %isbs__bschk, ^bs_yes, ^dollarchk
^bs_yes:
  %j1__bs_yes = arith.addi %j__loop, %one : i64
  %eof1__bs_yes = arith.cmpi uge, %j1__bs_yes, %n : i64
  cf.cond_br %eof1__bs_yes, ^after(%j__loop : i64), ^bs_skip
^bs_skip:
  %j2__bs_skip = arith.addi %j__loop, %two : i64
  cf.br ^loop(%j2__bs_skip : i64)
^dollarchk:
  %isd__dollarchk = arith.cmpi eq, %c__body, %dollar : i8
  cf.cond_br %isd__dollarchk, ^dollar_body, ^plain
^plain:
  %j1__plain = arith.addi %j__loop, %one : i64
  cf.br ^loop(%j1__plain : i64)
^dollar_body:
  %j1__dollar_body = arith.addi %j__loop, %one : i64
  %nn__dollar_body = func.call @lx_at(%src, %n, %j1__dollar_body) : (!llvm.ptr, i64, i64) -> i8
  %eof1__dollar_body = arith.cmpi uge, %j1__dollar_body, %n : i64
  cf.cond_br %eof1__dollar_body, ^after(%j__loop : i64), ^dollar_n
^dollar_n:
  %isl__dollar_n = arith.cmpi eq, %nn__dollar_body, %lbrace : i8
  cf.cond_br %isl__dollar_n, ^after(%j__loop : i64), ^dollar_q
^dollar_q:
  %isq2__dollar_q = arith.cmpi eq, %nn__dollar_body, %quote : i8
  cf.cond_br %isq2__dollar_q, ^dollar_q_yes, ^dollar_bs
^dollar_q_yes:
  %j1b__dollar_q_yes = arith.addi %j__loop, %one : i64
  cf.br ^after(%j1b__dollar_q_yes : i64)
^dollar_bs:
  %isbs2__dollar_bs = arith.cmpi eq, %nn__dollar_body, %bs : i8
  cf.cond_br %isbs2__dollar_bs, ^dollar_bs_yes, ^dollar_plain
^dollar_bs_yes:
  %j2__dollar_bs_yes = arith.addi %j__loop, %two : i64
  %eof2__dollar_bs_yes = arith.cmpi uge, %j2__dollar_bs_yes, %n : i64
  cf.cond_br %eof2__dollar_bs_yes, ^after(%j__loop : i64), ^dollar_bs_skip
^dollar_bs_skip:
  %j3__dollar_bs_skip = arith.addi %j__loop, %three : i64
  cf.br ^loop(%j3__dollar_bs_skip : i64)
^dollar_plain:
  %j2__dollar_plain = arith.addi %j__loop, %two : i64
  cf.br ^loop(%j2__dollar_plain : i64)
^after(%j__after: i64):
  %eq__after = arith.cmpi eq, %j__after, %i : i64
  cf.cond_br %eq__after, ^strempty, ^strpiece
^strempty:
  func.call @lx_wr(%s, %c2i, %n) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c8, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c11, %n) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_setpos(%s, %n) : (!llvm.ptr, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^strpiece:
  %tok__strpiece = arith.constant 4 : i64
  func.call @lx_wr(%s, %c8, %tok__strpiece) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  %fl__strpiece = func.call @lx_strflags(%src, %n, %i, %j__after) : (!llvm.ptr, i64, i64, i64) -> i64
  %nulbit__strpiece = arith.andi %fl__strpiece, %two : i64
  %hasnul__strpiece = arith.cmpi ne, %nulbit__strpiece, %z : i64
  cf.cond_br %hasnul__strpiece, ^nulerr, ^escchk
^nulerr:
  %ec__nulerr = arith.constant 3 : i64
  func.call @lx_wr(%s, %c16, %ec__nulerr) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c17, %i) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %e32 : i32
^escchk:
  %escbit__escchk = arith.andi %fl__strpiece, %one : i64
  %hasesc__escchk = arith.cmpi ne, %escbit__escchk, %z : i64
  cf.cond_br %hasesc__escchk, ^unescape, ^slice
^slice:
  %sh__slice = arith.shli %i, %c32 : i64
  %sp__slice = arith.ori %sh__slice, %j__after : i64
  func.call @lx_wr(%s, %c12, %sp__slice) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^strdone
^unescape:
  %dk__unescape = arith.constant 2 : i64
  func.call @lx_wr(%s, %c20, %dk__unescape) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c18, %i) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c19, %j__after) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^strdone
^strdone:
  func.call @lx_wr(%s, %c2i, %j__after) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
}
// ---- lexIndString (S_IND_STRING): a ''...'' piece, the escapes, ${, or the close ----
func.func private @lx_ind(%s: !llvm.ptr) -> i32 {
  %c0i = arith.constant 0 : i64
  %c1i = arith.constant 1 : i64
  %c2i = arith.constant 2 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c12 = arith.constant 12 : i64
  %c16 = arith.constant 16 : i64
  %c17 = arith.constant 17 : i64
  %c18 = arith.constant 18 : i64
  %c19 = arith.constant 19 : i64
  %c20 = arith.constant 20 : i64
  %c32 = arith.constant 32 : i64
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %two = arith.constant 2 : i64
  %three = arith.constant 3 : i64
  %four = arith.constant 4 : i64
  %z32 = arith.constant 0 : i32
  %t32 = arith.constant 3 : i32
  %e32 = arith.constant 2 : i32
  %dollar = arith.constant 36 : i8
  %quote = arith.constant 39 : i8
  %lbrace = arith.constant 123 : i8
  %bs = arith.constant 92 : i8
  %true = arith.constant 1 : i1
  %src = func.call @lx_rp(%s, %c0i) : (!llvm.ptr, i64) -> !llvm.ptr
  %n = func.call @lx_rd(%s, %c1i) : (!llvm.ptr, i64) -> i64
  %i = func.call @lx_rd(%s, %c2i) : (!llvm.ptr, i64) -> i64
  cf.br ^loop(%i : i64)
^loop(%j__loop: i64):
  %eof__loop = arith.cmpi uge, %j__loop, %n : i64
  cf.cond_br %eof__loop, ^after(%j__loop : i64), ^body
^body:
  %c__body = func.call @lx_at(%src, %n, %j__loop) : (!llvm.ptr, i64, i64) -> i8
  %isd__body = arith.cmpi eq, %c__body, %dollar : i8
  %isq__body = arith.cmpi eq, %c__body, %quote : i8
  %special__body = arith.ori %isd__body, %isq__body : i1
  cf.cond_br %special__body, ^special, ^plain
^plain:
  %j1__plain = arith.addi %j__loop, %one : i64
  cf.br ^loop(%j1__plain : i64)
^special:
  %j1__special = arith.addi %j__loop, %one : i64
  %eof1__special = arith.cmpi uge, %j1__special, %n : i64
  cf.cond_br %eof1__special, ^after(%j__loop : i64), ^hasnext
^hasnext:
  %nn__hasnext = func.call @lx_at(%src, %n, %j1__special) : (!llvm.ptr, i64, i64) -> i8
  %nnl__hasnext = arith.cmpi eq, %nn__hasnext, %lbrace : i8
  %nnq__hasnext = arith.cmpi eq, %nn__hasnext, %quote : i8
  %notl__hasnext = arith.xori %nnl__hasnext, %true : i1
  %notq__hasnext = arith.xori %nnq__hasnext, %true : i1
  %a__hasnext = arith.andi %notl__hasnext, %notq__hasnext : i1
  %dollar_ok__hasnext = arith.andi %isd__body, %a__hasnext : i1
  cf.cond_br %dollar_ok__hasnext, ^adv2, ^quotechk
^quotechk:
  %nnq2__quotechk = arith.cmpi eq, %nn__hasnext, %quote : i8
  %nnd__quotechk = arith.cmpi eq, %nn__hasnext, %dollar : i8
  %notq2__quotechk = arith.xori %nnq2__quotechk, %true : i1
  %notd__quotechk = arith.xori %nnd__quotechk, %true : i1
  %b__quotechk = arith.andi %notq2__quotechk, %notd__quotechk : i1
  %quote_ok__quotechk = arith.andi %isq__body, %b__quotechk : i1
  cf.cond_br %quote_ok__quotechk, ^adv2, ^after(%j__loop : i64)
^adv2:
  %j2__adv2 = arith.addi %j__loop, %two : i64
  cf.br ^loop(%j2__adv2 : i64)
^after(%j__after: i64):
  %gt__after = arith.cmpi ugt, %j__after, %i : i64
  cf.cond_br %gt__after, ^mainpiece, ^twocomma
^mainpiece:
  %tok__mainpiece = arith.constant 5 : i64
  func.call @lx_wr(%s, %c8, %tok__mainpiece) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %one) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  %sh__mainpiece = arith.shli %i, %c32 : i64
  %sp__mainpiece = arith.ori %sh__mainpiece, %j__after : i64
  func.call @lx_wr(%s, %c12, %sp__mainpiece) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  %fl__mainpiece = func.call @lx_strflags(%src, %n, %i, %j__after) : (!llvm.ptr, i64, i64, i64) -> i64
  %nulbit__mainpiece = arith.andi %fl__mainpiece, %two : i64
  %hasnul__mainpiece = arith.cmpi ne, %nulbit__mainpiece, %z : i64
  cf.cond_br %hasnul__mainpiece, ^nulerr, ^maindone
^nulerr:
  %ec__nulerr = arith.constant 3 : i64
  func.call @lx_wr(%s, %c16, %ec__nulerr) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c17, %i) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %e32 : i32
^maindone:
  func.call @lx_wr(%s, %c2i, %j__after) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^twocomma:
  %a0__twocomma = func.call @lx_at(%src, %n, %i) : (!llvm.ptr, i64, i64) -> i8
  %i1__twocomma = arith.addi %i, %one : i64
  %a1__twocomma = func.call @lx_at(%src, %n, %i1__twocomma) : (!llvm.ptr, i64, i64) -> i8
  %q0__twocomma = arith.cmpi eq, %a0__twocomma, %quote : i8
  %q1__twocomma = arith.cmpi eq, %a1__twocomma, %quote : i8
  %both__twocomma = arith.andi %q0__twocomma, %q1__twocomma : i1
  cf.cond_br %both__twocomma, ^ind2, ^dollarchk
^ind2:
  %i2__ind2 = arith.addi %i, %two : i64
  %a2__ind2 = func.call @lx_at(%src, %n, %i2__ind2) : (!llvm.ptr, i64, i64) -> i8
  %isd__ind2 = arith.cmpi eq, %a2__ind2, %dollar : i8
  cf.cond_br %isd__ind2, ^fix_dollar, ^ind2_q
^fix_dollar:
  %tok__fix_dollar = arith.constant 5 : i64
  func.call @lx_wr(%s, %c8, %tok__fix_dollar) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %one) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %one) : (!llvm.ptr, i64, i64) -> ()
  %p3__fix_dollar = arith.addi %i, %three : i64
  func.call @lx_wr(%s, %c2i, %p3__fix_dollar) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^ind2_q:
  %isq__ind2_q = arith.cmpi eq, %a2__ind2, %quote : i8
  cf.cond_br %isq__ind2_q, ^fix_twoq, ^ind2_bs
^fix_twoq:
  %tok__fix_twoq = arith.constant 5 : i64
  func.call @lx_wr(%s, %c8, %tok__fix_twoq) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %one) : (!llvm.ptr, i64, i64) -> ()
  %sh__fix_twoq = arith.shli %one, %c32 : i64
  %sp__fix_twoq = arith.ori %sh__fix_twoq, %one : i64
  func.call @lx_wr(%s, %c12, %sp__fix_twoq) : (!llvm.ptr, i64, i64) -> ()
  %p3__fix_twoq = arith.addi %i, %three : i64
  func.call @lx_wr(%s, %c2i, %p3__fix_twoq) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^ind2_bs:
  %isbs__ind2_bs = arith.cmpi eq, %a2__ind2, %bs : i8
  %i3__ind2_bs = arith.addi %i, %three : i64
  %eof3__ind2_bs = arith.cmpi uge, %i3__ind2_bs, %n : i64
  %noteof3__ind2_bs = arith.xori %eof3__ind2_bs, %true : i1
  %ok__ind2_bs = arith.andi %isbs__ind2_bs, %noteof3__ind2_bs : i1
  cf.cond_br %ok__ind2_bs, ^derived_bs, ^close
^derived_bs:
  %tok__derived_bs = arith.constant 5 : i64
  func.call @lx_wr(%s, %c8, %tok__derived_bs) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %two) : (!llvm.ptr, i64, i64) -> ()
  %i4__derived_bs = arith.addi %i, %four : i64
  func.call @lx_wr(%s, %c18, %i2__ind2) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c19, %i4__derived_bs) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %i4__derived_bs) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^close:
  func.call @lx_pop(%s) : (!llvm.ptr) -> ()
  %p2__close = arith.addi %i, %two : i64
  func.call @lx_wr(%s, %c2i, %p2__close) : (!llvm.ptr, i64, i64) -> ()
  %tok__close = arith.constant 13 : i64
  func.call @lx_wr(%s, %c8, %tok__close) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^dollarchk:
  %isd0__dollarchk = arith.cmpi eq, %a0__twocomma, %dollar : i8
  %isl1__dollarchk = arith.cmpi eq, %a1__twocomma, %lbrace : i8
  %bothd__dollarchk = arith.andi %isd0__dollarchk, %isl1__dollarchk : i1
  cf.cond_br %bothd__dollarchk, ^ind_dollar, ^single_d
^ind_dollar:
  %st__ind_dollar = func.call @lx_push(%s, %one) : (!llvm.ptr, i64) -> i32
  %room__ind_dollar = arith.cmpi ne, %st__ind_dollar, %z32 : i32
  cf.cond_br %room__ind_dollar, ^ret3, ^ind_dollar_ok
^ind_dollar_ok:
  %p2__ind_dollar_ok = arith.addi %i, %two : i64
  func.call @lx_wr(%s, %c2i, %p2__ind_dollar_ok) : (!llvm.ptr, i64, i64) -> ()
  %tok__ind_dollar_ok = arith.constant 11 : i64
  func.call @lx_wr(%s, %c8, %tok__ind_dollar_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^ret3:
  llvm.return %t32 : i32
^single_d:
  %isd0b__single_d = arith.cmpi eq, %a0__twocomma, %dollar : i8
  cf.cond_br %isd0b__single_d, ^fix_dollar1, ^single_q
^fix_dollar1:
  %tok__fix_dollar1 = arith.constant 5 : i64
  func.call @lx_wr(%s, %c8, %tok__fix_dollar1) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %one) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %one) : (!llvm.ptr, i64, i64) -> ()
  %p1__fix_dollar1 = arith.addi %i, %one : i64
  func.call @lx_wr(%s, %c2i, %p1__fix_dollar1) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^single_q:
  %isq0__single_q = arith.cmpi eq, %a0__twocomma, %quote : i8
  cf.cond_br %isq0__single_q, ^fix_quote1, ^unreach
^fix_quote1:
  %tok__fix_quote1 = arith.constant 5 : i64
  func.call @lx_wr(%s, %c8, %tok__fix_quote1) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %one) : (!llvm.ptr, i64, i64) -> ()
  %sh__fix_quote1 = arith.shli %two, %c32 : i64
  %sp__fix_quote1 = arith.ori %sh__fix_quote1, %one : i64
  func.call @lx_wr(%s, %c12, %sp__fix_quote1) : (!llvm.ptr, i64, i64) -> ()
  %p1__fix_quote1 = arith.addi %i, %one : i64
  func.call @lx_wr(%s, %c2i, %p1__fix_quote1) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^unreach:
  %ec__unreach = arith.constant 2 : i64
  func.call @lx_wr(%s, %c16, %ec__unreach) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c17, %i) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %e32 : i32
}

// ---- lexInPath (S_INPATH / S_INPATH_SLASH): a path segment, ${, or the path end ----
func.func private @lx_inpath(%s: !llvm.ptr) -> i32 {
  %c0i = arith.constant 0 : i64
  %c1i = arith.constant 1 : i64
  %c2i = arith.constant 2 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c12 = arith.constant 12 : i64
  %c16 = arith.constant 16 : i64
  %c17 = arith.constant 17 : i64
  %c20 = arith.constant 20 : i64
  %c32 = arith.constant 32 : i64
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %two = arith.constant 2 : i64
  %four = arith.constant 4 : i64
  %five = arith.constant 5 : i64
  %z32 = arith.constant 0 : i32
  %t32 = arith.constant 3 : i32
  %e32 = arith.constant 2 : i32
  %dollar = arith.constant 36 : i8
  %lbrace = arith.constant 123 : i8
  %sl = arith.constant 47 : i8
  %src = func.call @lx_rp(%s, %c0i) : (!llvm.ptr, i64) -> !llvm.ptr
  %n = func.call @lx_rd(%s, %c1i) : (!llvm.ptr, i64) -> i64
  %i = func.call @lx_rd(%s, %c2i) : (!llvm.ptr, i64) -> i64
  %a0 = func.call @lx_at(%src, %n, %i) : (!llvm.ptr, i64, i64) -> i8
  %i1 = arith.addi %i, %one : i64
  %a1 = func.call @lx_at(%src, %n, %i1) : (!llvm.ptr, i64, i64) -> i8
  %isd = arith.cmpi eq, %a0, %dollar : i8
  %isl = arith.cmpi eq, %a1, %lbrace : i8
  %both = arith.andi %isd, %isl : i1
  cf.cond_br %both, ^ip_dollar, ^match
^ip_dollar:
  %sp__ip_dollar = func.call @lx_rd(%s, %c6) : (!llvm.ptr, i64) -> i64
  %cap__ip_dollar = func.call @lx_rd(%s, %c7) : (!llvm.ptr, i64) -> i64
  %sp1__ip_dollar = arith.addi %sp__ip_dollar, %one : i64
  %over__ip_dollar = arith.cmpi ugt, %sp1__ip_dollar, %cap__ip_dollar : i64
  cf.cond_br %over__ip_dollar, ^ret3, ^ip_dollar_ok
^ip_dollar_ok:
  func.call @lx_pop(%s) : (!llvm.ptr) -> ()
  %st1__ip_dollar_ok = func.call @lx_push(%s, %four) : (!llvm.ptr, i64) -> i32
  %st2__ip_dollar_ok = func.call @lx_push(%s, %one) : (!llvm.ptr, i64) -> i32
  %p2__ip_dollar_ok = arith.addi %i, %two : i64
  func.call @lx_wr(%s, %c2i, %p2__ip_dollar_ok) : (!llvm.ptr, i64, i64) -> ()
  %tok__ip_dollar_ok = arith.constant 11 : i64
  func.call @lx_wr(%s, %c8, %tok__ip_dollar_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^ret3:
  llvm.return %t32 : i32
^match:
  %lp__match = func.call @lx_path(%src, %n, %i) : (!llvm.ptr, i64, i64) -> i64
  %ls__match = func.call @lx_pathseg(%src, %n, %i) : (!llvm.ptr, i64, i64) -> i64
  %t__match = llvm.mlir.addressof @lx_pathchar : !llvm.ptr
  %jr__match = func.call @lx_run(%src, %n, %i, %t__match) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %lr__match = arith.subi %jr__match, %i : i64
  %m1__match = arith.maxui %lp__match, %ls__match : i64
  %l__match = arith.maxui %m1__match, %lr__match : i64
  %hasl__match = arith.cmpi ugt, %l__match, %z : i64
  cf.cond_br %hasl__match, ^piece, ^end
^piece:
  func.call @lx_pop(%s) : (!llvm.ptr) -> ()
  %il1__piece = arith.addi %i, %l__match : i64
  %il1b__piece = arith.subi %il1__piece, %one : i64
  %cl__piece = func.call @lx_at(%src, %n, %il1b__piece) : (!llvm.ptr, i64, i64) -> i8
  %issl__piece = arith.cmpi eq, %cl__piece, %sl : i8
  %state__piece = arith.select %issl__piece, %five, %four : i64
  %st__piece = func.call @lx_push(%s, %state__piece) : (!llvm.ptr, i64) -> i32
  %tok__piece = arith.constant 4 : i64
  func.call @lx_wr(%s, %c8, %tok__piece) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  %sh__piece = arith.shli %i, %c32 : i64
  %spv__piece = arith.ori %sh__piece, %il1__piece : i64
  func.call @lx_wr(%s, %c12, %spv__piece) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %il1__piece) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^end:
  %top__end = func.call @lx_top(%s) : (!llvm.ptr) -> i64
  %issl__end = arith.cmpi eq, %top__end, %five : i64
  cf.cond_br %issl__end, ^trailerr, ^pathend
^trailerr:
  func.call @lx_wr(%s, %c16, %one) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c17, %i) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %e32 : i32
^pathend:
  func.call @lx_pop(%s) : (!llvm.ptr) -> ()
  %tok__pathend = arith.constant 10 : i64
  func.call @lx_wr(%s, %c8, %tok__pathend) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
}
// ---- lexDefault (S_INITIAL / S_DEFAULT): the fast paths, then the longest-match rule ----
// returns 0 token, 2 error, 3 room, 4 continue (whitespace / comment)
func.func private @lx_default(%s: !llvm.ptr) -> i32 {
  %c0i = arith.constant 0 : i64
  %c1i = arith.constant 1 : i64
  %c2i = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c12 = arith.constant 12 : i64
  %c13 = arith.constant 13 : i64
  %c16 = arith.constant 16 : i64
  %c17 = arith.constant 17 : i64
  %c20 = arith.constant 20 : i64
  %c32 = arith.constant 32 : i64
  %mask = arith.constant 4294967295 : i64
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %two = arith.constant 2 : i64
  %ten = arith.constant 10 : i64
  %twentytwo = arith.constant 22 : i64
  %fourteen = arith.constant 14 : i64
  %twentyfour = arith.constant 24 : i64
  %z32 = arith.constant 0 : i32
  %t32 = arith.constant 3 : i32
  %e32 = arith.constant 2 : i32
  %cont32 = arith.constant 4 : i32
  %true = arith.constant 1 : i1
  %src = func.call @lx_rp(%s, %c0i) : (!llvm.ptr, i64) -> !llvm.ptr
  %n = func.call @lx_rd(%s, %c1i) : (!llvm.ptr, i64) -> i64
  %i = func.call @lx_rd(%s, %c2i) : (!llvm.ptr, i64) -> i64
  %c = func.call @lx_at(%src, %n, %i) : (!llvm.ptr, i64, i64) -> i8
  %tsingle = llvm.mlir.addressof @lx_single : !llvm.ptr
  %issingle = func.call @lx_cls(%tsingle, %c) : (!llvm.ptr, i8) -> i1
  cf.cond_br %issingle, ^single, ^idstart
^single:
  %p1__single = arith.addi %i, %one : i64
  func.call @lx_wr(%s, %c2i, %p1__single) : (!llvm.ptr, i64, i64) -> ()
  %tok__single = arith.constant 36 : i64
  func.call @lx_wr(%s, %c8, %tok__single) : (!llvm.ptr, i64, i64) -> ()
  %ch__single = arith.extui %c : i8 to i64
  func.call @lx_wr(%s, %c9, %ch__single) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^idstart:
  %tid__idstart = llvm.mlir.addressof @lx_idstart : !llvm.ptr
  %isid__idstart = func.call @lx_cls(%tid__idstart, %c) : (!llvm.ptr, i8) -> i1
  cf.cond_br %isid__idstart, ^idpath, ^common
^idpath:
  %tpc__idpath = llvm.mlir.addressof @lx_pathchar : !llvm.ptr
  %i1__idpath = arith.addi %i, %one : i64
  %j__idpath = func.call @lx_run(%src, %n, %i1__idpath, %tpc__idpath) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %after__idpath = func.call @lx_at(%src, %n, %j__idpath) : (!llvm.ptr, i64, i64) -> i8
  %sl__idpath = arith.constant 47 : i8
  %co__idpath = arith.constant 58 : i8
  %issl__idpath = arith.cmpi eq, %after__idpath, %sl__idpath : i8
  %isco__idpath = arith.cmpi eq, %after__idpath, %co__idpath : i8
  %either__idpath = arith.ori %issl__idpath, %isco__idpath : i1
  %neither__idpath = arith.xori %either__idpath, %true : i1
  cf.cond_br %neither__idpath, ^idfast, ^common
^idfast:
  %len__idfast = func.call @lx_mid(%src, %n, %i) : (!llvm.ptr, i64, i64) -> i64
  %kw__idfast = func.call @nixfe_lex_keyword(%src, %n, %i, %len__idfast) : (!llvm.ptr, i64, i64, i64) -> i64
  func.call @lx_wr(%s, %c8, %kw__idfast) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  %isidtok__idfast = arith.cmpi eq, %kw__idfast, %one : i64
  cf.cond_br %isidtok__idfast, ^idfast_slice, ^idfast_p
^idfast_slice:
  %ie__idfast_slice = arith.addi %i, %len__idfast : i64
  %sh__idfast_slice = arith.shli %i, %c32 : i64
  %spv__idfast_slice = arith.ori %sh__idfast_slice, %ie__idfast_slice : i64
  func.call @lx_wr(%s, %c12, %spv__idfast_slice) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^idfast_p
^idfast_p:
  %ie__idfast_p = arith.addi %i, %len__idfast : i64
  func.call @lx_wr(%s, %c2i, %ie__idfast_p) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^common:
  %lb__common = arith.constant 123 : i8
  %islbrace__common = arith.cmpi eq, %c, %lb__common : i8
  cf.cond_br %islbrace__common, ^lbrace, ^rbrace
^lbrace:
  %st__lbrace = func.call @lx_push(%s, %one) : (!llvm.ptr, i64) -> i32
  %room__lbrace = arith.cmpi ne, %st__lbrace, %z32 : i32
  cf.cond_br %room__lbrace, ^ret3, ^lbrace_ok
^lbrace_ok:
  %p1__lbrace_ok = arith.addi %i, %one : i64
  func.call @lx_wr(%s, %c2i, %p1__lbrace_ok) : (!llvm.ptr, i64, i64) -> ()
  %tok__lbrace_ok = arith.constant 36 : i64
  func.call @lx_wr(%s, %c8, %tok__lbrace_ok) : (!llvm.ptr, i64, i64) -> ()
  %ch__lbrace_ok = arith.constant 123 : i64
  func.call @lx_wr(%s, %c9, %ch__lbrace_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^ret3:
  llvm.return %t32 : i32
^rbrace:
  %rb__rbrace = arith.constant 125 : i8
  %isrbrace__rbrace = arith.cmpi eq, %c, %rb__rbrace : i8
  cf.cond_br %isrbrace__rbrace, ^rbrace_yes, ^dquote
^rbrace_yes:
  %p1__rbrace_yes = arith.addi %i, %one : i64
  func.call @lx_wr(%s, %c2i, %p1__rbrace_yes) : (!llvm.ptr, i64, i64) -> ()
  %top__rbrace_yes = func.call @lx_top(%s) : (!llvm.ptr) -> i64
  %isinit__rbrace_yes = arith.cmpi eq, %top__rbrace_yes, %z : i64
  %notinit__rbrace_yes = arith.xori %isinit__rbrace_yes, %true : i1
  cf.cond_br %notinit__rbrace_yes, ^rbrace_pop, ^rbrace_tok
^rbrace_pop:
  func.call @lx_pop(%s) : (!llvm.ptr) -> ()
  cf.br ^rbrace_tok
^rbrace_tok:
  %tok__rbrace_tok = arith.constant 36 : i64
  func.call @lx_wr(%s, %c8, %tok__rbrace_tok) : (!llvm.ptr, i64, i64) -> ()
  %ch__rbrace_tok = arith.constant 125 : i64
  func.call @lx_wr(%s, %c9, %ch__rbrace_tok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^dquote:
  %dq__dquote = arith.constant 34 : i8
  %isdq__dquote = arith.cmpi eq, %c, %dq__dquote : i8
  cf.cond_br %isdq__dquote, ^dquote_yes, ^eqchk
^dquote_yes:
  %st__dquote_yes = func.call @lx_push(%s, %two) : (!llvm.ptr, i64) -> i32
  %room__dquote_yes = arith.cmpi ne, %st__dquote_yes, %z32 : i32
  cf.cond_br %room__dquote_yes, ^ret3, ^dquote_ok
^dquote_ok:
  %p1__dquote_ok = arith.addi %i, %one : i64
  func.call @lx_wr(%s, %c2i, %p1__dquote_ok) : (!llvm.ptr, i64, i64) -> ()
  %tok__dquote_ok = arith.constant 36 : i64
  func.call @lx_wr(%s, %c8, %tok__dquote_ok) : (!llvm.ptr, i64, i64) -> ()
  %ch__dquote_ok = arith.constant 34 : i64
  func.call @lx_wr(%s, %c9, %ch__dquote_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^eqchk:
  %eqc__eqchk = arith.constant 61 : i8
  %iseq__eqchk = arith.cmpi eq, %c, %eqc__eqchk : i8
  cf.cond_br %iseq__eqchk, ^eq_yes, ^opchk
^eq_yes:
  %i1__eq_yes = arith.addi %i, %one : i64
  %nn__eq_yes = func.call @lx_at(%src, %n, %i1__eq_yes) : (!llvm.ptr, i64, i64) -> i8
  %iseq2__eq_yes = arith.cmpi eq, %nn__eq_yes, %eqc__eqchk : i8
  cf.cond_br %iseq2__eq_yes, ^general, ^eq_plain
^eq_plain:
  %p1__eq_plain = arith.addi %i, %one : i64
  func.call @lx_wr(%s, %c2i, %p1__eq_plain) : (!llvm.ptr, i64, i64) -> ()
  %tok__eq_plain = arith.constant 36 : i64
  func.call @lx_wr(%s, %c8, %tok__eq_plain) : (!llvm.ptr, i64, i64) -> ()
  %ch__eq_plain = arith.constant 61 : i64
  func.call @lx_wr(%s, %c9, %ch__eq_plain) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^opchk:
  %mm__opchk = arith.constant 45 : i8
  %pp__opchk = arith.constant 43 : i8
  %lt__opchk = arith.constant 60 : i8
  %gt__opchk = arith.constant 62 : i8
  %nt__opchk = arith.constant 33 : i8
  %ism__opchk = arith.cmpi eq, %c, %mm__opchk : i8
  %isp__opchk = arith.cmpi eq, %c, %pp__opchk : i8
  %islt__opchk = arith.cmpi eq, %c, %lt__opchk : i8
  %isgt__opchk = arith.cmpi eq, %c, %gt__opchk : i8
  %isnt__opchk = arith.cmpi eq, %c, %nt__opchk : i8
  %a__opchk = arith.ori %ism__opchk, %isp__opchk : i1
  %b__opchk = arith.ori %islt__opchk, %isgt__opchk : i1
  %d__opchk = arith.ori %a__opchk, %b__opchk : i1
  %isop__opchk = arith.ori %d__opchk, %isnt__opchk : i1
  cf.cond_br %isop__opchk, ^op_sp, ^dotchk
^op_sp:
  %i1__op_sp = arith.addi %i, %one : i64
  %nn__op_sp = func.call @lx_at(%src, %n, %i1__op_sp) : (!llvm.ptr, i64, i64) -> i8
  %spc__op_sp = arith.constant 32 : i8
  %issp__op_sp = arith.cmpi eq, %nn__op_sp, %spc__op_sp : i8
  cf.cond_br %issp__op_sp, ^op_plain, ^general
^op_plain:
  %p1__op_plain = arith.addi %i, %one : i64
  func.call @lx_wr(%s, %c2i, %p1__op_plain) : (!llvm.ptr, i64, i64) -> ()
  %tok__op_plain = arith.constant 36 : i64
  func.call @lx_wr(%s, %c8, %tok__op_plain) : (!llvm.ptr, i64, i64) -> ()
  %ch__op_plain = arith.extui %c : i8 to i64
  func.call @lx_wr(%s, %c9, %ch__op_plain) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^dotchk:
  %dotc__dotchk = arith.constant 46 : i8
  %isdot__dotchk = arith.cmpi eq, %c, %dotc__dotchk : i8
  cf.cond_br %isdot__dotchk, ^dot_yes, ^general
^dot_yes:
  %i1__dot_yes = arith.addi %i, %one : i64
  %nn__dot_yes = func.call @lx_at(%src, %n, %i1__dot_yes) : (!llvm.ptr, i64, i64) -> i8
  %td__dot_yes = llvm.mlir.addressof @lx_digit : !llvm.ptr
  %isdigit__dot_yes = func.call @lx_cls(%td__dot_yes, %nn__dot_yes) : (!llvm.ptr, i8) -> i1
  %isdot2__dot_yes = arith.cmpi eq, %nn__dot_yes, %dotc__dotchk : i8
  %sl__dot_yes = arith.constant 47 : i8
  %issl__dot_yes = arith.cmpi eq, %nn__dot_yes, %sl__dot_yes : i8
  %x__dot_yes = arith.ori %isdigit__dot_yes, %isdot2__dot_yes : i1
  %stop__dot_yes = arith.ori %x__dot_yes, %issl__dot_yes : i1
  cf.cond_br %stop__dot_yes, ^general, ^dot_path
^dot_path:
  %tpc__dot_path = llvm.mlir.addressof @lx_pathchar : !llvm.ptr
  %ispc__dot_path = func.call @lx_cls(%tpc__dot_path, %nn__dot_yes) : (!llvm.ptr, i8) -> i1
  cf.cond_br %ispc__dot_path, ^dot_run, ^dot_plain
^dot_run:
  %i2__dot_run = arith.addi %i, %two : i64
  %j__dot_run = func.call @lx_run(%src, %n, %i2__dot_run, %tpc__dot_path) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %aj__dot_run = func.call @lx_at(%src, %n, %j__dot_run) : (!llvm.ptr, i64, i64) -> i8
  %issl2__dot_run = arith.cmpi eq, %aj__dot_run, %sl__dot_yes : i8
  cf.cond_br %issl2__dot_run, ^general, ^dot_plain
^dot_plain:
  %p1__dot_plain = arith.addi %i, %one : i64
  func.call @lx_wr(%s, %c2i, %p1__dot_plain) : (!llvm.ptr, i64, i64) -> ()
  %tok__dot_plain = arith.constant 36 : i64
  func.call @lx_wr(%s, %c8, %tok__dot_plain) : (!llvm.ptr, i64, i64) -> ()
  %ch__dot_plain = arith.constant 46 : i64
  func.call @lx_wr(%s, %c9, %ch__dot_plain) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^general:
  %m__general = func.call @nixfe_confix_match(%src, %n, %i) : (!llvm.ptr, i64, i64) -> i64
  %len__general = arith.shrui %m__general, %c32 : i64
  %rule__general = arith.andi %m__general, %mask : i64
  %ie__general = arith.addi %i, %len__general : i64
  %iskw__general = arith.cmpi ult, %rule__general, %ten : i64
  cf.cond_br %iskw__general, ^kw, ^oprule
^kw:
  %tok__kw = arith.addi %rule__general, %fourteen : i64
  func.call @lx_wr(%s, %c8, %tok__kw) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^oprule:
  %isop__oprule = arith.cmpi ult, %rule__general, %twentytwo : i64
  cf.cond_br %isop__oprule, ^op, ^rest
^op:
  %r10__op = arith.subi %rule__general, %ten : i64
  %tok__op = arith.addi %r10__op, %twentyfour : i64
  func.call @lx_wr(%s, %c8, %tok__op) : (!llvm.ptr, i64, i64) -> ()
  %pf__op = arith.constant 34 : i64
  %pi__op = arith.constant 35 : i64
  %isfrom__op = arith.cmpi eq, %tok__op, %pf__op : i64
  %isinto__op = arith.cmpi eq, %tok__op, %pi__op : i64
  %ispipe__op = arith.ori %isfrom__op, %isinto__op : i1
  cf.cond_br %ispipe__op, ^pipechk, ^op_done
^pipechk:
  %pipeops__pipechk = func.call @lx_rd(%s, %c4) : (!llvm.ptr, i64) -> i64
  %enabled__pipechk = arith.cmpi ne, %pipeops__pipechk, %z : i64
  cf.cond_br %enabled__pipechk, ^op_done, ^pipeerr
^pipeerr:
  %ec__pipeerr = arith.constant 6 : i64
  func.call @lx_wr(%s, %c16, %ec__pipeerr) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c17, %i) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %e32 : i32
^op_done:
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^rest:
  %r30__rest = arith.constant 30 : i64
  %isid__rest = arith.cmpi eq, %rule__general, %r30__rest : i64
  cf.cond_br %isid__rest, ^rid, ^rintchk
^rid:
  %tok__rid = arith.constant 1 : i64
  func.call @lx_wr(%s, %c8, %tok__rid) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  %sh__rid = arith.shli %i, %c32 : i64
  %spv__rid = arith.ori %sh__rid, %ie__general : i64
  func.call @lx_wr(%s, %c12, %spv__rid) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^rintchk:
  %r31__rintchk = arith.constant 31 : i64
  %isint__rintchk = arith.cmpi eq, %rule__general, %r31__rintchk : i64
  cf.cond_br %isint__rintchk, ^rint, ^rfloatchk
^rint:
  %slot__rint = llvm.alloca %one x i64 : (i64) -> !llvm.ptr
  %flag__rint = func.call @nixfe_lex_int(%src, %n, %i, %len__general, %slot__rint) : (!llvm.ptr, i64, i64, i64, !llvm.ptr) -> i64
  %bad__rint = arith.cmpi ne, %flag__rint, %z : i64
  cf.cond_br %bad__rint, ^interr, ^int_ok
^interr:
  %ec__interr = arith.constant 4 : i64
  func.call @lx_wr(%s, %c16, %ec__interr) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c17, %i) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %e32 : i32
^int_ok:
  %v__int_ok = llvm.load %slot__rint : !llvm.ptr -> i64
  %tok__int_ok = arith.constant 2 : i64
  func.call @lx_wr(%s, %c8, %tok__int_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c13, %v__int_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^rfloatchk:
  %r32__rfloatchk = arith.constant 32 : i64
  %isfloat__rfloatchk = arith.cmpi eq, %rule__general, %r32__rfloatchk : i64
  cf.cond_br %isfloat__rfloatchk, ^rfloat, ^rdollarchk
^rfloat:
  %slot__rfloat = llvm.alloca %one x i64 : (i64) -> !llvm.ptr
  %flag__rfloat = func.call @nixfe_lex_float(%src, %n, %i, %len__general, %slot__rfloat) : (!llvm.ptr, i64, i64, i64, !llvm.ptr) -> i64
  %bad__rfloat = arith.cmpi ne, %flag__rfloat, %z : i64
  cf.cond_br %bad__rfloat, ^floaterr, ^float_ok
^floaterr:
  %ec__floaterr = arith.constant 5 : i64
  func.call @lx_wr(%s, %c16, %ec__floaterr) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c17, %i) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %e32 : i32
^float_ok:
  %v__float_ok = llvm.load %slot__rfloat : !llvm.ptr -> i64
  %tok__float_ok = arith.constant 3 : i64
  func.call @lx_wr(%s, %c8, %tok__float_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c13, %v__float_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^rdollarchk:
  %r33__rdollarchk = arith.constant 33 : i64
  %isdollar__rdollarchk = arith.cmpi eq, %rule__general, %r33__rdollarchk : i64
  cf.cond_br %isdollar__rdollarchk, ^rdollar, ^rrbracechk
^rdollar:
  %st__rdollar = func.call @lx_push(%s, %one) : (!llvm.ptr, i64) -> i32
  %room__rdollar = arith.cmpi ne, %st__rdollar, %z32 : i32
  cf.cond_br %room__rdollar, ^ret3, ^rdollar_ok
^rdollar_ok:
  %tok__rdollar_ok = arith.constant 11 : i64
  func.call @lx_wr(%s, %c8, %tok__rdollar_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^rrbracechk:
  %r34__rrbracechk = arith.constant 34 : i64
  %isrbrace__rrbracechk = arith.cmpi eq, %rule__general, %r34__rrbracechk : i64
  cf.cond_br %isrbrace__rrbracechk, ^rrbrace, ^rlbracechk
^rrbrace:
  %top__rrbrace = func.call @lx_top(%s) : (!llvm.ptr) -> i64
  %isinit__rrbrace = arith.cmpi eq, %top__rrbrace, %z : i64
  %notinit__rrbrace = arith.xori %isinit__rrbrace, %true : i1
  cf.cond_br %notinit__rrbrace, ^rrbrace_pop, ^rrbrace_tok
^rrbrace_pop:
  func.call @lx_pop(%s) : (!llvm.ptr) -> ()
  cf.br ^rrbrace_tok
^rrbrace_tok:
  %tok__rrbrace_tok = arith.constant 36 : i64
  func.call @lx_wr(%s, %c8, %tok__rrbrace_tok) : (!llvm.ptr, i64, i64) -> ()
  %ch__rrbrace_tok = arith.constant 125 : i64
  func.call @lx_wr(%s, %c9, %ch__rrbrace_tok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^rlbracechk:
  %r35__rlbracechk = arith.constant 35 : i64
  %islbrace__rlbracechk = arith.cmpi eq, %rule__general, %r35__rlbracechk : i64
  cf.cond_br %islbrace__rlbracechk, ^rlbrace, ^rdquotechk
^rlbrace:
  %st__rlbrace = func.call @lx_push(%s, %one) : (!llvm.ptr, i64) -> i32
  %room__rlbrace = arith.cmpi ne, %st__rlbrace, %z32 : i32
  cf.cond_br %room__rlbrace, ^ret3, ^rlbrace_ok
^rlbrace_ok:
  %tok__rlbrace_ok = arith.constant 36 : i64
  func.call @lx_wr(%s, %c8, %tok__rlbrace_ok) : (!llvm.ptr, i64, i64) -> ()
  %ch__rlbrace_ok = arith.constant 123 : i64
  func.call @lx_wr(%s, %c9, %ch__rlbrace_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^rdquotechk:
  %r36__rdquotechk = arith.constant 36 : i64
  %isdquote__rdquotechk = arith.cmpi eq, %rule__general, %r36__rdquotechk : i64
  cf.cond_br %isdquote__rdquotechk, ^rdquote, ^rindopenchk
^rdquote:
  %st__rdquote = func.call @lx_push(%s, %two) : (!llvm.ptr, i64) -> i32
  %room__rdquote = arith.cmpi ne, %st__rdquote, %z32 : i32
  cf.cond_br %room__rdquote, ^ret3, ^rdquote_ok
^rdquote_ok:
  %tok__rdquote_ok = arith.constant 36 : i64
  func.call @lx_wr(%s, %c8, %tok__rdquote_ok) : (!llvm.ptr, i64, i64) -> ()
  %ch__rdquote_ok = arith.constant 34 : i64
  func.call @lx_wr(%s, %c9, %ch__rdquote_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^rindopenchk:
  %r37__rindopenchk = arith.constant 37 : i64
  %isindopen__rindopenchk = arith.cmpi eq, %rule__general, %r37__rindopenchk : i64
  cf.cond_br %isindopen__rindopenchk, ^rindopen, ^rpathstartchk
^rindopen:
  %three__rindopen = arith.constant 3 : i64
  %st__rindopen = func.call @lx_push(%s, %three__rindopen) : (!llvm.ptr, i64) -> i32
  %room__rindopen = arith.cmpi ne, %st__rindopen, %z32 : i32
  cf.cond_br %room__rindopen, ^ret3, ^rindopen_ok
^rindopen_ok:
  %tok__rindopen_ok = arith.constant 12 : i64
  func.call @lx_wr(%s, %c8, %tok__rindopen_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^rpathstartchk:
  %r38__rpathstartchk = arith.constant 38 : i64
  %ispathstart__rpathstartchk = arith.cmpi eq, %rule__general, %r38__rpathstartchk : i64
  cf.cond_br %ispathstart__rpathstartchk, ^rpathstart, ^rpathchk
^rpathstart:
  %tilde__rpathstart = arith.constant 126 : i8
  %istilde__rpathstart = arith.cmpi eq, %c, %tilde__rpathstart : i8
  cf.cond_br %istilde__rpathstart, ^rpathstart_home, ^rpathstart_seg
^rpathstart_home:
  %five__rpathstart_home = arith.constant 5 : i64
  %st__rpathstart_home = func.call @lx_push(%s, %five__rpathstart_home) : (!llvm.ptr, i64) -> i32
  %room__rpathstart_home = arith.cmpi ne, %st__rpathstart_home, %z32 : i32
  cf.cond_br %room__rpathstart_home, ^ret3, ^rpathstart_home_ok
^rpathstart_home_ok:
  %tok__rpathstart_home_ok = arith.constant 7 : i64
  func.call @lx_wr(%s, %c8, %tok__rpathstart_home_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %one) : (!llvm.ptr, i64, i64) -> ()
  %three__rpathstart_home_ok = arith.constant 3 : i64
  %sh__rpathstart_home_ok = arith.shli %three__rpathstart_home_ok, %c32 : i64
  %spv__rpathstart_home_ok = arith.ori %sh__rpathstart_home_ok, %one : i64
  func.call @lx_wr(%s, %c12, %spv__rpathstart_home_ok) : (!llvm.ptr, i64, i64) -> ()
  %p2__rpathstart_home_ok = arith.addi %i, %two : i64
  func.call @lx_wr(%s, %c2i, %p2__rpathstart_home_ok) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^rpathstart_seg:
  %l__rpathstart_seg = func.call @lx_pathseg(%src, %n, %i) : (!llvm.ptr, i64, i64) -> i64
  %five__rpathstart_seg = arith.constant 5 : i64
  %st__rpathstart_seg = func.call @lx_push(%s, %five__rpathstart_seg) : (!llvm.ptr, i64) -> i32
  %room__rpathstart_seg = arith.cmpi ne, %st__rpathstart_seg, %z32 : i32
  cf.cond_br %room__rpathstart_seg, ^ret3, ^rpathstart_seg_ok
^rpathstart_seg_ok:
  %tok__rpathstart_seg_ok = arith.constant 6 : i64
  func.call @lx_wr(%s, %c8, %tok__rpathstart_seg_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  %il__rpathstart_seg_ok = arith.addi %i, %l__rpathstart_seg : i64
  %sh__rpathstart_seg_ok = arith.shli %i, %c32 : i64
  %spv__rpathstart_seg_ok = arith.ori %sh__rpathstart_seg_ok, %il__rpathstart_seg_ok : i64
  func.call @lx_wr(%s, %c12, %spv__rpathstart_seg_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %il__rpathstart_seg_ok) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^rpathchk:
  %r39__rpathchk = arith.constant 39 : i64
  %ispath__rpathchk = arith.cmpi eq, %rule__general, %r39__rpathchk : i64
  %r40__rpathchk = arith.constant 40 : i64
  %ishpath__rpathchk = arith.cmpi eq, %rule__general, %r40__rpathchk : i64
  %ispathany__rpathchk = arith.ori %ispath__rpathchk, %ishpath__rpathchk : i1
  cf.cond_br %ispathany__rpathchk, ^rpath, ^rspathchk
^rpath:
  %il1__rpath = arith.subi %ie__general, %one : i64
  %cl__rpath = func.call @lx_at(%src, %n, %il1__rpath) : (!llvm.ptr, i64, i64) -> i8
  %sl__rpath = arith.constant 47 : i8
  %issl__rpath = arith.cmpi eq, %cl__rpath, %sl__rpath : i8
  %five__rpath = arith.constant 5 : i64
  %four__rpath = arith.constant 4 : i64
  %state__rpath = arith.select %issl__rpath, %five__rpath, %four__rpath : i64
  %st__rpath = func.call @lx_push(%s, %state__rpath) : (!llvm.ptr, i64) -> i32
  %room__rpath = arith.cmpi ne, %st__rpath, %z32 : i32
  cf.cond_br %room__rpath, ^ret3, ^rpath_ok
^rpath_ok:
  %six__rpath_ok = arith.constant 6 : i64
  %seven__rpath_ok = arith.constant 7 : i64
  %tok__rpath_ok = arith.select %ispath__rpathchk, %six__rpath_ok, %seven__rpath_ok : i64
  func.call @lx_wr(%s, %c8, %tok__rpath_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  %sh__rpath_ok = arith.shli %i, %c32 : i64
  %spv__rpath_ok = arith.ori %sh__rpath_ok, %ie__general : i64
  func.call @lx_wr(%s, %c12, %spv__rpath_ok) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^rspathchk:
  %r41__rspathchk = arith.constant 41 : i64
  %isspath__rspathchk = arith.cmpi eq, %rule__general, %r41__rspathchk : i64
  cf.cond_br %isspath__rspathchk, ^rspath, ^rurichk
^rspath:
  %tok__rspath = arith.constant 8 : i64
  func.call @lx_wr(%s, %c8, %tok__rspath) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  %sh__rspath = arith.shli %i, %c32 : i64
  %spv__rspath = arith.ori %sh__rspath, %ie__general : i64
  func.call @lx_wr(%s, %c12, %spv__rspath) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^rurichk:
  %r42__rurichk = arith.constant 42 : i64
  %isuri__rurichk = arith.cmpi eq, %rule__general, %r42__rurichk : i64
  cf.cond_br %isuri__rurichk, ^ruri, ^rcommentchk
^ruri:
  %tok__ruri = arith.constant 9 : i64
  func.call @lx_wr(%s, %c8, %tok__ruri) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  %sh__ruri = arith.shli %i, %c32 : i64
  %spv__ruri = arith.ori %sh__ruri, %ie__general : i64
  func.call @lx_wr(%s, %c12, %spv__ruri) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^rcommentchk:
  %r43__rcommentchk = arith.constant 43 : i64
  %iscomment__rcommentchk = arith.cmpi eq, %rule__general, %r43__rcommentchk : i64
  cf.cond_br %iscomment__rcommentchk, ^rcomment, ^rchar
^rcomment:
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %cont32 : i32
^rchar:
  %tok__rchar = arith.constant 36 : i64
  func.call @lx_wr(%s, %c8, %tok__rchar) : (!llvm.ptr, i64, i64) -> ()
  %ch__rchar = arith.extui %c : i8 to i64
  func.call @lx_wr(%s, %c9, %ch__rchar) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c2i, %ie__general) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
}

// ---- next(): the state loop producing one token (Lexer::next / nextToken) ----
func.func @nixfe_lex_next(%s: !llvm.ptr) -> i32 {
  %c0i = arith.constant 0 : i64
  %c1i = arith.constant 1 : i64
  %c2i = arith.constant 2 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %c12 = arith.constant 12 : i64
  %c16 = arith.constant 16 : i64
  %c17 = arith.constant 17 : i64
  %c20 = arith.constant 20 : i64
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %two = arith.constant 2 : i64
  %three = arith.constant 3 : i64
  %four = arith.constant 4 : i64
  %five = arith.constant 5 : i64
  %z32 = arith.constant 0 : i32
  %o32 = arith.constant 1 : i32
  %e32 = arith.constant 2 : i32
  %cont32 = arith.constant 4 : i32
  %hash = arith.constant 35 : i8
  %src = func.call @lx_rp(%s, %c0i) : (!llvm.ptr, i64) -> !llvm.ptr
  %n = func.call @lx_rd(%s, %c1i) : (!llvm.ptr, i64) -> i64
  %tws = llvm.mlir.addressof @lx_ws : !llvm.ptr
  cf.br ^loop
^loop:
  %p__loop = func.call @lx_rd(%s, %c2i) : (!llvm.ptr, i64) -> i64
  %eof__loop = arith.cmpi uge, %p__loop, %n : i64
  cf.cond_br %eof__loop, ^eof_top, ^getst
^eof_top:
  %top__eof_top = func.call @lx_top(%s) : (!llvm.ptr) -> i64
  %isinpath__eof_top = arith.cmpi eq, %top__eof_top, %four : i64
  cf.cond_br %isinpath__eof_top, ^eof_pathend, ^eof_slash
^eof_pathend:
  func.call @lx_pop(%s) : (!llvm.ptr) -> ()
  %tok__eof_pathend = arith.constant 10 : i64
  func.call @lx_wr(%s, %c8, %tok__eof_pathend) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c11, %p__loop) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_setpos(%s, %p__loop) : (!llvm.ptr, i64) -> ()
  func.call @lx_wr(%s, %c9, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c10, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c12, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c20, %z) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %z32 : i32
^eof_slash:
  %isslash__eof_slash = arith.cmpi eq, %top__eof_top, %five : i64
  cf.cond_br %isslash__eof_slash, ^eof_trailerr, ^eof_ret
^eof_trailerr:
  func.call @lx_wr(%s, %c16, %one) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_wr(%s, %c17, %p__loop) : (!llvm.ptr, i64, i64) -> ()
  llvm.return %e32 : i32
^eof_ret:
  llvm.return %o32 : i32
^getst:
  %st__getst = func.call @lx_top(%s) : (!llvm.ptr) -> i64
  %isinit__getst = arith.cmpi eq, %st__getst, %z : i64
  %isdef__getst = arith.cmpi eq, %st__getst, %one : i64
  %skip__getst = arith.ori %isinit__getst, %isdef__getst : i1
  cf.cond_br %skip__getst, ^ws, ^dispatch
^ws:
  cf.br ^wsloop(%p__loop : i64)
^wsloop(%q__wsloop: i64):
  %q1__wsloop = func.call @lx_run(%src, %n, %q__wsloop, %tws) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %c__wsloop = func.call @lx_at(%src, %n, %q1__wsloop) : (!llvm.ptr, i64, i64) -> i8
  %ish__wsloop = arith.cmpi eq, %c__wsloop, %hash : i8
  cf.cond_br %ish__wsloop, ^wscomment, ^wsdone
^wscomment:
  %q2__wscomment = arith.addi %q1__wsloop, %one : i64
  %q3__wscomment = func.call @lx_skipline(%src, %n, %q2__wscomment) : (!llvm.ptr, i64, i64) -> i64
  cf.br ^wsloop(%q3__wscomment : i64)
^wsdone:
  func.call @lx_wr(%s, %c2i, %q1__wsloop) : (!llvm.ptr, i64, i64) -> ()
  %eof2__wsdone = arith.cmpi uge, %q1__wsloop, %n : i64
  cf.cond_br %eof2__wsdone, ^loop, ^dispatch
^dispatch:
  %p2__dispatch = func.call @lx_rd(%s, %c2i) : (!llvm.ptr, i64) -> i64
  func.call @lx_wr(%s, %c11, %p2__dispatch) : (!llvm.ptr, i64, i64) -> ()
  func.call @lx_setpos(%s, %p2__dispatch) : (!llvm.ptr, i64) -> ()
  %st2__dispatch = func.call @lx_top(%s) : (!llvm.ptr) -> i64
  %isstr__dispatch = arith.cmpi eq, %st2__dispatch, %two : i64
  cf.cond_br %isstr__dispatch, ^do_str, ^indchk
^indchk:
  %isind__indchk = arith.cmpi eq, %st2__dispatch, %three : i64
  cf.cond_br %isind__indchk, ^do_ind, ^pathchk
^pathchk:
  %isip__pathchk = arith.cmpi eq, %st2__dispatch, %four : i64
  %isips__pathchk = arith.cmpi eq, %st2__dispatch, %five : i64
  %ispath__pathchk = arith.ori %isip__pathchk, %isips__pathchk : i1
  cf.cond_br %ispath__pathchk, ^do_path, ^do_def
^do_str:
  %r__do_str = func.call @lx_string(%s) : (!llvm.ptr) -> i32
  cf.br ^handle(%r__do_str : i32)
^do_ind:
  %r__do_ind = func.call @lx_ind(%s) : (!llvm.ptr) -> i32
  cf.br ^handle(%r__do_ind : i32)
^do_path:
  %r__do_path = func.call @lx_inpath(%s) : (!llvm.ptr) -> i32
  cf.br ^handle(%r__do_path : i32)
^do_def:
  %r__do_def = func.call @lx_default(%s) : (!llvm.ptr) -> i32
  cf.br ^handle(%r__do_def : i32)
^handle(%r__handle: i32):
  %iscont__handle = arith.cmpi eq, %r__handle, %cont32 : i32
  cf.cond_br %iscont__handle, ^loop, ^ret_r
^ret_r:
  llvm.return %r__handle : i32
}