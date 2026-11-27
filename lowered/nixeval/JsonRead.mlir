// builtins.fromJSON's reader (lib/Eval/Formats.cpp parseJSON; the C++ port of TrikeShed's Confix it replaces was
// include/Composite/Confix.h), in three parts:
//
//   confix_scan_checked(rec, rows) -> fault   the body of the confix dialect's confix.checked (Confix.td): the text
//     scanned once into the index's rows, in the order the elements open, checked as the reader of builtins.fromJSON
//     checks it.  The rows are a lane the caller made (!trikeshed.lane: a MutableSeries in LaneTrie's shape), filled by
//     trikeshed.append: a row is (open, close, tag, up), `up` the row of the container it is in (-1 for the root's).
//     So the open containers are no stack at all, the machine's or the record's: the container on top is a row, the
//     one under it that row's `up`, and a document nested a million deep needs nothing a flat one does not.  A
//     container's `close` is 0 until its closer is read: trikeshed.anchor mints it there.  The faults are nlohmann's,
//     at the offsets that reader had reached; Unsigned (an integer from 2^63 to 2^64 - 1) and Nul (a string with
//     \u0000) are a number and a string a Nix value cannot be.  A number without a fraction or an exponent that fits
//     64 bits is a Long, any other a Double.  The state machine is cf blocks (Value, Key, After), lifted to scf at
//     build time.
//
//   nixev_json_read(rec, st, root) -> fault   the lane made here and filled by confix.checked; then (when the text is
//     one) `up` drained into one series for trikeshed.adjacency, which gives a row's children (each row an edge from
//     the row it is in: the counting sort gives every row its (first, count) into the children, in the order of the
//     text); open, close and tag are read where the fill left them.  Then the values of the index: a Value
//     for each row, a container's filled from the Values of its children, which are made before they are visited
//     because a child's row comes after its parent's.  An object's members are sorted by their keys' bytes
//     (trikeshed.sorted, stable: of equal keys the last in the text is the last in the order, and it is the one kept,
//     as the sorted map the reader before kept it).  Null, booleans, integers and floats are written into the Value
//     here (VType Int 5, Float 6, Bool 7, Null 8: type u8 @0, payload @8); the evaluator's arena stays C++, behind
//     callbacks: nixev_json_value (allocValue), nixev_json_string (mkString), nixev_json_attrs (the BindingsBuilder of
//     the rows given in key order), EvalState::mkList.  strtod reads a Double, as the reader before read it.
//
//   nixev_json_decode(src, from, to, into, shown) -> written   the bytes of the string whose quotes are at from and to,
//     its escapes read: \uXXXX as UTF-8, a high surrogate and the escape after it as one code point (computed as the
//     reader before computed it, whatever the second half is), a lone half as its three bytes.  With shown, a NUL is
//     written as U+2400 (the Nul fault's message).  nixev_json_what(fault, &len) is a syntax fault's words.
//
// The record (4 words, the bridge's; Confix.td): src, n, at, end.  The index is not the bridge's: its rows are the
// lane of whoever calls confix.checked, which grows a page at a time and never asks.  The faults (also Confix.td):
// 1 EndOfInput, 2 InvalidLiteral,
// 3 ExpectedKey, 4 ExpectedColon, 5 ExpectedBrace, 6 ExpectedBracket, 7 Trailing, 8 MissingQuote, 9 ControlChar,
// 10 InvalidString, 11 Hex4, 12 Surrogate, 13 Backslash, 14 Unsigned, 15 Nul; `at` the offset (for Unsigned and Nul
// where the number or the string opens, and `end` one past it; `end` nonzero on entry is the store's reading of __json,
// StructuredAttrsOps.mlir's, where those two are a Long and a String).  The tags: 0 Nothing, 1 Boolean, 2 Long, 3 Double,
// 4 String, 5 Object, 6 Array.
!s8 = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!m8 = memref<?xi8, strided<[1], offset: ?>>
// the index while it is filled: a row is (open, close, tag, up); one column of it; and a row's children, drained
!rows = !trikeshed.lane<i32, i32, i8, i32>
!l32 = !trikeshed.lane<i32>
!l8 = !trikeshed.lane<i8>
!tp = !trikeshed.twinpacked<i32>
!kids = !trikeshed.series<!tp>

llvm.mlir.global internal constant @js_what_blob("unexpected end of input; expected '[', '{', or a literalinvalid literalinvalid literal; expected string literalsyntax error; expected ':'syntax error; expected '}'syntax error; expected ']'syntax error while parsing value - unexpected trailing content; expected end of inputinvalid string: missing closing quoteinvalid string: control character must be escapedinvalid stringinvalid string: '\5Cu' must be followed by 4 hex digitsinvalid string: surrogate U+D800..U+DBFF must be followed by U+DC00..U+DFFFinvalid string: forbidden character after backslash") {addr_space = 0 : i32}
llvm.mlir.global internal constant @js_what_off(dense<[0, 0, 56, 71, 111, 137, 163, 189, 274, 311, 360, 374, 427, 502]> : tensor<14xi32>) {addr_space = 0 : i32} : !llvm.array<14 x i32>
llvm.mlir.global internal constant @js_what_len(dense<[0, 56, 15, 40, 26, 26, 26, 85, 37, 49, 14, 53, 75, 51]> : tensor<14xi32>) {addr_space = 0 : i32} : !llvm.array<14 x i32>

func.func private @nixev_json_value(!llvm.ptr) -> !llvm.ptr
func.func private @nixev_json_string(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64)
func.func private @nixev_json_attrs(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64)
func.func private @_ZN5nixev9EvalState6mkListERNS_5ValueEm(!llvm.ptr, !llvm.ptr, i64)
func.func private @strtod(!llvm.ptr, !llvm.ptr) -> f64
func.func private @memchr(!llvm.ptr, i32, i64) -> !llvm.ptr

// ---- the record's words, and cells of its arrays (module-unique names: a private func is a global symbol) ----
func.func private @js_rd(%r: !llvm.ptr, %k: i64) -> i64 {
  %p = llvm.getelementptr %r[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %p : !llvm.ptr -> i64
  return %v : i64
}
func.func private @js_wr(%r: !llvm.ptr, %k: i64, %v: i64) {
  %p = llvm.getelementptr %r[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %p : i64, !llvm.ptr
  return
}
func.func private @js_rp(%r: !llvm.ptr, %k: i64) -> !llvm.ptr {
  %p = llvm.getelementptr %r[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %p : !llvm.ptr -> !llvm.ptr
  return %v : !llvm.ptr
}
func.func private @js_s64(%p: !llvm.ptr, %i: i64, %v: i64) {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %q : i64, !llvm.ptr
  return
}
func.func private @js_a8(%p: !llvm.ptr, %i: i64) -> i8 {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %v = llvm.load %q : !llvm.ptr -> i8
  return %v : i8
}
func.func private @js_s8(%p: !llvm.ptr, %i: i64, %v: i8) {
  %q = llvm.getelementptr %p[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %v, %q : i8, !llvm.ptr
  return
}

// the byte at i (0..255), -1 past the end
func.func private @js_at(%src: !llvm.ptr, %n: i64, %i: i64) -> i32 {
  %in = arith.cmpi ult, %i, %n : i64
  %c = scf.if %in -> (i32) {
    %b = func.call @js_a8(%src, %i) : (!llvm.ptr, i64) -> i8
    %w = arith.extui %b : i8 to i32
    scf.yield %w : i32
  } else {
    %m1 = arith.constant -1 : i32
    scf.yield %m1 : i32
  }
  return %c : i32
}
// past the white space from p: ' ', '\t', '\n', '\r'
func.func private @js_ws(%src: !llvm.ptr, %n: i64, %p: i64) -> i64 {
  %r = scf.while (%q = %p) : (i64) -> i64 {
    %c = func.call @js_at(%src, %n, %q) : (!llvm.ptr, i64, i64) -> i32
    %sp = arith.constant 32 : i32
    %ht = arith.constant 9 : i32
    %lf = arith.constant 10 : i32
    %cr = arith.constant 13 : i32
    %a = arith.cmpi eq, %c, %sp : i32
    %b = arith.cmpi eq, %c, %ht : i32
    %d = arith.cmpi eq, %c, %lf : i32
    %e = arith.cmpi eq, %c, %cr : i32
    %ab = arith.ori %a, %b : i1
    %de = arith.ori %d, %e : i1
    %w = arith.ori %ab, %de : i1
    scf.condition(%w) %q : i64
  } do {
  ^bb0(%q1: i64):
    %one = arith.constant 1 : i64
    %q2 = arith.addi %q1, %one : i64
    scf.yield %q2 : i64
  }
  return %r : i64
}
// past the decimal digits from p
func.func private @js_digits(%src: !llvm.ptr, %n: i64, %p: i64) -> i64 {
  %r = scf.while (%q = %p) : (i64) -> i64 {
    %c = func.call @js_at(%src, %n, %q) : (!llvm.ptr, i64, i64) -> i32
    %zero = arith.constant 48 : i32
    %nine = arith.constant 57 : i32
    %ge = arith.cmpi sge, %c, %zero : i32
    %le = arith.cmpi sle, %c, %nine : i32
    %d = arith.andi %ge, %le : i1
    scf.condition(%d) %q : i64
  } do {
  ^bb0(%q1: i64):
    %one = arith.constant 1 : i64
    %q2 = arith.addi %q1, %one : i64
    scf.yield %q2 : i64
  }
  return %r : i64
}

// four hex digits from p: whether they are, their value, and where the reading got to (on a fault, past the digits read)
func.func private @js_hex4(%src: !llvm.ptr, %n: i64, %p: i64) -> (i1, i32, i64) {
  %c1 = arith.constant 1 : i64
  %c4 = arith.constant 4 : i64
  %v0 = arith.constant 0 : i32
  %yes = arith.constant 1 : i1
  %no = arith.constant 0 : i1
  %p4 = arith.addi %p, %c4 : i64
  %room = arith.cmpi ule, %p4, %n : i64
  cf.cond_br %room, ^loop(%p, %v0 : i64, i32), ^ret(%no, %v0, %p : i1, i32, i64)
^loop(%q: i64, %v: i32):
  %done = arith.cmpi eq, %q, %p4 : i64
  cf.cond_br %done, ^ret(%yes, %v, %q : i1, i32, i64), ^body
^body:
  %c = func.call @js_at(%src, %n, %q) : (!llvm.ptr, i64, i64) -> i32
  %q1 = arith.addi %q, %c1 : i64
  %k48 = arith.constant 48 : i32
  %k57 = arith.constant 57 : i32
  %k97 = arith.constant 97 : i32
  %k102 = arith.constant 102 : i32
  %k65 = arith.constant 65 : i32
  %k70 = arith.constant 70 : i32
  %k87 = arith.constant 87 : i32
  %k55 = arith.constant 55 : i32
  %k4 = arith.constant 4 : i32
  %g1 = arith.cmpi sge, %c, %k48 : i32
  %l1 = arith.cmpi sle, %c, %k57 : i32
  %dig = arith.andi %g1, %l1 : i1
  %g2 = arith.cmpi sge, %c, %k97 : i32
  %l2 = arith.cmpi sle, %c, %k102 : i32
  %low = arith.andi %g2, %l2 : i1
  %g3 = arith.cmpi sge, %c, %k65 : i32
  %l3 = arith.cmpi sle, %c, %k70 : i32
  %up = arith.andi %g3, %l3 : i1
  %dd = arith.subi %c, %k48 : i32
  %dl = arith.subi %c, %k87 : i32
  %du = arith.subi %c, %k55 : i32
  %d1 = arith.select %low, %dl, %du : i32
  %d = arith.select %dig, %dd, %d1 : i32
  %ok1 = arith.ori %dig, %low : i1
  %ok = arith.ori %ok1, %up : i1
  %vs = arith.shli %v, %k4 : i32
  %v2 = arith.ori %vs, %d : i32
  cf.cond_br %ok, ^loop(%q1, %v2 : i64, i32), ^ret(%no, %v0, %q1 : i1, i32, i64)
^ret(%rok: i1, %rv: i32, %rp: i64):
  return %rok, %rv, %rp : i1, i32, i64
}

// a string from the quote at `from`: (0, past its closing quote), or (fault, the offset the reading had got to)
func.func private @js_string(%rec: !llvm.ptr, %src: !llvm.ptr, %n: i64, %from: i64) -> (i32, i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %kat = arith.constant 2 : i64
  %kend = arith.constant 3 : i64
  %ok = arith.constant 0 : i32
  %kq = arith.constant 34 : i32
  %kbs = arith.constant 92 : i32
  %ksp = arith.constant 32 : i32
  %f8 = arith.constant 8 : i32
  %f9 = arith.constant 9 : i32
  %f10 = arith.constant 10 : i32
  %f11 = arith.constant 11 : i32
  %f12 = arith.constant 12 : i32
  %f13 = arith.constant 13 : i32
  %f15 = arith.constant 15 : i32
  %p0 = arith.addi %from, %c1 : i64
  cf.br ^run(%p0, %c0 : i64, i64)
^run(%p: i64, %nul: i64):
  %c = func.call @js_at(%src, %n, %p) : (!llvm.ptr, i64, i64) -> i32
  %ge = arith.cmpi sge, %c, %ksp : i32
  %nq = arith.cmpi ne, %c, %kq : i32
  %nb = arith.cmpi ne, %c, %kbs : i32
  %pl1 = arith.andi %ge, %nq : i1
  %plain = arith.andi %pl1, %nb : i1
  cf.cond_br %plain, ^step, ^stop
^step:
  %ps = arith.addi %p, %c1 : i64
  cf.br ^run(%ps, %nul : i64, i64)
^stop:
  %end = arith.cmpi uge, %p, %n : i64
  cf.cond_br %end, ^fail(%f8, %p : i32, i64), ^s1
^s1:
  %p1 = arith.addi %p, %c1 : i64
  %isq = arith.cmpi eq, %c, %kq : i32
  cf.cond_br %isq, ^closed(%p1, %nul : i64, i64), ^s2
^s2:
  %ctl = arith.cmpi slt, %c, %ksp : i32
  cf.cond_br %ctl, ^fail(%f9, %p1 : i32, i64), ^s3
^s3:
  %e1 = arith.cmpi uge, %p1, %n : i64
  cf.cond_br %e1, ^fail(%f10, %p1 : i32, i64), ^s4
^s4:
  %e = func.call @js_at(%src, %n, %p1) : (!llvm.ptr, i64, i64) -> i32
  %p2 = arith.addi %p1, %c1 : i64
  %x34 = arith.constant 34 : i32
  %x92 = arith.constant 92 : i32
  %x47 = arith.constant 47 : i32
  %x98 = arith.constant 98 : i32
  %x102 = arith.constant 102 : i32
  %x110 = arith.constant 110 : i32
  %x114 = arith.constant 114 : i32
  %x116 = arith.constant 116 : i32
  %y1 = arith.cmpi eq, %e, %x34 : i32
  %y2 = arith.cmpi eq, %e, %x92 : i32
  %y3 = arith.cmpi eq, %e, %x47 : i32
  %y4 = arith.cmpi eq, %e, %x98 : i32
  %y5 = arith.cmpi eq, %e, %x102 : i32
  %y6 = arith.cmpi eq, %e, %x110 : i32
  %y7 = arith.cmpi eq, %e, %x114 : i32
  %y8 = arith.cmpi eq, %e, %x116 : i32
  %z1 = arith.ori %y1, %y2 : i1
  %z2 = arith.ori %y3, %y4 : i1
  %z3 = arith.ori %y5, %y6 : i1
  %z4 = arith.ori %y7, %y8 : i1
  %z5 = arith.ori %z1, %z2 : i1
  %z6 = arith.ori %z3, %z4 : i1
  %simple = arith.ori %z5, %z6 : i1
  cf.cond_br %simple, ^run(%p2, %nul : i64, i64), ^s5
^s5:
  %x117 = arith.constant 117 : i32
  %isu = arith.cmpi eq, %e, %x117 : i32
  cf.cond_br %isu, ^u, ^fail(%f13, %p2 : i32, i64)
^u:
  %hok, %hv, %hp = func.call @js_hex4(%src, %n, %p2) : (!llvm.ptr, i64, i64) -> (i1, i32, i64)
  cf.cond_br %hok, ^u1, ^fail(%f11, %hp : i32, i64)
^u1:
  %kd800 = arith.constant 55296 : i32
  %kdbff = arith.constant 56319 : i32
  %h1 = arith.cmpi uge, %hv, %kd800 : i32
  %h2 = arith.cmpi ule, %hv, %kdbff : i32
  %high = arith.andi %h1, %h2 : i1
  cf.cond_br %high, ^hi, ^lo
^lo:
  %z0 = arith.constant 0 : i32
  %isz = arith.cmpi eq, %hv, %z0 : i32
  %isz64 = arith.extui %isz : i1 to i64
  %nul2 = arith.ori %nul, %isz64 : i64
  cf.br ^run(%hp, %nul2 : i64, i64)
^hi:
  %hp2 = arith.addi %hp, %c2 : i64
  %room = arith.cmpi ule, %hp2, %n : i64
  %hp1 = arith.addi %hp, %c1 : i64
  %b0 = func.call @js_at(%src, %n, %hp) : (!llvm.ptr, i64, i64) -> i32
  %b1 = func.call @js_at(%src, %n, %hp1) : (!llvm.ptr, i64, i64) -> i32
  %w0 = arith.cmpi eq, %b0, %x92 : i32
  %w1 = arith.cmpi eq, %b1, %x117 : i32
  %w01 = arith.andi %w0, %w1 : i1
  %pair = arith.andi %w01, %room : i1
  cf.cond_br %pair, ^hi2, ^fail(%f12, %hp : i32, i64)
^hi2:
  %lok, %lv, %lp = func.call @js_hex4(%src, %n, %hp2) : (!llvm.ptr, i64, i64) -> (i1, i32, i64)
  cf.cond_br %lok, ^run(%lp, %nul : i64, i64), ^fail(%f11, %lp : i32, i64)
^closed(%cp: i64, %cnul: i64):
  %anynul = arith.cmpi ne, %cnul, %c0 : i64
  // `end` set on entry: the store's reading of __json, where a NUL is a byte of the string
  %storew = func.call @js_rd(%rec, %kend) : (!llvm.ptr, i64) -> i64
  %evalw = arith.cmpi eq, %storew, %c0 : i64
  %isnul = arith.andi %anynul, %evalw : i1
  cf.cond_br %isnul, ^nul, ^ret(%ok, %cp : i32, i64)
^nul:
  func.call @js_wr(%rec, %kat, %from) : (!llvm.ptr, i64, i64) -> ()
  func.call @js_wr(%rec, %kend, %cp) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^ret(%f15, %cp : i32, i64)
^fail(%ff: i32, %fat: i64):
  func.call @js_wr(%rec, %kat, %fat) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^ret(%ff, %fat : i32, i64)
^ret(%rf: i32, %rp: i64):
  return %rf, %rp : i32, i64
}

// a number from `from` (a '-' or a digit there): past it, and its tag, a Long (2), or a Double (3) when it has a
// fraction or an exponent or does not fit 64 bits; the fault Unsigned for an integer from 2^63 to 2^64 - 1.  Up to 18 digits cannot overflow;
// longer ones are read as strtoll (negative) and strtoull read them: the magnitude against 2^63 or 2^64 - 1.
func.func private @js_number(%rec: !llvm.ptr, %src: !llvm.ptr, %n: i64, %from: i64) -> (i32, i64, i8) {
  %c1 = arith.constant 1 : i64
  %c10 = arith.constant 10 : i64
  %kat = arith.constant 2 : i64
  %kend = arith.constant 3 : i64
  %c18 = arith.constant 18 : i64
  %c48 = arith.constant 48 : i64
  %yes = arith.constant 1 : i1
  %no = arith.constant 0 : i1
  %kmin = arith.constant 45 : i32
  %kplus = arith.constant 43 : i32
  %kdot = arith.constant 46 : i32
  %ke = arith.constant 101 : i32
  %kE = arith.constant 69 : i32
  %c = func.call @js_at(%src, %n, %from) : (!llvm.ptr, i64, i64) -> i32
  %neg = arith.cmpi eq, %c, %kmin : i32
  %negi = arith.extui %neg : i1 to i64
  %d0 = arith.addi %from, %negi : i64
  %p1 = func.call @js_digits(%src, %n, %d0) : (!llvm.ptr, i64, i64) -> i64
  %digits = arith.subi %p1, %d0 : i64
  %c2 = func.call @js_at(%src, %n, %p1) : (!llvm.ptr, i64, i64) -> i32
  %isdot = arith.cmpi eq, %c2, %kdot : i32
  %p2, %f1 = scf.if %isdot -> (i64, i1) {
    %q = arith.addi %p1, %c1 : i64
    %q2 = func.call @js_digits(%src, %n, %q) : (!llvm.ptr, i64, i64) -> i64
    scf.yield %q2, %yes : i64, i1
  } else {
    scf.yield %p1, %no : i64, i1
  }
  %c3 = func.call @js_at(%src, %n, %p2) : (!llvm.ptr, i64, i64) -> i32
  %ise = arith.cmpi eq, %c3, %ke : i32
  %isE = arith.cmpi eq, %c3, %kE : i32
  %isexp = arith.ori %ise, %isE : i1
  %p3, %frac = scf.if %isexp -> (i64, i1) {
    %q = arith.addi %p2, %c1 : i64
    %c4 = func.call @js_at(%src, %n, %q) : (!llvm.ptr, i64, i64) -> i32
    %sp = arith.cmpi eq, %c4, %kplus : i32
    %sm = arith.cmpi eq, %c4, %kmin : i32
    %sg = arith.ori %sp, %sm : i1
    %sgi = arith.extui %sg : i1 to i64
    %q2 = arith.addi %q, %sgi : i64
    %q3 = func.call @js_digits(%src, %n, %q2) : (!llvm.ptr, i64, i64) -> i64
    scf.yield %q3, %yes : i64, i1
  } else {
    scf.yield %p2, %f1 : i64, i1
  }
  %k0 = arith.constant 0 : i32
  %k1 = arith.constant 1 : i32
  %k2 = arith.constant 2 : i32
  %big = arith.cmpi ugt, %digits, %c18 : i64
  %whole = arith.xori %frac, %yes : i1
  %check = arith.andi %whole, %big : i1
  // kind: 0 a Long, 1 a Double, 2 Unsigned
  %kind = scf.if %check -> (i32) {
    %lneg = arith.constant -9223372036854775808 : i64
    %lpos = arith.constant -1 : i64
    %limit = arith.select %neg, %lneg, %lpos : i64
    %v0 = arith.constant 0 : i64
    %lo = arith.index_cast %d0 : i64 to index
    %hi = arith.index_cast %p1 : i64 to index
    %one = arith.constant 1 : index
    %acc:2 = scf.for %i = %lo to %hi step %one iter_args(%v = %v0, %over = %no) -> (i64, i1) {
      %i64 = arith.index_cast %i : index to i64
      %b = func.call @js_a8(%src, %i64) : (!llvm.ptr, i64) -> i8
      %bw = arith.extui %b : i8 to i64
      %d = arith.subi %bw, %c48 : i64
      %room = arith.subi %limit, %d : i64
      %cut = arith.divui %room, %c10 : i64
      %o = arith.cmpi ugt, %v, %cut : i64
      %over2 = arith.ori %over, %o : i1
      %v10 = arith.muli %v, %c10 : i64
      %v2 = arith.addi %v10, %d : i64
      scf.yield %v2, %over2 : i64, i1
    }
    %imax = arith.constant 9223372036854775807 : i64
    %above = arith.cmpi ugt, %acc#0, %imax : i64
    %pos = arith.xori %neg, %yes : i1
    %uns = arith.andi %pos, %above : i1
    %k = arith.select %uns, %k2, %k0 : i32
    %kk = arith.select %acc#1, %k1, %k : i32
    scf.yield %kk : i32
  } else {
    %k = arith.select %frac, %k1, %k0 : i32
    scf.yield %k : i32
  }
  %anyuns = arith.cmpi eq, %kind, %k2 : i32
  // `end` set on entry: the store's reading of __json, where such an integer is a Long row
  %storew = func.call @js_rd(%rec, %kend) : (!llvm.ptr, i64) -> i64
  %z64 = arith.constant 0 : i64
  %evalw = arith.cmpi eq, %storew, %z64 : i64
  %isuns = arith.andi %anyuns, %evalw : i1
  %f = scf.if %isuns -> (i32) {
    func.call @js_wr(%rec, %kat, %from) : (!llvm.ptr, i64, i64) -> ()
    func.call @js_wr(%rec, %kend, %p3) : (!llvm.ptr, i64, i64) -> ()
    %u = arith.constant 14 : i32
    scf.yield %u : i32
  } else {
    scf.yield %k0 : i32
  }
  %isd = arith.cmpi eq, %kind, %k1 : i32
  %t2 = arith.constant 2 : i8
  %t3 = arith.constant 3 : i8
  %t = arith.select %isd, %t3, %t2 : i8
  return %f, %p3, %t : i32, i64, i8
}

// which literal is at p: 1 true, 2 false, 3 null, 0 none
func.func private @js_lit(%src: !llvm.ptr, %n: i64, %p: i64) -> i32 {
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %p1 = arith.addi %p, %c1 : i64
  %p2 = arith.addi %p, %c2 : i64
  %p3 = arith.addi %p, %c3 : i64
  %p4 = arith.addi %p, %c4 : i64
  %b0 = func.call @js_at(%src, %n, %p) : (!llvm.ptr, i64, i64) -> i32
  %b1 = func.call @js_at(%src, %n, %p1) : (!llvm.ptr, i64, i64) -> i32
  %b2 = func.call @js_at(%src, %n, %p2) : (!llvm.ptr, i64, i64) -> i32
  %b3 = func.call @js_at(%src, %n, %p3) : (!llvm.ptr, i64, i64) -> i32
  %b4 = func.call @js_at(%src, %n, %p4) : (!llvm.ptr, i64, i64) -> i32
  %kt = arith.constant 116 : i32
  %kr = arith.constant 114 : i32
  %ku = arith.constant 117 : i32
  %ke = arith.constant 101 : i32
  %kf = arith.constant 102 : i32
  %ka = arith.constant 97 : i32
  %kl = arith.constant 108 : i32
  %ks = arith.constant 115 : i32
  %kn = arith.constant 110 : i32
  %t0 = arith.cmpi eq, %b0, %kt : i32
  %t1 = arith.cmpi eq, %b1, %kr : i32
  %t2 = arith.cmpi eq, %b2, %ku : i32
  %t3 = arith.cmpi eq, %b3, %ke : i32
  %ta = arith.andi %t0, %t1 : i1
  %tb = arith.andi %t2, %t3 : i1
  %istrue = arith.andi %ta, %tb : i1
  %f0 = arith.cmpi eq, %b0, %kf : i32
  %f1 = arith.cmpi eq, %b1, %ka : i32
  %f2 = arith.cmpi eq, %b2, %kl : i32
  %f3 = arith.cmpi eq, %b3, %ks : i32
  %f4 = arith.cmpi eq, %b4, %ke : i32
  %fa = arith.andi %f0, %f1 : i1
  %fb = arith.andi %f2, %f3 : i1
  %fc = arith.andi %fa, %fb : i1
  %isfalse = arith.andi %fc, %f4 : i1
  %n0 = arith.cmpi eq, %b0, %kn : i32
  %n1 = arith.cmpi eq, %b1, %ku : i32
  %n2 = arith.cmpi eq, %b2, %kl : i32
  %n3 = arith.cmpi eq, %b3, %kl : i32
  %na = arith.andi %n0, %n1 : i1
  %nb = arith.andi %n2, %n3 : i1
  %isnull = arith.andi %na, %nb : i1
  %z = arith.constant 0 : i32
  %one = arith.constant 1 : i32
  %two = arith.constant 2 : i32
  %three = arith.constant 3 : i32
  %r1 = arith.select %isnull, %three, %z : i32
  %r2 = arith.select %isfalse, %two, %r1 : i32
  %r3 = arith.select %istrue, %one, %r2 : i32
  return %r3 : i32
}

// confix.checked: the scan, the fill of the index.  The states are blocks: ^value (a value is expected), ^key (a key
// after `{` or `,`), ^after (an element ended: `,` or the closer of the container on top, or the end of the document).
// Each carries the row of the container on top, -1 outside any (a row is 32 bits unsigned: a text under 4 GiB has
// fewer rows than that, whatever it holds).  A row is appended when its element is read: a container's when it opens
// (its close 0: not minted yet), a scalar's when it ends.
func.func @confix_scan_checked(%rec: !llvm.ptr, %rows: !rows) -> i32 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %kat = arith.constant 2 : i64
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %z32 = arith.constant 0 : i32
  %none = arith.constant -1 : i32
  %ok = arith.constant 0 : i32
  %f1 = arith.constant 1 : i32
  %f2 = arith.constant 2 : i32
  %f3 = arith.constant 3 : i32
  %f4 = arith.constant 4 : i32
  %f5 = arith.constant 5 : i32
  %f6 = arith.constant 6 : i32
  %f7 = arith.constant 7 : i32
  %qlbrace = arith.constant 123 : i32
  %qrbrace = arith.constant 125 : i32
  %qlbrack = arith.constant 91 : i32
  %qrbrack = arith.constant 93 : i32
  %qquote = arith.constant 34 : i32
  %qcomma = arith.constant 44 : i32
  %qcolon = arith.constant 58 : i32
  %qminus = arith.constant 45 : i32
  %q0 = arith.constant 48 : i32
  %q9 = arith.constant 57 : i32
  %t0 = arith.constant 0 : i8
  %t1 = arith.constant 1 : i8
  %t4 = arith.constant 4 : i8
  %t5 = arith.constant 5 : i8
  %t6 = arith.constant 6 : i8
  // the columns the scan reads back while it fills: a container's close, its tag, and the row it is in
  %closes = trikeshed.take %rows[%i1] : !rows -> !l32
  %tags = trikeshed.take %rows[%i2] : !rows -> !l8
  %ups = trikeshed.take %rows[%i3] : !rows -> !l32
  %src = func.call @js_rp(%rec, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %n = func.call @js_rd(%rec, %c1) : (!llvm.ptr, i64) -> i64
  cf.br ^value(%c0, %none : i64, i32)
^value(%p: i64, %top: i32):
  %vq = func.call @js_ws(%src, %n, %p) : (!llvm.ptr, i64, i64) -> i64
  %vend = arith.cmpi uge, %vq, %n : i64
  cf.cond_br %vend, ^fail(%f1, %vq : i32, i64), ^vgo
^vgo:
  %vc = func.call @js_at(%src, %n, %vq) : (!llvm.ptr, i64, i64) -> i32
  %vob = arith.cmpi eq, %vc, %qlbrace : i32
  %vab = arith.cmpi eq, %vc, %qlbrack : i32
  %vopen = arith.ori %vob, %vab : i1
  cf.cond_br %vopen, ^open, ^vstr
^open:
  // a container opens: its row, and it is the one on top
  %otag = arith.select %vob, %t5, %t6 : i8
  %oat = arith.trunci %vq : i64 to i32
  %orow = trikeshed.append %rows, %oat, %z32, %otag, %top : !rows, i32, i32, i8, i32 -> index
  %otop = arith.index_cast %orow : index to i32
  %oq1 = arith.addi %vq, %c1 : i64
  %oq2 = func.call @js_ws(%src, %n, %oq1) : (!llvm.ptr, i64, i64) -> i64
  %oc = func.call @js_at(%src, %n, %oq2) : (!llvm.ptr, i64, i64) -> i32
  %ocl = arith.select %vob, %qrbrace, %qrbrack : i32
  %oempty = arith.cmpi eq, %oc, %ocl : i32
  cf.cond_br %oempty, ^shut(%oq2, %otop : i64, i32), ^onot
^onot:
  cf.cond_br %vob, ^key(%oq2, %otop : i64, i32), ^value(%oq2, %otop : i64, i32)
^vstr:
  %visq = arith.cmpi eq, %vc, %qquote : i32
  cf.cond_br %visq, ^str, ^vlit
^str:
  %sf, %sp = func.call @js_string(%rec, %src, %n, %vq) : (!llvm.ptr, !llvm.ptr, i64, i64) -> (i32, i64)
  %sbad = arith.cmpi ne, %sf, %ok : i32
  cf.cond_br %sbad, ^ret(%sf : i32), ^row(%t4, %vq, %sp, %top : i8, i64, i64, i32)
^vlit:
  %lit = func.call @js_lit(%src, %n, %vq) : (!llvm.ptr, i64, i64) -> i32
  %islit = arith.cmpi ne, %lit, %ok : i32
  cf.cond_br %islit, ^lit, ^vnum
^lit:
  %l4 = arith.constant 4 : i64
  %l5 = arith.constant 5 : i64
  %lk2 = arith.constant 2 : i32
  %lk3 = arith.constant 3 : i32
  %lfalse = arith.cmpi eq, %lit, %lk2 : i32
  %lnull = arith.cmpi eq, %lit, %lk3 : i32
  %llen = arith.select %lfalse, %l5, %l4 : i64
  %ltag = arith.select %lnull, %t0, %t1 : i8
  %lend = arith.addi %vq, %llen : i64
  cf.br ^row(%ltag, %vq, %lend, %top : i8, i64, i64, i32)
^vnum:
  %nmin = arith.cmpi eq, %vc, %qminus : i32
  %nge = arith.cmpi sge, %vc, %q0 : i32
  %nle = arith.cmpi sle, %vc, %q9 : i32
  %ndig = arith.andi %nge, %nle : i1
  %isnum = arith.ori %nmin, %ndig : i1
  cf.cond_br %isnum, ^num, ^fail(%f2, %vq : i32, i64)
^num:
  %nf, %np, %nt = func.call @js_number(%rec, %src, %n, %vq) : (!llvm.ptr, !llvm.ptr, i64, i64) -> (i32, i64, i8)
  %nbad = arith.cmpi ne, %nf, %ok : i32
  cf.cond_br %nbad, ^ret(%nf : i32), ^row(%nt, %vq, %np, %top : i8, i64, i64, i32)
^row(%rtag: i8, %rfrom: i64, %rend: i64, %rtop: i32):
  // a string, a number or a literal ended: its row, from its first byte to its last
  %rlast = arith.subi %rend, %c1 : i64
  %ropen = arith.trunci %rfrom : i64 to i32
  %rclose = arith.trunci %rlast : i64 to i32
  %rrow = trikeshed.append %rows, %ropen, %rclose, %rtag, %rtop : !rows, i32, i32, i8, i32 -> index
  cf.br ^after(%rend, %rtop : i64, i32)
^key(%kp: i64, %ktop: i32):
  %kq = func.call @js_ws(%src, %n, %kp) : (!llvm.ptr, i64, i64) -> i64
  %kc = func.call @js_at(%src, %n, %kq) : (!llvm.ptr, i64, i64) -> i32
  %kisq = arith.cmpi eq, %kc, %qquote : i32
  cf.cond_br %kisq, ^kstr, ^fail(%f3, %kq : i32, i64)
^kstr:
  %kf, %kp2 = func.call @js_string(%rec, %src, %n, %kq) : (!llvm.ptr, !llvm.ptr, i64, i64) -> (i32, i64)
  %kbad = arith.cmpi ne, %kf, %ok : i32
  cf.cond_br %kbad, ^ret(%kf : i32), ^kcolon
^kcolon:
  // the key's row, then the colon
  %klast = arith.subi %kp2, %c1 : i64
  %kopen = arith.trunci %kq : i64 to i32
  %kclose = arith.trunci %klast : i64 to i32
  %krow = trikeshed.append %rows, %kopen, %kclose, %t4, %ktop : !rows, i32, i32, i8, i32 -> index
  %kq3 = func.call @js_ws(%src, %n, %kp2) : (!llvm.ptr, i64, i64) -> i64
  %kc3 = func.call @js_at(%src, %n, %kq3) : (!llvm.ptr, i64, i64) -> i32
  %kiscol = arith.cmpi eq, %kc3, %qcolon : i32
  %kq4 = arith.addi %kq3, %c1 : i64
  cf.cond_br %kiscol, ^value(%kq4, %ktop : i64, i32), ^fail(%f4, %kq3 : i32, i64)
^after(%ap: i64, %atop: i32):
  %aempty = arith.cmpi eq, %atop, %none : i32
  cf.cond_br %aempty, ^done(%ap : i64), ^amore
^amore:
  %aq = func.call @js_ws(%src, %n, %ap) : (!llvm.ptr, i64, i64) -> i64
  %arow = arith.index_castui %atop : i32 to index
  %atag = trikeshed.at %tags[%arow] : !l8, index -> i8
  %aobj = arith.cmpi eq, %atag, %t5 : i8
  %ac = func.call @js_at(%src, %n, %aq) : (!llvm.ptr, i64, i64) -> i32
  %acomma = arith.cmpi eq, %ac, %qcomma : i32
  %aq1 = arith.addi %aq, %c1 : i64
  cf.cond_br %acomma, ^anext, ^aclose
^anext:
  cf.cond_br %aobj, ^key(%aq1, %atop : i64, i32), ^value(%aq1, %atop : i64, i32)
^aclose:
  %acl = arith.select %aobj, %qrbrace, %qrbrack : i32
  %ais = arith.cmpi eq, %ac, %acl : i32
  %af = arith.select %aobj, %f5, %f6 : i32
  cf.cond_br %ais, ^shut(%aq, %atop : i64, i32), ^fail(%af, %aq : i32, i64)
^shut(%sat: i64, %stop: i32):
  // the container on top closes at sat: its close is minted, and the container it is in is on top again
  %srow = arith.index_castui %stop : i32 to index
  %sclose = arith.trunci %sat : i64 to i32
  %sminted = trikeshed.anchor %closes[%srow] : !l32 -> i32 {
    trikeshed.yield %sclose : i32
  }
  %sup = trikeshed.at %ups[%srow] : !l32, index -> i32
  %sq1 = arith.addi %sat, %c1 : i64
  cf.br ^after(%sq1, %sup : i64, i32)
^done(%dp: i64):
  %dq = func.call @js_ws(%src, %n, %dp) : (!llvm.ptr, i64, i64) -> i64
  %dend = arith.cmpi eq, %dq, %n : i64
  cf.cond_br %dend, ^ret(%ok : i32), ^fail(%f7, %dq : i32, i64)
^fail(%ff: i32, %fat: i64):
  func.call @js_wr(%rec, %kat, %fat) : (!llvm.ptr, i64, i64) -> ()
  cf.br ^ret(%ff : i32)
^ret(%rf: i32):
  return %rf : i32
}

// ---- strings decoded ----

// four hex digits at p (the scan has checked them)
func.func private @js_hexv(%s: !llvm.ptr, %p: i64) -> i32 {
  %zero = arith.constant 0 : index
  %four = arith.constant 4 : index
  %one = arith.constant 1 : index
  %v0 = arith.constant 0 : i32
  %r = scf.for %i = %zero to %four step %one iter_args(%v = %v0) -> (i32) {
    %i64 = arith.index_cast %i : index to i64
    %at = arith.addi %p, %i64 : i64
    %b = func.call @js_a8(%s, %at) : (!llvm.ptr, i64) -> i8
    %c = arith.extui %b : i8 to i32
    %k57 = arith.constant 57 : i32
    %k97 = arith.constant 97 : i32
    %k48 = arith.constant 48 : i32
    %k87 = arith.constant 87 : i32
    %k55 = arith.constant 55 : i32
    %k4 = arith.constant 4 : i32
    %dig = arith.cmpi sle, %c, %k57 : i32
    %low = arith.cmpi sge, %c, %k97 : i32
    %dd = arith.subi %c, %k48 : i32
    %dl = arith.subi %c, %k87 : i32
    %du = arith.subi %c, %k55 : i32
    %d1 = arith.select %low, %dl, %du : i32
    %d = arith.select %dig, %dd, %d1 : i32
    %vs = arith.shli %v, %k4 : i32
    %v2 = arith.ori %vs, %d : i32
    scf.yield %v2 : i32
  }
  return %r : i32
}
// code point cp as UTF-8 at out[w] (a lone surrogate gets its three bytes; with shown, a NUL is U+2400): the next w
func.func private @js_utf8(%out: !llvm.ptr, %w: i64, %cp: i32, %shown: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %w1 = arith.addi %w, %c1 : i64
  %w2 = arith.addi %w, %c2 : i64
  %w3 = arith.addi %w, %c3 : i64
  %k80 = arith.constant 128 : i32
  %k800 = arith.constant 2048 : i32
  %k10000 = arith.constant 65536 : i32
  %k3f = arith.constant 63 : i32
  %kc0 = arith.constant 192 : i32
  %ke0 = arith.constant 224 : i32
  %kf0 = arith.constant 240 : i32
  %s6 = arith.constant 6 : i32
  %s12 = arith.constant 12 : i32
  %s18 = arith.constant 18 : i32
  %z = arith.constant 0 : i32
  %r6 = arith.shrui %cp, %s6 : i32
  %r12 = arith.shrui %cp, %s12 : i32
  %r18 = arith.shrui %cp, %s18 : i32
  %m0 = arith.andi %cp, %k3f : i32
  %m6 = arith.andi %r6, %k3f : i32
  %m12 = arith.andi %r12, %k3f : i32
  %t0 = arith.ori %m0, %k80 : i32
  %t6 = arith.ori %m6, %k80 : i32
  %t12 = arith.ori %m12, %k80 : i32
  %b0 = arith.trunci %t0 : i32 to i8
  %b6 = arith.trunci %t6 : i32 to i8
  %b12 = arith.trunci %t12 : i32 to i8
  %one = arith.cmpi ult, %cp, %k80 : i32
  %r = scf.if %one -> (i64) {
    %isnul = arith.cmpi eq, %cp, %z : i32
    %sh = arith.cmpi ne, %shown, %c0 : i64
    %sym = arith.andi %isnul, %sh : i1
    %rr = scf.if %sym -> (i64) {
      %e2 = arith.constant -30 : i8
      %x90 = arith.constant -112 : i8
      %x80 = arith.constant -128 : i8
      func.call @js_s8(%out, %w, %e2) : (!llvm.ptr, i64, i8) -> ()
      func.call @js_s8(%out, %w1, %x90) : (!llvm.ptr, i64, i8) -> ()
      func.call @js_s8(%out, %w2, %x80) : (!llvm.ptr, i64, i8) -> ()
      scf.yield %w3 : i64
    } else {
      %b = arith.trunci %cp : i32 to i8
      func.call @js_s8(%out, %w, %b) : (!llvm.ptr, i64, i8) -> ()
      scf.yield %w1 : i64
    }
    scf.yield %rr : i64
  } else {
    %two = arith.cmpi ult, %cp, %k800 : i32
    %rr = scf.if %two -> (i64) {
      %l = arith.ori %r6, %kc0 : i32
      %lb = arith.trunci %l : i32 to i8
      func.call @js_s8(%out, %w, %lb) : (!llvm.ptr, i64, i8) -> ()
      func.call @js_s8(%out, %w1, %b0) : (!llvm.ptr, i64, i8) -> ()
      scf.yield %w2 : i64
    } else {
      %three = arith.cmpi ult, %cp, %k10000 : i32
      %r3 = scf.if %three -> (i64) {
        %l = arith.ori %r12, %ke0 : i32
        %lb = arith.trunci %l : i32 to i8
        func.call @js_s8(%out, %w, %lb) : (!llvm.ptr, i64, i8) -> ()
        func.call @js_s8(%out, %w1, %b6) : (!llvm.ptr, i64, i8) -> ()
        func.call @js_s8(%out, %w2, %b0) : (!llvm.ptr, i64, i8) -> ()
        scf.yield %w3 : i64
      } else {
        %l = arith.ori %r18, %kf0 : i32
        %lb = arith.trunci %l : i32 to i8
        %w4 = arith.addi %w, %c4 : i64
        func.call @js_s8(%out, %w, %lb) : (!llvm.ptr, i64, i8) -> ()
        func.call @js_s8(%out, %w1, %b12) : (!llvm.ptr, i64, i8) -> ()
        func.call @js_s8(%out, %w2, %b6) : (!llvm.ptr, i64, i8) -> ()
        func.call @js_s8(%out, %w3, %b0) : (!llvm.ptr, i64, i8) -> ()
        scf.yield %w4 : i64
      }
      scf.yield %r3 : i64
    }
    scf.yield %rr : i64
  }
  return %r : i64
}
// the string whose quotes are at from and to, its escapes read, into out: how many bytes
func.func @nixev_json_decode(%s: !llvm.ptr, %from: i64, %to: i64, %out: !llvm.ptr, %shown: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %p0 = arith.addi %from, %c1 : i64
  %r:2 = scf.while (%p = %p0, %w = %c0) : (i64, i64) -> (i64, i64) {
    %go = arith.cmpi ult, %p, %to : i64
    scf.condition(%go) %p, %w : i64, i64
  } do {
  ^bb0(%pp: i64, %ww: i64):
    %kb = arith.constant 92 : i8
    %c = func.call @js_a8(%s, %pp) : (!llvm.ptr, i64) -> i8
    %isbs = arith.cmpi eq, %c, %kb : i8
    %next:2 = scf.if %isbs -> (i64, i64) {
      %c2 = arith.constant 2 : i64
      %c4 = arith.constant 4 : i64
      %pe = arith.addi %pp, %c1 : i64
      %e = func.call @js_a8(%s, %pe) : (!llvm.ptr, i64) -> i8
      %p2 = arith.addi %pp, %c2 : i64
      %ku = arith.constant 117 : i8
      %isu = arith.cmpi eq, %e, %ku : i8
      %u:2 = scf.if %isu -> (i64, i64) {
        %cp = func.call @js_hexv(%s, %p2) : (!llvm.ptr, i64) -> i32
        %p6 = arith.addi %p2, %c4 : i64
        %kd800 = arith.constant 55296 : i32
        %kdbff = arith.constant 56319 : i32
        %h1 = arith.cmpi uge, %cp, %kd800 : i32
        %h2 = arith.cmpi ule, %cp, %kdbff : i32
        %high = arith.andi %h1, %h2 : i1
        %pair:2 = scf.if %high -> (i32, i64) {
          %p8 = arith.addi %p6, %c2 : i64
          %lo = func.call @js_hexv(%s, %p8) : (!llvm.ptr, i64) -> i32
          %k10000 = arith.constant 65536 : i32
          %kdc00 = arith.constant 56320 : i32
          %k10 = arith.constant 10 : i32
          %hd = arith.subi %cp, %kd800 : i32
          %hs = arith.shli %hd, %k10 : i32
          %ld = arith.subi %lo, %kdc00 : i32
          %a1 = arith.addi %k10000, %hs : i32
          %full = arith.addi %a1, %ld : i32
          %p12 = arith.addi %p8, %c4 : i64
          scf.yield %full, %p12 : i32, i64
        } else {
          scf.yield %cp, %p6 : i32, i64
        }
        %w2 = func.call @js_utf8(%out, %ww, %pair#0, %shown) : (!llvm.ptr, i64, i32, i64) -> i64
        scf.yield %pair#1, %w2 : i64, i64
      } else {
        %kb8 = arith.constant 98 : i8
        %kf8 = arith.constant 102 : i8
        %kn8 = arith.constant 110 : i8
        %kr8 = arith.constant 114 : i8
        %kt8 = arith.constant 116 : i8
        %vb = arith.constant 8 : i8
        %vf = arith.constant 12 : i8
        %vn = arith.constant 10 : i8
        %vr = arith.constant 13 : i8
        %vt = arith.constant 9 : i8
        %ib = arith.cmpi eq, %e, %kb8 : i8
        %if = arith.cmpi eq, %e, %kf8 : i8
        %in = arith.cmpi eq, %e, %kn8 : i8
        %ir = arith.cmpi eq, %e, %kr8 : i8
        %it = arith.cmpi eq, %e, %kt8 : i8
        %x1 = arith.select %it, %vt, %e : i8
        %x2 = arith.select %ir, %vr, %x1 : i8
        %x3 = arith.select %in, %vn, %x2 : i8
        %x4 = arith.select %if, %vf, %x3 : i8
        %x5 = arith.select %ib, %vb, %x4 : i8
        func.call @js_s8(%out, %ww, %x5) : (!llvm.ptr, i64, i8) -> ()
        %w1 = arith.addi %ww, %c1 : i64
        scf.yield %p2, %w1 : i64, i64
      }
      scf.yield %u#0, %u#1 : i64, i64
    } else {
      func.call @js_s8(%out, %ww, %c) : (!llvm.ptr, i64, i8) -> ()
      %p1 = arith.addi %pp, %c1 : i64
      %w1 = arith.addi %ww, %c1 : i64
      scf.yield %p1, %w1 : i64, i64
    }
    scf.yield %next#0, %next#1 : i64, i64
  }
  return %r#1 : i64
}

// a syntax fault's words: their place in the blob, their length into *len
func.func @nixev_json_what(%f: i64, %len: !llvm.ptr) -> !llvm.ptr {
  %blob = llvm.mlir.addressof @js_what_blob : !llvm.ptr
  %offs = llvm.mlir.addressof @js_what_off : !llvm.ptr
  %lens = llvm.mlir.addressof @js_what_len : !llvm.ptr
  %op = llvm.getelementptr %offs[%f] : (!llvm.ptr, i64) -> !llvm.ptr, i32
  %o = llvm.load %op : !llvm.ptr -> i32
  %lp = llvm.getelementptr %lens[%f] : (!llvm.ptr, i64) -> !llvm.ptr, i32
  %l = llvm.load %lp : !llvm.ptr -> i32
  %l64 = arith.extui %l : i32 to i64
  llvm.store %l64, %len : i64, !llvm.ptr
  %o64 = arith.extui %o : i32 to i64
  %w = llvm.getelementptr %blob[%o64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  return %w : !llvm.ptr
}

// ---- the values of an index ----

// the address of a buffer's first cell
func.func private @js_addr8(%b: memref<?xi8>) -> !llvm.ptr {
  %a = memref.extract_aligned_pointer_as_index %b : memref<?xi8> -> index
  %w = arith.index_cast %a : index to i64
  %p = llvm.inttoptr %w : i64 to !llvm.ptr
  return %p : !llvm.ptr
}
func.func private @js_addr64(%b: memref<?xi64>) -> !llvm.ptr {
  %a = memref.extract_aligned_pointer_as_index %b : memref<?xi64> -> index
  %w = arith.index_cast %a : index to i64
  %p = llvm.inttoptr %w : i64 to !llvm.ptr
  return %p : !llvm.ptr
}

// a Double: the bytes from..to read by strtod, which wants the NUL after them
func.func private @js_mk_double(%src: !llvm.ptr, %v: !llvm.ptr, %from: i64, %to: i64) {
  %c1 = arith.constant 1 : i64
  %len = arith.subi %to, %from : i64
  %len1 = arith.addi %len, %c1 : i64
  %room = arith.addi %len1, %c1 : i64
  %ri = arith.index_cast %room : i64 to index
  %buf = memref.alloc(%ri) : memref<?xi8>
  %zero = arith.constant 0 : index
  %li = arith.index_cast %len1 : i64 to index
  %one = arith.constant 1 : index
  scf.for %i = %zero to %li step %one {
    %i64 = arith.index_cast %i : index to i64
    %at = arith.addi %from, %i64 : i64
    %b = func.call @js_a8(%src, %at) : (!llvm.ptr, i64) -> i8
    memref.store %b, %buf[%i] : memref<?xi8>
  }
  %z8 = arith.constant 0 : i8
  memref.store %z8, %buf[%li] : memref<?xi8>
  %p = func.call @js_addr8(%buf) : (memref<?xi8>) -> !llvm.ptr
  %null = llvm.mlir.zero : !llvm.ptr
  %d = func.call @strtod(%p, %null) : (!llvm.ptr, !llvm.ptr) -> f64
  %t6 = arith.constant 6 : i8
  llvm.store %t6, %v : i8, !llvm.ptr
  %pay = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %d, %pay : f64, !llvm.ptr
  return
}
// a String: a window of the source when nothing in it is escaped, else decoded into a scratch buffer
func.func private @js_mk_string(%src: !llvm.ptr, %st: !llvm.ptr, %v: !llvm.ptr, %from: i64, %to: i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %body = arith.addi %from, %c1 : i64
  %len = arith.subi %to, %body : i64
  %bp = llvm.getelementptr %src[%body] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %kbs = arith.constant 92 : i32
  %hit = func.call @memchr(%bp, %kbs, %len) : (!llvm.ptr, i32, i64) -> !llvm.ptr
  %hw = llvm.ptrtoint %hit : !llvm.ptr to i64
  %esc = arith.cmpi ne, %hw, %c0 : i64
  scf.if %esc {
    %li = arith.index_cast %len : i64 to index
    %buf = memref.alloc(%li) : memref<?xi8>
    %p = func.call @js_addr8(%buf) : (memref<?xi8>) -> !llvm.ptr
    %w = func.call @nixev_json_decode(%src, %from, %to, %p, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
    func.call @nixev_json_string(%st, %v, %p, %w) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> ()
  } else {
    func.call @nixev_json_string(%st, %v, %bp, %len) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> ()
  }
  return
}
// an Array: a fresh Value for each child (vals[child]), then the list of them
func.func private @js_mk_array(%st: !llvm.ptr, %v: !llvm.ptr, %vals: memref<?xi64>, %kid: !s32, %first: index, %count: index) {
  %cells = memref.alloc(%count) : memref<?xi64>
  %zero = arith.constant 0 : index
  %one = arith.constant 1 : index
  scf.for %k = %zero to %count step %one {
    %at = arith.addi %first, %k : index
    %row = trikeshed.at %kid[%at] : !s32, index -> i32
    %ri = arith.index_castui %row : i32 to index
    %cell = func.call @nixev_json_value(%st) : (!llvm.ptr) -> !llvm.ptr
    %cw = llvm.ptrtoint %cell : !llvm.ptr to i64
    memref.store %cw, %vals[%ri] : memref<?xi64>
    memref.store %cw, %cells[%k] : memref<?xi64>
  }
  %count64 = arith.index_cast %count : index to i64
  func.call @_ZN5nixev9EvalState6mkListERNS_5ValueEm(%st, %v, %count64) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %ep = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %elems = llvm.load %ep : !llvm.ptr -> !llvm.ptr
  scf.for %k = %zero to %count step %one {
    %k64 = arith.index_cast %k : index to i64
    %cw = memref.load %cells[%k] : memref<?xi64>
    func.call @js_s64(%elems, %k64, %cw) : (!llvm.ptr, i64, i64) -> ()
  }
  return
}
// an Object: each member's key decoded into one buffer and a fresh Value for its value, in the order they came; the
// members sorted by their keys' bytes (stable); of equal keys the last is kept; the rows handed to the attrs builder
func.func private @js_mk_object(%src: !llvm.ptr, %st: !llvm.ptr, %v: !llvm.ptr, %vals: memref<?xi64>, %opens: !l32,
                                %closes: !l32, %kid: !s32, %first: index, %count: index) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %zero = arith.constant 0 : index
  %one = arith.constant 1 : index
  %c2i = arith.constant 2 : index
  %mi = arith.divui %count, %c2i : index
  // room for the keys: the bytes between their quotes, which their values never outgrow
  %room = scf.for %k = %zero to %mi step %one iter_args(%acc = %c0) -> (i64) {
    %k2 = arith.muli %k, %c2i : index
    %at = arith.addi %first, %k2 : index
    %row = trikeshed.at %kid[%at] : !s32, index -> i32
    %from32 = trikeshed.at %opens[%row] : !l32, i32 -> i32
    %to32 = trikeshed.at %closes[%row] : !l32, i32 -> i32
    %from = arith.extui %from32 : i32 to i64
    %to = arith.extui %to32 : i32 to i64
    %d = arith.subi %to, %from : i64
    %d1 = arith.subi %d, %c1 : i64
    %acc2 = arith.addi %acc, %d1 : i64
    scf.yield %acc2 : i64
  }
  %roomi = arith.index_cast %room : i64 to index
  %keys = memref.alloc(%roomi) : memref<?xi8>
  %koff = memref.alloc(%mi) : memref<?xi64>
  %klen = memref.alloc(%mi) : memref<?xi64>
  %cells = memref.alloc(%mi) : memref<?xi64>
  %kbase = func.call @js_addr8(%keys) : (memref<?xi8>) -> !llvm.ptr
  %kbw = llvm.ptrtoint %kbase : !llvm.ptr to i64
  %used = scf.for %k = %zero to %mi step %one iter_args(%off = %c0) -> (i64) {
    %k2 = arith.muli %k, %c2i : index
    %at = arith.addi %first, %k2 : index
    %row = trikeshed.at %kid[%at] : !s32, index -> i32
    %from32 = trikeshed.at %opens[%row] : !l32, i32 -> i32
    %to32 = trikeshed.at %closes[%row] : !l32, i32 -> i32
    %from = arith.extui %from32 : i32 to i64
    %to = arith.extui %to32 : i32 to i64
    %into = llvm.getelementptr %kbase[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %w = func.call @nixev_json_decode(%src, %from, %to, %into, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
    memref.store %off, %koff[%k] : memref<?xi64>
    memref.store %w, %klen[%k] : memref<?xi64>
    %at1 = arith.addi %at, %one : index
    %vrow = trikeshed.at %kid[%at1] : !s32, index -> i32
    %vri = arith.index_castui %vrow : i32 to index
    %cell = func.call @nixev_json_value(%st) : (!llvm.ptr) -> !llvm.ptr
    %cw = llvm.ptrtoint %cell : !llvm.ptr to i64
    memref.store %cw, %vals[%vri] : memref<?xi64>
    memref.store %cw, %cells[%k] : memref<?xi64>
    %off2 = arith.addi %off, %w : i64
    scf.yield %off2 : i64
  }
  %kv = memref.cast %keys : memref<?xi8> to !m8
  %ks = builtin.unrealized_conversion_cast %kv : !m8 to !s8
  %idx = trikeshed.series %mi : !s64 {
  ^bb0(%j: index):
    %j64 = arith.index_cast %j : index to i64
    trikeshed.yield %j64 : i64
  }
  // in key order; sorted is stable (a tie keeps the order of the text)
  %order = trikeshed.sorted %idx : !s64 -> !s64 by {
  ^bb0(%a: i64, %b: i64):
    %ai = arith.index_cast %a : i64 to index
    %bi = arith.index_cast %b : i64 to index
    %ao = memref.load %koff[%ai] : memref<?xi64>
    %al = memref.load %klen[%ai] : memref<?xi64>
    %bo = memref.load %koff[%bi] : memref<?xi64>
    %bl = memref.load %klen[%bi] : memref<?xi64>
    %aoi = arith.index_cast %ao : i64 to index
    %ali = arith.index_cast %al : i64 to index
    %boi = arith.index_cast %bo : i64 to index
    %bli = arith.index_cast %bl : i64 to index
    %sa = trikeshed.slice %ks[%aoi, %ali] : !s8 -> !s8
    %sb = trikeshed.slice %ks[%boi, %bli] : !s8 -> !s8
    %c = trikeshed.compare %sa, %sb unsigned : !s8, !s8
    trikeshed.yield %c : i32
  }
  // the rows to bind: Chars {u32 count @0, ptr @8} and the value, of each key that the next does not repeat
  %m2 = arith.muli %mi, %c2i : index
  %chars = memref.alloc(%m2) : memref<?xi64>
  %vcells = memref.alloc(%mi) : memref<?xi64>
  %nrows = scf.for %k = %zero to %mi step %one iter_args(%j = %c0) -> (i64) {
    %o = trikeshed.at %order[%k] : !s64, index -> i64
    %k1 = arith.addi %k, %one : index
    %more = arith.cmpi ult, %k1, %mi : index
    %kn = arith.select %more, %k1, %k : index
    %o2 = trikeshed.at %order[%kn] : !s64, index -> i64
    %oi = arith.index_cast %o : i64 to index
    %o2i = arith.index_cast %o2 : i64 to index
    %ao = memref.load %koff[%oi] : memref<?xi64>
    %al = memref.load %klen[%oi] : memref<?xi64>
    %bo = memref.load %koff[%o2i] : memref<?xi64>
    %bl = memref.load %klen[%o2i] : memref<?xi64>
    %aoi = arith.index_cast %ao : i64 to index
    %ali = arith.index_cast %al : i64 to index
    %boi = arith.index_cast %bo : i64 to index
    %bli = arith.index_cast %bl : i64 to index
    %sa = trikeshed.slice %ks[%aoi, %ali] : !s8 -> !s8
    %sb = trikeshed.slice %ks[%boi, %bli] : !s8 -> !s8
    %c = trikeshed.compare %sa, %sb unsigned : !s8, !s8
    %z32 = arith.constant 0 : i32
    %same = arith.cmpi eq, %c, %z32 : i32
    %dup = arith.andi %more, %same : i1
    %j2 = scf.if %dup -> (i64) {
      scf.yield %j : i64
    } else {
      %ji = arith.index_cast %j : i64 to index
      %j2i = arith.muli %ji, %c2i : index
      %j2i1 = arith.addi %j2i, %one : index
      %kp = arith.addi %kbw, %ao : i64
      memref.store %al, %chars[%j2i] : memref<?xi64>
      memref.store %kp, %chars[%j2i1] : memref<?xi64>
      %cw = memref.load %cells[%oi] : memref<?xi64>
      memref.store %cw, %vcells[%ji] : memref<?xi64>
      %jn = arith.addi %j, %c1 : i64
      scf.yield %jn : i64
    }
    scf.yield %j2 : i64
  }
  %cp = func.call @js_addr64(%chars) : (memref<?xi64>) -> !llvm.ptr
  %vp = func.call @js_addr64(%vcells) : (memref<?xi64>) -> !llvm.ptr
  // the keys' buffer is read through the rows' pointers; it is freed at the end of this block, after the builder has
  // interned them
  func.call @nixev_json_attrs(%st, %v, %cp, %vp, %nrows) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> ()
  return
}

// the values of the index, made now from its rows where they lie, the first row's into root
func.func private @js_reify(%src: !llvm.ptr, %st: !llvm.ptr, %root: !llvm.ptr, %opens: !l32, %closes: !l32, %tags: !l8,
                            %kids: !kids, %kid: !s32) {
  %c0 = arith.constant 0 : i64
  %ri = trikeshed.size %tags : !l8
  %vals = memref.alloc(%ri) : memref<?xi64>
  %zero = arith.constant 0 : index
  %one = arith.constant 1 : index
  scf.for %i = %zero to %ri step %one {
    memref.store %c0, %vals[%i] : memref<?xi64>
  }
  %rw = llvm.ptrtoint %root : !llvm.ptr to i64
  memref.store %rw, %vals[%zero] : memref<?xi64>
  scf.for %i = %zero to %ri step %one {
    %vb = memref.load %vals[%i] : memref<?xi64>
    %made = arith.cmpi ne, %vb, %c0 : i64
    scf.if %made {
      %v = llvm.inttoptr %vb : i64 to !llvm.ptr
      %from32 = trikeshed.at %opens[%i] : !l32, index -> i32
      %to32 = trikeshed.at %closes[%i] : !l32, index -> i32
      %from = arith.extui %from32 : i32 to i64
      %to = arith.extui %to32 : i32 to i64
      %tag = trikeshed.at %tags[%i] : !l8, index -> i8
      %t1 = arith.constant 1 : i8
      %t2 = arith.constant 2 : i8
      %t3 = arith.constant 3 : i8
      %t4 = arith.constant 4 : i8
      %t5 = arith.constant 5 : i8
      %small = arith.cmpi ule, %tag, %t2 : i8
      %pay = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
      scf.if %small {
        // Nothing, Boolean, Long: written into the Value (mkNull, mkBool, mkInt)
        %isnull = arith.cmpi ult, %tag, %t1 : i8
        %isbool = arith.cmpi eq, %tag, %t1 : i8
        scf.if %isnull {
          %vt = arith.constant 8 : i8
          llvm.store %vt, %v : i8, !llvm.ptr
        } else {
          scf.if %isbool {
            %b = func.call @js_a8(%src, %from) : (!llvm.ptr, i64) -> i8
            %kt = arith.constant 116 : i8
            %bt = arith.cmpi eq, %b, %kt : i8
            %b8 = arith.extui %bt : i1 to i8
            %vt = arith.constant 7 : i8
            llvm.store %vt, %v : i8, !llvm.ptr
            llvm.store %b8, %pay : i8, !llvm.ptr
          } else {
            %x = func.call @js_long(%src, %from, %to) : (!llvm.ptr, i64, i64) -> i64
            %vt = arith.constant 5 : i8
            llvm.store %vt, %v : i8, !llvm.ptr
            llvm.store %x, %pay : i64, !llvm.ptr
          }
        }
      } else {
        %isdouble = arith.cmpi eq, %tag, %t3 : i8
        scf.if %isdouble {
          func.call @js_mk_double(%src, %v, %from, %to) : (!llvm.ptr, !llvm.ptr, i64, i64) -> ()
        } else {
          %isstring = arith.cmpi eq, %tag, %t4 : i8
          scf.if %isstring {
            func.call @js_mk_string(%src, %st, %v, %from, %to) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64) -> ()
          } else {
            // a container's children: its (first, count) into kid
            %kc = trikeshed.at %kids[%i] : !kids, index -> !tp
            %first32 = trikeshed.first %kc : !tp -> i32
            %count32 = trikeshed.second %kc : !tp -> i32
            %first = arith.index_castui %first32 : i32 to index
            %count = arith.index_castui %count32 : i32 to index
            %isobject = arith.cmpi eq, %tag, %t5 : i8
            scf.if %isobject {
              func.call @js_mk_object(%src, %st, %v, %vals, %opens, %closes, %kid, %first, %count)
                : (!llvm.ptr, !llvm.ptr, !llvm.ptr, memref<?xi64>, !l32, !l32, !s32, index, index) -> ()
            } else {
              func.call @js_mk_array(%st, %v, %vals, %kid, %first, %count) : (!llvm.ptr, !llvm.ptr, memref<?xi64>, !s32, index, index) -> ()
            }
          }
        }
      }
    }
  }
  return
}

// a Long's value: an optional '-' and digits (a '-' alone is 0, as the reader before made it); the scan has seen that
// it fits, so the digits summed in 64 bits and negated are exact (-2^63 too)
func.func private @js_long(%src: !llvm.ptr, %from: i64, %to: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c10 = arith.constant 10 : i64
  %c48 = arith.constant 48 : i64
  %km = arith.constant 45 : i8
  %b0 = func.call @js_a8(%src, %from) : (!llvm.ptr, i64) -> i8
  %neg = arith.cmpi eq, %b0, %km : i8
  %negi = arith.extui %neg : i1 to i64
  %d0 = arith.addi %from, %negi : i64
  %end = arith.addi %to, %c1 : i64
  %lo = arith.index_cast %d0 : i64 to index
  %hi = arith.index_cast %end : i64 to index
  %one = arith.constant 1 : index
  %v = scf.for %i = %lo to %hi step %one iter_args(%acc = %c0) -> (i64) {
    %i64 = arith.index_cast %i : index to i64
    %b = func.call @js_a8(%src, %i64) : (!llvm.ptr, i64) -> i8
    %bw = arith.extui %b : i8 to i64
    %d = arith.subi %bw, %c48 : i64
    %a10 = arith.muli %acc, %c10 : i64
    %a2 = arith.addi %a10, %d : i64
    scf.yield %a2 : i64
  }
  %mv = arith.subi %c0, %v : i64
  %r = arith.select %neg, %mv, %v : i64
  return %r : i64
}

// builtins.fromJSON's reader: the index's lane made here and filled by confix.checked (the fill); when the text is one,
// `up` drained for trikeshed.adjacency, which counts each row's children out of it, and the values made from the rows
// where they lie: a lane's rows are read in place (trikeshed.at), so the index is never held twice.  The fault, 0 for none.
func.func @nixev_json_read(%rec: !llvm.ptr, %st: !llvm.ptr, %root: !llvm.ptr) -> i32 {
  %rows = trikeshed.lane : !rows
  %f = confix.checked %rec, %rows : !llvm.ptr, !rows
  %z = arith.constant 0 : i32
  %ok = arith.cmpi eq, %f, %z : i32
  scf.if %ok {
    %c0 = arith.constant 0 : i64
    %i0 = arith.constant 0 : index
    %i1 = arith.constant 1 : index
    %i2 = arith.constant 2 : index
    %i3 = arith.constant 3 : index
    %src = func.call @js_rp(%rec, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
    %opens = trikeshed.take %rows[%i0] : !rows -> !l32
    %closes = trikeshed.take %rows[%i1] : !rows -> !l32
    %tags = trikeshed.take %rows[%i2] : !rows -> !l8
    %lups = trikeshed.take %rows[%i3] : !rows -> !l32
    %ups = trikeshed.drain %lups : !l32 -> !s32
    %n = trikeshed.size %ups : !s32
    %ids = trikeshed.series %n : !s32 {
    ^bb0(%i: index):
      %r = arith.index_cast %i : index to i32
      trikeshed.yield %r : i32
    }
    %kids, %kid = trikeshed.adjacency %ups, %ids over %n : !s32, !s32 -> !kids, !s32
    func.call @js_reify(%src, %st, %root, %opens, %closes, %tags, %kids, %kid)
      : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !l32, !l32, !l8, !kids, !s32) -> ()
  }
  return %f : i32
}
