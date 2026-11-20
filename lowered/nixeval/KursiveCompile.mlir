// Kursive's pattern compiler (include/Composite/Kursive.h detail::Compiler + compile, until 723dd15) hollowed into MLIR:
// the POSIX extended regular expression parser (alternation, concatenation, groups, the repetitions * + ? {m,n},
// bracket expressions with ranges, [: :] classes and [. .]/[= =] elements, anchors, escapes) building the pattern's
// tree in the caller's Node pool, then the code generator emitting the Step program (Char Alt Rep Jmp Save Bol Eol
// Match) and the byte Sets into the caller's arrays.  Nothing is allocated: the parser keeps its cursor and counters in
// one 16-word state array on the stack, and the recursion of the grammar (alternation -> sequence -> atom ->
// alternation) and of the generator (gen -> repeat -> gen) is func.call recursion inside this module, as the C++
// recursed.  The semantics are libstdc++'s std::regex::extended as Nix on Linux answers (see Kursive.h): the first
// error wins (1 Invalid, 2 Space), and every write the C++ made after it (a dangling Alt's jump target, the partial
// program) is made here too, so the arrays are byte for byte the old compiler's.
//
// Layouts (Kursive.h): Node 20B (kind u8@0, a/b/min/max u32@4/8/12/16) as 5 i32 words; Step 16B (op u8@0, x/y/z
// u32@4/8/12) as 4 i32 words; Set 4 u64.  The pattern is a trikeshed series<i8> read with trikeshed.at; a class name is
// matched with trikeshed.compare of the pattern's slice against a slice of the constant names text.
// State words: 0 p, 1 nNodes, 2 fail, 3 nSteps, 4 nSets, 5 groups, 6 loops, 7 end, 8 capNodes, 9 capSteps, 10 capSets.
// Helpers are module-unique (kc_*): func.func private still exports a global symbol.
!s = !trikeshed.series<i8>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!m32 = memref<?xi32, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!st = memref<16xi32>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// The C-locale classes [:name:] (regex_traits<char> under the C locale), generated from the old classMember: the names
// text, each name's offset and length, and each class's 4 set words.  `d`, `s` and `w` are libstdc++'s extra names.
memref.global "private" constant @kc_class_names : memref<64xi8> = dense<[97, 108, 110, 117, 109, 97, 108, 112, 104, 97, 100, 105, 103, 105, 116, 100, 115, 112, 97, 99, 101, 115, 117, 112, 112, 101, 114, 108, 111, 119, 101, 114, 120, 100, 105, 103, 105, 116, 98, 108, 97, 110, 107, 112, 117, 110, 99, 116, 112, 114, 105, 110, 116, 103, 114, 97, 112, 104, 99, 110, 116, 114, 108, 119]>
memref.global "private" constant @kc_class_off : memref<15xi32> = dense<[0, 5, 10, 15, 16, 21, 22, 27, 32, 38, 43, 48, 53, 58, 63]>
memref.global "private" constant @kc_class_len : memref<15xi32> = dense<[5, 5, 5, 1, 5, 1, 5, 5, 6, 5, 5, 5, 5, 5, 1]>
memref.global "private" constant @kc_class_sets : memref<60xi64> =
  dense<[287948901175001088, 576460743847706622, 0, 0, 0, 576460743847706622, 0, 0, 287948901175001088, 0, 0, 0, 287948901175001088, 0, 0, 0, 4294983168, 0, 0, 0, 4294983168, 0, 0, 0, 0, 134217726, 0, 0, 0, 576460743713488896, 0, 0, 287948901175001088, 541165879422, 0, 0, 4294967808, 0, 0, 0, -287948909764935680, 8646911293007069185, 0, 0, -4294967296, 9223372036854775807, 0, 0, -8589934592, 9223372036854775807, 0, 0, 4294967295, -9223372036854775808, 0, 0, 287948901175001088, 576460745995190270, 0, 0]>
memref.global "private" constant @kc_special : memref<256xi8> =
  dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]>

func.func private @kc_desc(%p: !llvm.ptr, %n: i64) -> !d {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %u = llvm.mlir.undef : !d
  %a = llvm.insertvalue %p, %u[0] : !d
  %b = llvm.insertvalue %p, %a[1] : !d
  %c = llvm.insertvalue %c0, %b[2] : !d
  %e = llvm.insertvalue %n, %c[3, 0] : !d
  %f = llvm.insertvalue %c1, %e[4, 0] : !d
  return %f : !d
}

// The byte at i (0..255), or -1 past the end: every `p < end && *p == c` of the C++ is one compare against it.
func.func private @kc_byte(%pat: !s, %i: i32, %n: i32) -> i32 {
  %m1 = arith.constant -1 : i32
  %in = arith.cmpi ult, %i, %n : i32
  %r = scf.if %in -> (i32) {
    %ix = arith.index_cast %i : i32 to index
    %ch = trikeshed.at %pat[%ix] : !s, index -> i8
    %w = arith.extui %ch : i8 to i32
    scf.yield %w : i32
  } else {
    scf.yield %m1 : i32
  }
  return %r : i32
}

// The byte `off` after the cursor.
func.func private @kc_peek(%pat: !s, %st: !st, %off: i32) -> i32 {
  %i0 = arith.constant 0 : index
  %i7 = arith.constant 7 : index
  %p = memref.load %st[%i0] : !st
  %e = memref.load %st[%i7] : !st
  %q = arith.addi %p, %off : i32
  %b = func.call @kc_byte(%pat, %q, %e) : (!s, i32, i32) -> i32
  return %b : i32
}

// p += k
func.func private @kc_adv(%st: !st, %k: i32) {
  %i0 = arith.constant 0 : index
  %p = memref.load %st[%i0] : !st
  %q = arith.addi %p, %k : i32
  memref.store %q, %st[%i0] : !st
  return
}

// bad(e): the first error wins.
func.func private @kc_bad(%st: !st, %e: i32) {
  %i2 = arith.constant 2 : index
  %z = arith.constant 0 : i32
  %f = memref.load %st[%i2] : !st
  %none = arith.cmpi eq, %f, %z : i32
  scf.if %none {
    memref.store %e, %st[%i2] : !st
  }
  return
}

func.func private @kc_failed(%st: !st) -> i1 {
  %i2 = arith.constant 2 : index
  %z = arith.constant 0 : i32
  %f = memref.load %st[%i2] : !st
  %r = arith.cmpi ne, %f, %z : i32
  return %r : i1
}

// node(n): the next pool slot, or Space and 0 when the pool is full.
func.func private @kc_node(%st: !st, %nodes: !m32, %k: i32, %a: i32, %b: i32, %mn: i32, %mx: i32) -> i32 {
  %i1 = arith.constant 1 : index
  %i8 = arith.constant 8 : index
  %z = arith.constant 0 : i32
  %one = arith.constant 1 : i32
  %two = arith.constant 2 : i32
  %five = arith.constant 5 : i32
  %n = memref.load %st[%i1] : !st
  %cap = memref.load %st[%i8] : !st
  %full = arith.cmpi eq, %n, %cap : i32
  %r = scf.if %full -> (i32) {
    func.call @kc_bad(%st, %two) : (!st, i32) -> ()
    scf.yield %z : i32
  } else {
    %w = arith.muli %n, %five : i32
    %x0 = arith.index_cast %w : i32 to index
    %x1 = arith.addi %x0, %i1 : index
    %x2 = arith.addi %x1, %i1 : index
    %x3 = arith.addi %x2, %i1 : index
    %x4 = arith.addi %x3, %i1 : index
    memref.store %k, %nodes[%x0] : !m32
    memref.store %a, %nodes[%x1] : !m32
    memref.store %b, %nodes[%x2] : !m32
    memref.store %mn, %nodes[%x3] : !m32
    memref.store %mx, %nodes[%x4] : !m32
    %n1 = arith.addi %n, %one : i32
    memref.store %n1, %st[%i1] : !st
    scf.yield %n : i32
  }
  return %r : i32
}

// set(s): the next set slot, or Space and 0 when the sets are full.
func.func private @kc_set4(%st: !st, %sets: !m64, %w0: i64, %w1: i64, %w2: i64, %w3: i64) -> i32 {
  %i1 = arith.constant 1 : index
  %i4 = arith.constant 4 : index
  %i10 = arith.constant 10 : index
  %z = arith.constant 0 : i32
  %one = arith.constant 1 : i32
  %two = arith.constant 2 : i32
  %four = arith.constant 4 : i32
  %n = memref.load %st[%i4] : !st
  %cap = memref.load %st[%i10] : !st
  %full = arith.cmpi eq, %n, %cap : i32
  %r = scf.if %full -> (i32) {
    func.call @kc_bad(%st, %two) : (!st, i32) -> ()
    scf.yield %z : i32
  } else {
    %w = arith.muli %n, %four : i32
    %x0 = arith.index_cast %w : i32 to index
    %x1 = arith.addi %x0, %i1 : index
    %x2 = arith.addi %x1, %i1 : index
    %x3 = arith.addi %x2, %i1 : index
    memref.store %w0, %sets[%x0] : !m64
    memref.store %w1, %sets[%x1] : !m64
    memref.store %w2, %sets[%x2] : !m64
    memref.store %w3, %sets[%x3] : !m64
    %n1 = arith.addi %n, %one : i32
    memref.store %n1, %st[%i4] : !st
    scf.yield %n : i32
  }
  return %r : i32
}

// emit(s): the next step, or Space and 0 when the steps are full.
func.func private @kc_emit(%st: !st, %steps: !m32, %op: i32, %x: i32, %y: i32, %zz: i32) -> i32 {
  %i1 = arith.constant 1 : index
  %i3 = arith.constant 3 : index
  %i9 = arith.constant 9 : index
  %z = arith.constant 0 : i32
  %one = arith.constant 1 : i32
  %two = arith.constant 2 : i32
  %four = arith.constant 4 : i32
  %n = memref.load %st[%i3] : !st
  %cap = memref.load %st[%i9] : !st
  %full = arith.cmpi eq, %n, %cap : i32
  %r = scf.if %full -> (i32) {
    func.call @kc_bad(%st, %two) : (!st, i32) -> ()
    scf.yield %z : i32
  } else {
    %w = arith.muli %n, %four : i32
    %x0 = arith.index_cast %w : i32 to index
    %x1 = arith.addi %x0, %i1 : index
    %x2 = arith.addi %x1, %i1 : index
    %x3 = arith.addi %x2, %i1 : index
    memref.store %op, %steps[%x0] : !m32
    memref.store %x, %steps[%x1] : !m32
    memref.store %y, %steps[%x2] : !m32
    memref.store %zz, %steps[%x3] : !m32
    %n1 = arith.addi %n, %one : i32
    memref.store %n1, %st[%i3] : !st
    scf.yield %n : i32
  }
  return %r : i32
}

// steps[r].field = v (field 1 x, 2 y, 3 z)
func.func private @kc_patch(%steps: !m32, %r: i32, %field: i32, %v: i32) {
  %four = arith.constant 4 : i32
  %w = arith.muli %r, %four : i32
  %f = arith.addi %w, %field : i32
  %x = arith.index_cast %f : i32 to index
  memref.store %v, %steps[%x] : !m32
  return
}

// Set::add(c)
func.func private @kc_add(%buf: memref<4xi64>, %c: i32) {
  %k6 = arith.constant 6 : i32
  %k63 = arith.constant 63 : i32
  %one = arith.constant 1 : i64
  %wi = arith.shrui %c, %k6 : i32
  %bi = arith.andi %c, %k63 : i32
  %ix = arith.index_cast %wi : i32 to index
  %b64 = arith.extui %bi : i32 to i64
  %bit = arith.shli %one, %b64 : i64
  %w = memref.load %buf[%ix] : memref<4xi64>
  %nw = arith.ori %w, %bit : i64
  memref.store %nw, %buf[%ix] : memref<4xi64>
  return
}

// The Lit node of the one byte c: set({c}) first, then the node, as node({Kind::Lit, set(s)}) evaluates.
func.func private @kc_lit(%st: !st, %nodes: !m32, %sets: !m64, %c: i32) -> i32 {
  %k6 = arith.constant 6 : i32
  %k63 = arith.constant 63 : i32
  %one = arith.constant 1 : i64
  %zero = arith.constant 0 : i64
  %z = arith.constant 0 : i32
  %k1 = arith.constant 1 : i32
  %k2 = arith.constant 2 : i32
  %k3 = arith.constant 3 : i32
  %wi = arith.shrui %c, %k6 : i32
  %bi = arith.andi %c, %k63 : i32
  %b64 = arith.extui %bi : i32 to i64
  %bit = arith.shli %one, %b64 : i64
  %e0 = arith.cmpi eq, %wi, %z : i32
  %e1 = arith.cmpi eq, %wi, %k1 : i32
  %e2 = arith.cmpi eq, %wi, %k2 : i32
  %e3 = arith.cmpi eq, %wi, %k3 : i32
  %w0 = arith.select %e0, %bit, %zero : i64
  %w1 = arith.select %e1, %bit, %zero : i64
  %w2 = arith.select %e2, %bit, %zero : i64
  %w3 = arith.select %e3, %bit, %zero : i64
  %s = func.call @kc_set4(%st, %sets, %w0, %w1, %w2, %w3) : (!st, !m64, i64, i64, i64, i64) -> i32
  %n = func.call @kc_node(%st, %nodes, %z, %s, %z, %z, %z) : (!st, !m32, i32, i32, i32, i32, i32) -> i32
  return %n : i32
}

// [:name:] for the name pat[from, from + len): adds the class's bytes to buf and answers whether the name is known.
// The name is compared whole (trikeshed.compare also orders by length, so 0 is the same bytes and the same length).
func.func private @kc_class(%pat: !s, %from: i32, %len: i32, %buf: memref<4xi64>) -> i1 {
  %z = arith.constant 0 : i32
  %one = arith.constant 1 : i32
  %count = arith.constant 15 : i32
  %four = arith.constant 4 : i32
  %i1 = arith.constant 1 : index
  %t = arith.constant 1 : i1
  %f = arith.constant 0 : i1
  %gn = memref.get_global @kc_class_names : memref<64xi8>
  %names = trikeshed.text %gn : memref<64xi8> -> !s
  %go = memref.get_global @kc_class_off : memref<15xi32>
  %gl = memref.get_global @kc_class_len : memref<15xi32>
  %gs = memref.get_global @kc_class_sets : memref<60xi64>
  %fromi = arith.index_cast %from : i32 to index
  %leni = arith.index_cast %len : i32 to index
  %name = trikeshed.slice %pat[%fromi, %leni] : !s -> !s
  %k:2 = scf.while (%i = %z, %hit = %f) : (i32, i1) -> (i32, i1) {
    %more = arith.cmpi ult, %i, %count : i32
    %nothit = arith.xori %hit, %t : i1
    %go2 = arith.andi %more, %nothit : i1
    scf.condition(%go2) %i, %hit : i32, i1
  } do {
  ^bb0(%j: i32, %h: i1):
    %ji = arith.index_cast %j : i32 to index
    %o = memref.load %go[%ji] : memref<15xi32>
    %l = memref.load %gl[%ji] : memref<15xi32>
    %oi = arith.index_cast %o : i32 to index
    %li = arith.index_cast %l : i32 to index
    %cand = trikeshed.slice %names[%oi, %li] : !s -> !s
    %cmp = trikeshed.compare %name, %cand unsigned : !s, !s
    %same = arith.cmpi eq, %cmp, %z : i32
    %j1 = arith.addi %j, %one : i32
    %nj = arith.select %same, %j, %j1 : i32
    scf.yield %nj, %same : i32, i1
  }
  scf.if %k#1 {
    %base = arith.muli %k#0, %four : i32
    %bi = arith.index_cast %base : i32 to index
    %i4 = arith.constant 4 : index
    %i0 = arith.constant 0 : index
    scf.for %w = %i0 to %i4 step %i1 {
      %src = arith.addi %bi, %w : index
      %cw = memref.load %gs[%src] : memref<60xi64>
      %old = memref.load %buf[%w] : memref<4xi64>
      %nw = arith.ori %old, %cw : i64
      memref.store %nw, %buf[%w] : memref<4xi64>
    }
  }
  return %k#1 : i1
}

// A bracket expression, after its '[': a backslash in it is a byte like any other (POSIX), ']' first is a member, '-'
// first or last too; [. .] and [= =] name one byte.  The C++ bracket() as a block machine: ^loop carries (first, prev).
func.func private @kc_bracket(%pat: !s, %st: !st, %nodes: !m32, %steps: !m32, %sets: !m64) -> i32 {
  %z = arith.constant 0 : i32
  %k1 = arith.constant 1 : i32
  %k2 = arith.constant 2 : i32
  %k3 = arith.constant 3 : i32
  %k4 = arith.constant 4 : i32
  %k5 = arith.constant 5 : i32
  %m1 = arith.constant -1 : i32
  %c45 = arith.constant 45 : i32
  %c46 = arith.constant 46 : i32
  %c58 = arith.constant 58 : i32
  %c61 = arith.constant 61 : i32
  %c91 = arith.constant 91 : i32
  %c93 = arith.constant 93 : i32
  %c94 = arith.constant 94 : i32
  %t = arith.constant 1 : i1
  %f = arith.constant 0 : i1
  %zero = arith.constant 0 : i64
  %ones = arith.constant -1 : i64
  %i0 = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %i7 = arith.constant 7 : index
  %buf = memref.alloca() : memref<4xi64>
  memref.store %zero, %buf[%i0] : memref<4xi64>
  memref.store %zero, %buf[%i1] : memref<4xi64>
  memref.store %zero, %buf[%i2] : memref<4xi64>
  memref.store %zero, %buf[%i3] : memref<4xi64>
  %b0 = func.call @kc_peek(%pat, %st, %z) : (!s, !st, i32) -> i32
  %neg = arith.cmpi eq, %b0, %c94 : i32
  %negk = arith.extui %neg : i1 to i32
  func.call @kc_adv(%st, %negk) : (!st, i32) -> ()
  cf.br ^loop(%t, %m1 : i1, i32)
^loop(%first: i1, %prev: i32):
  %ch = func.call @kc_peek(%pat, %st, %z) : (!s, !st, i32) -> i32
  %atend = arith.cmpi eq, %ch, %m1 : i32
  %isclose = arith.cmpi eq, %ch, %c93 : i32
  %notfirst = arith.xori %first, %t : i1
  %closes = arith.andi %notfirst, %isclose : i1
  %stop = arith.ori %atend, %closes : i1
  cf.cond_br %stop, ^done, ^body
^body:
  %ch1 = func.call @kc_peek(%pat, %st, %k1) : (!s, !st, i32) -> i32
  %isLb = arith.cmpi eq, %ch, %c91 : i32
  %isColon = arith.cmpi eq, %ch1, %c58 : i32
  %cls = arith.andi %isLb, %isColon : i1
  cf.cond_br %cls, ^class, ^single
^class:
  %p = memref.load %st[%i0] : !st
  %end = memref.load %st[%i7] : !st
  %name = arith.addi %p, %k2 : i32
  cf.br ^cscan(%name : i32)
^cscan(%q: i32):
  %q1 = arith.addi %q, %k1 : i32
  %qin = arith.cmpi ult, %q1, %end : i32
  cf.cond_br %qin, ^ccheck, ^cdone
^ccheck:
  %bq = func.call @kc_byte(%pat, %q, %end) : (!s, i32, i32) -> i32
  %bq1 = func.call @kc_byte(%pat, %q1, %end) : (!s, i32, i32) -> i32
  %mc = arith.cmpi eq, %bq, %c58 : i32
  %mb = arith.cmpi eq, %bq1, %c93 : i32
  %m = arith.andi %mc, %mb : i1
  cf.cond_br %m, ^cdone, ^cscan(%q1 : i32)
^cdone:
  %qe = arith.addi %q, %k1 : i32
  %unclosed = arith.cmpi uge, %qe, %end : i32
  cf.cond_br %unclosed, ^invalid, ^clook
^clook:
  %len = arith.subi %q, %name : i32
  %known = func.call @kc_class(%pat, %name, %len, %buf) : (!s, i32, i32, memref<4xi64>) -> i1
  cf.cond_br %known, ^cok, ^invalid
^cok:
  %q2 = arith.addi %q, %k2 : i32
  memref.store %q2, %st[%i0] : !st
  cf.br ^loop(%f, %m1 : i1, i32)
^single:
  %isDot = arith.cmpi eq, %ch1, %c46 : i32
  %isEq = arith.cmpi eq, %ch1, %c61 : i32
  %de = arith.ori %isDot, %isEq : i1
  %coll = arith.andi %isLb, %de : i1
  cf.cond_br %coll, ^coll, ^plain
^coll:
  %b3 = func.call @kc_peek(%pat, %st, %k3) : (!s, !st, i32) -> i32
  %b4 = func.call @kc_peek(%pat, %st, %k4) : (!s, !st, i32) -> i32
  %s3 = arith.cmpi eq, %b3, %ch1 : i32
  %s4 = arith.cmpi eq, %b4, %c93 : i32
  %sok = arith.andi %s3, %s4 : i1
  cf.cond_br %sok, ^collok, ^invalid
^collok:
  %cc = func.call @kc_peek(%pat, %st, %k2) : (!s, !st, i32) -> i32
  func.call @kc_adv(%st, %k5) : (!st, i32) -> ()
  cf.br ^got(%cc : i32)
^plain:
  func.call @kc_adv(%st, %k1) : (!st, i32) -> ()
  cf.br ^got(%ch : i32)
^got(%c: i32):
  %isDash = arith.cmpi eq, %c, %c45 : i32
  %prevOk = arith.cmpi sge, %prev, %z : i32
  %nx = func.call @kc_peek(%pat, %st, %z) : (!s, !st, i32) -> i32
  %nxIn = arith.cmpi ne, %nx, %m1 : i32
  %nxOpen = arith.cmpi ne, %nx, %c93 : i32
  %r1 = arith.andi %isDash, %notfirst : i1
  %r2 = arith.andi %r1, %prevOk : i1
  %r3 = arith.andi %r2, %nxIn : i1
  %rng = arith.andi %r3, %nxOpen : i1
  cf.cond_br %rng, ^range, ^addone
^range:
  %h1 = func.call @kc_peek(%pat, %st, %k1) : (!s, !st, i32) -> i32
  %hLb = arith.cmpi eq, %nx, %c91 : i32
  %hDot = arith.cmpi eq, %h1, %c46 : i32
  %hEq = arith.cmpi eq, %h1, %c61 : i32
  %hDe = arith.ori %hDot, %hEq : i1
  %hcoll = arith.andi %hLb, %hDe : i1
  cf.cond_br %hcoll, ^rcoll, ^rnotcoll
^rcoll:
  %h3 = func.call @kc_peek(%pat, %st, %k3) : (!s, !st, i32) -> i32
  %h4 = func.call @kc_peek(%pat, %st, %k4) : (!s, !st, i32) -> i32
  %t3 = arith.cmpi eq, %h3, %h1 : i32
  %t4 = arith.cmpi eq, %h4, %c93 : i32
  %tok = arith.andi %t3, %t4 : i1
  cf.cond_br %tok, ^rcollok, ^invalid
^rcollok:
  %hc = func.call @kc_peek(%pat, %st, %k2) : (!s, !st, i32) -> i32
  func.call @kc_adv(%st, %k5) : (!st, i32) -> ()
  cf.br ^rhi(%hc : i32)
^rnotcoll:
  %hColon = arith.cmpi eq, %h1, %c58 : i32
  %hcl = arith.andi %hLb, %hColon : i1
  cf.cond_br %hcl, ^invalid, ^rplain
^rplain:
  func.call @kc_adv(%st, %k1) : (!st, i32) -> ()
  cf.br ^rhi(%nx : i32)
^rhi(%hi: i32):
  %below = arith.cmpi slt, %hi, %prev : i32
  cf.cond_br %below, ^invalid, ^rset
^rset:
  %lo_i = arith.index_cast %prev : i32 to index
  %hi_i = arith.index_cast %hi : i32 to index
  %hi_e = arith.addi %hi_i, %i1 : index
  scf.for %rc = %lo_i to %hi_e step %i1 {
    %rcv = arith.index_cast %rc : index to i32
    func.call @kc_add(%buf, %rcv) : (memref<4xi64>, i32) -> ()
  }
  cf.br ^loop(%f, %m1 : i1, i32)
^addone:
  func.call @kc_add(%buf, %c) : (memref<4xi64>, i32) -> ()
  cf.br ^loop(%f, %c : i1, i32)
^done:
  %closed = arith.cmpi eq, %ch, %c93 : i32
  cf.cond_br %closed, ^fin, ^invalid
^fin:
  func.call @kc_adv(%st, %k1) : (!st, i32) -> ()
  %v0 = memref.load %buf[%i0] : memref<4xi64>
  %v1 = memref.load %buf[%i1] : memref<4xi64>
  %v2 = memref.load %buf[%i2] : memref<4xi64>
  %v3 = memref.load %buf[%i3] : memref<4xi64>
  %mask = arith.select %neg, %ones, %zero : i64
  %u0 = arith.xori %v0, %mask : i64
  %u1 = arith.xori %v1, %mask : i64
  %u2 = arith.xori %v2, %mask : i64
  %u3 = arith.xori %v3, %mask : i64
  %sx = func.call @kc_set4(%st, %sets, %u0, %u1, %u2, %u3) : (!st, !m64, i64, i64, i64, i64) -> i32
  %nd = func.call @kc_node(%st, %nodes, %z, %sx, %z, %z, %z) : (!st, !m32, i32, i32, i32, i32, i32) -> i32
  return %nd : i32
^invalid:
  func.call @kc_bad(%st, %k1) : (!st, i32) -> ()
  return %z : i32
}

// number(v): a run of digits at the cursor; Space past 100000, false with no digit.
func.func private @kc_number(%pat: !s, %st: !st, %nodes: !m32, %steps: !m32, %sets: !m64) -> (i1, i32) {
  %z = arith.constant 0 : i32
  %k1 = arith.constant 1 : i32
  %k2 = arith.constant 2 : i32
  %k10 = arith.constant 10 : i32
  %c48 = arith.constant 48 : i32
  %c57 = arith.constant 57 : i32
  %lim = arith.constant 100000 : i32
  %t = arith.constant 1 : i1
  %f = arith.constant 0 : i1
  %b = func.call @kc_peek(%pat, %st, %z) : (!s, !st, i32) -> i32
  %ge = arith.cmpi sge, %b, %c48 : i32
  %le = arith.cmpi sle, %b, %c57 : i32
  %dig = arith.andi %ge, %le : i1
  cf.cond_br %dig, ^loop(%z : i32), ^no
^no:
  return %f, %z : i1, i32
^loop(%v: i32):
  %b2 = func.call @kc_peek(%pat, %st, %z) : (!s, !st, i32) -> i32
  %ge2 = arith.cmpi sge, %b2, %c48 : i32
  %le2 = arith.cmpi sle, %b2, %c57 : i32
  %dig2 = arith.andi %ge2, %le2 : i1
  cf.cond_br %dig2, ^step, ^yes
^step:
  %v10 = arith.muli %v, %k10 : i32
  %d = arith.subi %b2, %c48 : i32
  %v2 = arith.addi %v10, %d : i32
  func.call @kc_adv(%st, %k1) : (!st, i32) -> ()
  %big = arith.cmpi ugt, %v2, %lim : i32
  cf.cond_br %big, ^space, ^loop(%v2 : i32)
^space:
  func.call @kc_bad(%st, %k2) : (!st, i32) -> ()
  return %f, %v2 : i1, i32
^yes:
  return %t, %v : i1, i32
}

// atom(assertion): one atom at the cursor (the C++ took *p++ first).  Answers the node and whether it is an anchor.
func.func private @kc_atom(%pat: !s, %st: !st, %nodes: !m32, %steps: !m32, %sets: !m64) -> (i32, i1) {
  %z = arith.constant 0 : i32
  %k1 = arith.constant 1 : i32
  %k4 = arith.constant 4 : i32
  %k5 = arith.constant 5 : i32
  %k6 = arith.constant 6 : i32
  %k7 = arith.constant 7 : i32
  %m1 = arith.constant -1 : i32
  %c36 = arith.constant 36 : i32
  %c40 = arith.constant 40 : i32
  %c41 = arith.constant 41 : i32
  %c42 = arith.constant 42 : i32
  %c43 = arith.constant 43 : i32
  %c46 = arith.constant 46 : i32
  %c63 = arith.constant 63 : i32
  %c91 = arith.constant 91 : i32
  %c92 = arith.constant 92 : i32
  %c94 = arith.constant 94 : i32
  %c123 = arith.constant 123 : i32
  %c124 = arith.constant 124 : i32
  %t = arith.constant 1 : i1
  %f = arith.constant 0 : i1
  %ones = arith.constant -1 : i64
  %notnul = arith.constant -2 : i64
  %i5 = arith.constant 5 : index
  %c = func.call @kc_peek(%pat, %st, %z) : (!s, !st, i32) -> i32
  func.call @kc_adv(%st, %k1) : (!st, i32) -> ()
  %isDot = arith.cmpi eq, %c, %c46 : i32
  cf.cond_br %isDot, ^dot, ^n1
^dot:
  // any byte but NUL, as libstdc++'s POSIX '.'
  %sd = func.call @kc_set4(%st, %sets, %notnul, %ones, %ones, %ones) : (!st, !m64, i64, i64, i64, i64) -> i32
  %nd = func.call @kc_node(%st, %nodes, %z, %sd, %z, %z, %z) : (!st, !m32, i32, i32, i32, i32, i32) -> i32
  return %nd, %f : i32, i1
^n1:
  %isBr = arith.cmpi eq, %c, %c91 : i32
  cf.cond_br %isBr, ^br, ^n2
^br:
  %nb = func.call @kc_bracket(%pat, %st, %nodes, %steps, %sets) : (!s, !st, !m32, !m32, !m64) -> i32
  return %nb, %f : i32, i1
^n2:
  %isBol = arith.cmpi eq, %c, %c94 : i32
  cf.cond_br %isBol, ^bol, ^n3
^bol:
  %nbol = func.call @kc_node(%st, %nodes, %k5, %z, %z, %z, %z) : (!st, !m32, i32, i32, i32, i32, i32) -> i32
  return %nbol, %t : i32, i1
^n3:
  %isEol = arith.cmpi eq, %c, %c36 : i32
  cf.cond_br %isEol, ^eol, ^n4
^eol:
  %neol = func.call @kc_node(%st, %nodes, %k6, %z, %z, %z, %z) : (!st, !m32, i32, i32, i32, i32, i32) -> i32
  return %neol, %t : i32, i1
^n4:
  %isOpen = arith.cmpi eq, %c, %c40 : i32
  cf.cond_br %isOpen, ^grp, ^n5
^grp:
  %g0 = memref.load %st[%i5] : !st
  %g = arith.addi %g0, %k1 : i32
  memref.store %g, %st[%i5] : !st
  %e = func.call @kc_peek(%pat, %st, %z) : (!s, !st, i32) -> i32
  %eClose = arith.cmpi eq, %e, %c41 : i32
  cf.cond_br %eClose, ^gempty, ^galt
^gempty:
  %ne = func.call @kc_node(%st, %nodes, %k7, %z, %z, %z, %z) : (!st, !m32, i32, i32, i32, i32, i32) -> i32
  cf.br ^gjoin(%ne : i32)
^galt:
  %na = func.call @kc_alternation(%pat, %st, %nodes, %steps, %sets) : (!s, !st, !m32, !m32, !m64) -> i32
  cf.br ^gjoin(%na : i32)
^gjoin(%inner: i32):
  %e2 = func.call @kc_peek(%pat, %st, %z) : (!s, !st, i32) -> i32
  %e2Close = arith.cmpi eq, %e2, %c41 : i32
  cf.cond_br %e2Close, ^gok, ^invalid
^gok:
  func.call @kc_adv(%st, %k1) : (!st, i32) -> ()
  %ng = func.call @kc_node(%st, %nodes, %k4, %inner, %z, %g, %z) : (!st, !m32, i32, i32, i32, i32, i32) -> i32
  return %ng, %f : i32, i1
^n5:
  %isEsc = arith.cmpi eq, %c, %c92 : i32
  cf.cond_br %isEsc, ^esc, ^n6
^esc:
  // only a special character may be escaped: Nix's libstdc++ is built strict (__STRICT_ANSI__)
  %ex = func.call @kc_peek(%pat, %st, %z) : (!s, !st, i32) -> i32
  %exEnd = arith.cmpi eq, %ex, %m1 : i32
  cf.cond_br %exEnd, ^invalid, ^esc1
^esc1:
  func.call @kc_adv(%st, %k1) : (!st, i32) -> ()
  %gsp = memref.get_global @kc_special : memref<256xi8>
  %spec = trikeshed.text %gsp : memref<256xi8> -> !s
  %exi = arith.index_cast %ex : i32 to index
  %sp8 = trikeshed.at %spec[%exi] : !s, index -> i8
  %sp32 = arith.extui %sp8 : i8 to i32
  %isSpec = arith.cmpi ne, %sp32, %z : i32
  cf.cond_br %isSpec, ^esclit, ^invalid
^esclit:
  %nl = func.call @kc_lit(%st, %nodes, %sets, %ex) : (!st, !m32, !m64, i32) -> i32
  return %nl, %f : i32, i1
^n6:
  // a quantifier with nothing before it
  %q1 = arith.cmpi eq, %c, %c42 : i32
  %q2 = arith.cmpi eq, %c, %c43 : i32
  %q3 = arith.cmpi eq, %c, %c63 : i32
  %q4 = arith.cmpi eq, %c, %c123 : i32
  %q5 = arith.cmpi eq, %c, %c41 : i32
  %q6 = arith.cmpi eq, %c, %c124 : i32
  %q12 = arith.ori %q1, %q2 : i1
  %q34 = arith.ori %q3, %q4 : i1
  %q56 = arith.ori %q5, %q6 : i1
  %q1234 = arith.ori %q12, %q34 : i1
  %quant = arith.ori %q1234, %q56 : i1
  cf.cond_br %quant, ^invalid, ^plain
^plain:
  %np = func.call @kc_lit(%st, %nodes, %sets, %c) : (!st, !m32, !m64, i32) -> i32
  return %np, %f : i32, i1
^invalid:
  func.call @kc_bad(%st, %k1) : (!st, i32) -> ()
  return %z, %f : i32, i1
}

// postfix(a, assertion): the repetitions after an atom; an anchor takes none.
func.func private @kc_postfix(%pat: !s, %st: !st, %nodes: !m32, %steps: !m32, %sets: !m64, %a: i32, %as: i1) -> i32 {
  %z = arith.constant 0 : i32
  %k1 = arith.constant 1 : i32
  %k3 = arith.constant 3 : i32
  %m1 = arith.constant -1 : i32
  %c42 = arith.constant 42 : i32
  %c43 = arith.constant 43 : i32
  %c44 = arith.constant 44 : i32
  %c63 = arith.constant 63 : i32
  %c123 = arith.constant 123 : i32
  %c125 = arith.constant 125 : i32
  %t = arith.constant 1 : i1
  cf.br ^loop(%a : i32)
^loop(%acc: i32):
  %b = func.call @kc_peek(%pat, %st, %z) : (!s, !st, i32) -> i32
  %atend = arith.cmpi eq, %b, %m1 : i32
  %fl = func.call @kc_failed(%st) : (!st) -> i1
  %stop = arith.ori %atend, %fl : i1
  cf.cond_br %stop, ^out, ^body
^body:
  %isBrace = arith.cmpi eq, %b, %c123 : i32
  cf.cond_br %isBrace, ^brace, ^simple
^simple:
  %isStar = arith.cmpi eq, %b, %c42 : i32
  %isPlus = arith.cmpi eq, %b, %c43 : i32
  %isQ = arith.cmpi eq, %b, %c63 : i32
  %sp = arith.ori %isStar, %isPlus : i1
  %isq = arith.ori %sp, %isQ : i1
  cf.cond_br %isq, ^q, ^out
^q:
  cf.cond_br %as, ^invalid, ^qok
^qok:
  %lo = arith.extui %isPlus : i1 to i32
  %hi = arith.select %isQ, %k1, %m1 : i32
  func.call @kc_adv(%st, %k1) : (!st, i32) -> ()
  %nq = func.call @kc_node(%st, %nodes, %k3, %acc, %z, %lo, %hi) : (!st, !m32, i32, i32, i32, i32, i32) -> i32
  cf.br ^loop(%nq : i32)
^brace:
  cf.cond_br %as, ^invalid, ^b1
^b1:
  func.call @kc_adv(%st, %k1) : (!st, i32) -> ()
  %lr:2 = func.call @kc_number(%pat, %st, %nodes, %steps, %sets) : (!s, !st, !m32, !m32, !m64) -> (i1, i32)
  cf.cond_br %lr#0, ^b2, ^invalid
^b2:
  %cm = func.call @kc_peek(%pat, %st, %z) : (!s, !st, i32) -> i32
  %isComma = arith.cmpi eq, %cm, %c44 : i32
  cf.cond_br %isComma, ^b3, ^b4(%lr#1 : i32)
^b3:
  func.call @kc_adv(%st, %k1) : (!st, i32) -> ()
  %hr:2 = func.call @kc_number(%pat, %st, %nodes, %steps, %sets) : (!s, !st, !m32, !m32, !m64) -> (i1, i32)
  %hh = arith.select %hr#0, %hr#1, %m1 : i32
  cf.br ^b4(%hh : i32)
^b4(%hb: i32):
  %cl = func.call @kc_peek(%pat, %st, %z) : (!s, !st, i32) -> i32
  %closeOk = arith.cmpi eq, %cl, %c125 : i32
  %bounded = arith.cmpi ne, %hb, %m1 : i32
  %lt = arith.cmpi ult, %hb, %lr#1 : i32
  %badb = arith.andi %bounded, %lt : i1
  %okb = arith.xori %badb, %t : i1
  %good = arith.andi %closeOk, %okb : i1
  cf.cond_br %good, ^b5, ^invalid
^b5:
  func.call @kc_adv(%st, %k1) : (!st, i32) -> ()
  %nb = func.call @kc_node(%st, %nodes, %k3, %acc, %z, %lr#1, %hb) : (!st, !m32, i32, i32, i32, i32, i32) -> i32
  cf.br ^loop(%nb : i32)
^out:
  return %acc : i32
^invalid:
  func.call @kc_bad(%st, %k1) : (!st, i32) -> ()
  return %z : i32
}

// sequence(): atoms with their repetitions up to '|', ')' or the end; Empty for none.
func.func private @kc_sequence(%pat: !s, %st: !st, %nodes: !m32, %steps: !m32, %sets: !m64) -> i32 {
  %z = arith.constant 0 : i32
  %k1 = arith.constant 1 : i32
  %k7 = arith.constant 7 : i32
  %m1 = arith.constant -1 : i32
  %c41 = arith.constant 41 : i32
  %c124 = arith.constant 124 : i32
  cf.br ^loop(%m1 : i32)
^loop(%acc: i32):
  %b = func.call @kc_peek(%pat, %st, %z) : (!s, !st, i32) -> i32
  %atend = arith.cmpi eq, %b, %m1 : i32
  %isBar = arith.cmpi eq, %b, %c124 : i32
  %isClose = arith.cmpi eq, %b, %c41 : i32
  %fl = func.call @kc_failed(%st) : (!st) -> i1
  %s1 = arith.ori %atend, %isBar : i1
  %s2 = arith.ori %isClose, %fl : i1
  %stop = arith.ori %s1, %s2 : i1
  cf.cond_br %stop, ^end, ^body
^body:
  %at:2 = func.call @kc_atom(%pat, %st, %nodes, %steps, %sets) : (!s, !st, !m32, !m32, !m64) -> (i32, i1)
  %a = func.call @kc_postfix(%pat, %st, %nodes, %steps, %sets, %at#0, %at#1) : (!s, !st, !m32, !m32, !m64, i32, i1) -> i32
  %none = arith.cmpi eq, %acc, %m1 : i32
  cf.cond_br %none, ^loop(%a : i32), ^cat
^cat:
  %nc = func.call @kc_node(%st, %nodes, %k1, %acc, %a, %z, %z) : (!st, !m32, i32, i32, i32, i32, i32) -> i32
  cf.br ^loop(%nc : i32)
^end:
  %empty = arith.cmpi eq, %acc, %m1 : i32
  cf.cond_br %empty, ^mkempty, ^ret
^mkempty:
  %ne = func.call @kc_node(%st, %nodes, %k7, %z, %z, %z, %z) : (!st, !m32, i32, i32, i32, i32, i32) -> i32
  return %ne : i32
^ret:
  return %acc : i32
}

// alternation(): sequences separated by '|' (the right one parsed before its Alt node is made).
func.func private @kc_alternation(%pat: !s, %st: !st, %nodes: !m32, %steps: !m32, %sets: !m64) -> i32 {
  %z = arith.constant 0 : i32
  %k1 = arith.constant 1 : i32
  %k2 = arith.constant 2 : i32
  %c124 = arith.constant 124 : i32
  %t = arith.constant 1 : i1
  %a0 = func.call @kc_sequence(%pat, %st, %nodes, %steps, %sets) : (!s, !st, !m32, !m32, !m64) -> i32
  cf.br ^loop(%a0 : i32)
^loop(%acc: i32):
  %b = func.call @kc_peek(%pat, %st, %z) : (!s, !st, i32) -> i32
  %isBar = arith.cmpi eq, %b, %c124 : i32
  %fl = func.call @kc_failed(%st) : (!st) -> i1
  %ok = arith.xori %fl, %t : i1
  %go = arith.andi %isBar, %ok : i1
  cf.cond_br %go, ^body, ^end
^body:
  func.call @kc_adv(%st, %k1) : (!st, i32) -> ()
  %r = func.call @kc_sequence(%pat, %st, %nodes, %steps, %sets) : (!s, !st, !m32, !m32, !m64) -> i32
  %n = func.call @kc_node(%st, %nodes, %k2, %acc, %r, %z, %z) : (!st, !m32, i32, i32, i32, i32, i32) -> i32
  cf.br ^loop(%n : i32)
^end:
  return %acc : i32
}

// repeat(body, loop): one Rep state (its loop slot in z), the body at x, the way out at y; a loop's body jumps back.
func.func private @kc_repeat(%pat: !s, %st: !st, %nodes: !m32, %steps: !m32, %sets: !m64, %body: i32, %loop: i1) {
  %z = arith.constant 0 : i32
  %k1 = arith.constant 1 : i32
  %k2 = arith.constant 2 : i32
  %k3 = arith.constant 3 : i32
  %i3 = arith.constant 3 : index
  %i6 = arith.constant 6 : index
  %r = func.call @kc_emit(%st, %steps, %k2, %z, %z, %z) : (!st, !m32, i32, i32, i32, i32) -> i32
  %fl = func.call @kc_failed(%st) : (!st) -> i1
  cf.cond_br %fl, ^ret, ^go
^go:
  %l = memref.load %st[%i6] : !st
  %l1 = arith.addi %l, %k1 : i32
  memref.store %l1, %st[%i6] : !st
  func.call @kc_patch(%steps, %r, %k3, %l) : (!m32, i32, i32, i32) -> ()
  %ns = memref.load %st[%i3] : !st
  func.call @kc_patch(%steps, %r, %k1, %ns) : (!m32, i32, i32, i32) -> ()
  func.call @kc_gen(%pat, %st, %nodes, %steps, %sets, %body) : (!s, !st, !m32, !m32, !m64, i32) -> ()
  cf.cond_br %loop, ^jmp, ^tail
^jmp:
  %j = func.call @kc_emit(%st, %steps, %k3, %r, %z, %z) : (!st, !m32, i32, i32, i32, i32) -> i32
  cf.br ^tail
^tail:
  %fl2 = func.call @kc_failed(%st) : (!st) -> i1
  cf.cond_br %fl2, ^ret, ^sety
^sety:
  %ny = memref.load %st[%i3] : !st
  func.call @kc_patch(%steps, %r, %k2, %ny) : (!m32, i32, i32, i32) -> ()
  cf.br ^ret
^ret:
  return
}

// gen(i): node i's steps.
func.func private @kc_gen(%pat: !s, %st: !st, %nodes: !m32, %steps: !m32, %sets: !m64, %i: i32) {
  %z = arith.constant 0 : i32
  %k1 = arith.constant 1 : i32
  %k2 = arith.constant 2 : i32
  %k3 = arith.constant 3 : i32
  %k4 = arith.constant 4 : i32
  %k5 = arith.constant 5 : i32
  %k6 = arith.constant 6 : i32
  %m1 = arith.constant -1 : i32
  %t = arith.constant 1 : i1
  %f = arith.constant 0 : i1
  %i1 = arith.constant 1 : index
  %i3 = arith.constant 3 : index
  %fl0 = func.call @kc_failed(%st) : (!st) -> i1
  cf.cond_br %fl0, ^ret, ^go
^go:
  %w = arith.muli %i, %k5 : i32
  %x0 = arith.index_cast %w : i32 to index
  %x1 = arith.addi %x0, %i1 : index
  %x2 = arith.addi %x1, %i1 : index
  %x3 = arith.addi %x2, %i1 : index
  %x4 = arith.addi %x3, %i1 : index
  %kw = memref.load %nodes[%x0] : !m32
  %na = memref.load %nodes[%x1] : !m32
  %nb = memref.load %nodes[%x2] : !m32
  %mn = memref.load %nodes[%x3] : !m32
  %mx = memref.load %nodes[%x4] : !m32
  %k255 = arith.constant 255 : i32
  %kind = arith.andi %kw, %k255 : i32
  %isLit = arith.cmpi eq, %kind, %z : i32
  cf.cond_br %isLit, ^lit, ^n1
^lit:
  %e0 = func.call @kc_emit(%st, %steps, %z, %na, %z, %z) : (!st, !m32, i32, i32, i32, i32) -> i32
  cf.br ^ret
^n1:
  %isCat = arith.cmpi eq, %kind, %k1 : i32
  cf.cond_br %isCat, ^cat, ^n2
^cat:
  func.call @kc_gen(%pat, %st, %nodes, %steps, %sets, %na) : (!s, !st, !m32, !m32, !m64, i32) -> ()
  func.call @kc_gen(%pat, %st, %nodes, %steps, %sets, %nb) : (!s, !st, !m32, !m32, !m64, i32) -> ()
  cf.br ^ret
^n2:
  %isAlt = arith.cmpi eq, %kind, %k2 : i32
  cf.cond_br %isAlt, ^alt, ^n3
^alt:
  // alt L1 L2; L1: a; jmp end; L2: b; end:
  %alt = func.call @kc_emit(%st, %steps, %k1, %z, %z, %z) : (!st, !m32, i32, i32, i32, i32) -> i32
  %fa = func.call @kc_failed(%st) : (!st) -> i1
  cf.cond_br %fa, ^ret, ^alt1
^alt1:
  %s1 = memref.load %st[%i3] : !st
  func.call @kc_patch(%steps, %alt, %k1, %s1) : (!m32, i32, i32, i32) -> ()
  func.call @kc_gen(%pat, %st, %nodes, %steps, %sets, %na) : (!s, !st, !m32, !m32, !m64, i32) -> ()
  %jmp = func.call @kc_emit(%st, %steps, %k3, %z, %z, %z) : (!st, !m32, i32, i32, i32, i32) -> i32
  %fj = func.call @kc_failed(%st) : (!st) -> i1
  cf.cond_br %fj, ^ret, ^alt2
^alt2:
  %s2 = memref.load %st[%i3] : !st
  func.call @kc_patch(%steps, %alt, %k2, %s2) : (!m32, i32, i32, i32) -> ()
  func.call @kc_gen(%pat, %st, %nodes, %steps, %sets, %nb) : (!s, !st, !m32, !m32, !m64, i32) -> ()
  %s3 = memref.load %st[%i3] : !st
  func.call @kc_patch(%steps, %jmp, %k1, %s3) : (!m32, i32, i32, i32) -> ()
  cf.br ^ret
^n3:
  %isGroup = arith.cmpi eq, %kind, %k4 : i32
  cf.cond_br %isGroup, ^group, ^n4
^group:
  %g2 = arith.muli %mn, %k2 : i32
  %g21 = arith.addi %g2, %k1 : i32
  %eg0 = func.call @kc_emit(%st, %steps, %k4, %g2, %z, %z) : (!st, !m32, i32, i32, i32, i32) -> i32
  func.call @kc_gen(%pat, %st, %nodes, %steps, %sets, %na) : (!s, !st, !m32, !m32, !m64, i32) -> ()
  %eg1 = func.call @kc_emit(%st, %steps, %k4, %g21, %z, %z) : (!st, !m32, i32, i32, i32, i32) -> i32
  cf.br ^ret
^n4:
  %isBol = arith.cmpi eq, %kind, %k5 : i32
  cf.cond_br %isBol, ^bol, ^n5
^bol:
  %eb = func.call @kc_emit(%st, %steps, %k5, %z, %z, %z) : (!st, !m32, i32, i32, i32, i32) -> i32
  cf.br ^ret
^n5:
  %isEol = arith.cmpi eq, %kind, %k6 : i32
  cf.cond_br %isEol, ^eol, ^n6
^eol:
  %ee = func.call @kc_emit(%st, %steps, %k6, %z, %z, %z) : (!st, !m32, i32, i32, i32, i32) -> i32
  cf.br ^ret
^n6:
  %isRep = arith.cmpi eq, %kind, %k3 : i32
  cf.cond_br %isRep, ^rep, ^ret
^rep:
  // min copies of the body, then a loop, or one optional repeat state per copy up to max
  cf.br ^must(%z : i32)
^must(%k: i32):
  %kl = arith.cmpi ult, %k, %mn : i32
  %fm = func.call @kc_failed(%st) : (!st) -> i1
  %nfm = arith.xori %fm, %t : i1
  %mgo = arith.andi %kl, %nfm : i1
  cf.cond_br %mgo, ^mbody, ^opt
^mbody:
  func.call @kc_gen(%pat, %st, %nodes, %steps, %sets, %na) : (!s, !st, !m32, !m32, !m64, i32) -> ()
  %k1n = arith.addi %k, %k1 : i32
  cf.br ^must(%k1n : i32)
^opt:
  %unb = arith.cmpi eq, %mx, %m1 : i32
  cf.cond_br %unb, ^star, ^opts(%mn : i32)
^star:
  func.call @kc_repeat(%pat, %st, %nodes, %steps, %sets, %na, %t) : (!s, !st, !m32, !m32, !m64, i32, i1) -> ()
  cf.br ^ret
^opts(%o: i32):
  %ol = arith.cmpi ult, %o, %mx : i32
  %fo = func.call @kc_failed(%st) : (!st) -> i1
  %nfo = arith.xori %fo, %t : i1
  %ogo = arith.andi %ol, %nfo : i1
  cf.cond_br %ogo, ^obody, ^ret
^obody:
  func.call @kc_repeat(%pat, %st, %nodes, %steps, %sets, %na, %f) : (!s, !st, !m32, !m32, !m64, i32, i1) -> ()
  %o1 = arith.addi %o, %k1 : i32
  cf.br ^opts(%o1 : i32)
^ret:
  return
}

// compile(pattern, len, prog, pool, poolCap): counts is {nSteps, nSets, groups, loops} in and out (the Program's own
// counters, as the C++ compiled from them); the answer is Program::error (0 None, 1 Invalid, 2 Space).
func.func @mlnix_kursive_compile(%pattern: !llvm.ptr, %len: i32, %stepsP: !llvm.ptr, %capSteps: i32,
    %setsP: !llvm.ptr, %capSets: i32, %poolP: !llvm.ptr, %poolCap: i32, %countsP: !llvm.ptr) -> i32 {
  %z = arith.constant 0 : i32
  %k1 = arith.constant 1 : i32
  %k4 = arith.constant 4 : i32
  %k7 = arith.constant 7 : i32
  %z64 = arith.constant 0 : i64
  %i0 = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %i4 = arith.constant 4 : index
  %i5 = arith.constant 5 : index
  %i6 = arith.constant 6 : index
  %i7 = arith.constant 7 : index
  %i8 = arith.constant 8 : index
  %i9 = arith.constant 9 : index
  %i10 = arith.constant 10 : index
  %len64 = arith.extui %len : i32 to i64
  %dp = func.call @kc_desc(%pattern, %len64) : (!llvm.ptr, i64) -> !d
  %mp = builtin.unrealized_conversion_cast %dp : !d to !m8
  %pat = builtin.unrealized_conversion_cast %mp : !m8 to !s
  %ds = func.call @kc_desc(%stepsP, %z64) : (!llvm.ptr, i64) -> !d
  %steps = builtin.unrealized_conversion_cast %ds : !d to !m32
  %dt = func.call @kc_desc(%setsP, %z64) : (!llvm.ptr, i64) -> !d
  %sets = builtin.unrealized_conversion_cast %dt : !d to !m64
  %dn = func.call @kc_desc(%poolP, %z64) : (!llvm.ptr, i64) -> !d
  %nodes = builtin.unrealized_conversion_cast %dn : !d to !m32
  %dc = func.call @kc_desc(%countsP, %z64) : (!llvm.ptr, i64) -> !d
  %counts = builtin.unrealized_conversion_cast %dc : !d to !m32
  %st = memref.alloca() : !st
  %n0 = memref.load %counts[%i0] : !m32
  %n1 = memref.load %counts[%i1] : !m32
  %n2 = memref.load %counts[%i2] : !m32
  %n3 = memref.load %counts[%i3] : !m32
  memref.store %z, %st[%i0] : !st
  memref.store %z, %st[%i1] : !st
  memref.store %z, %st[%i2] : !st
  memref.store %n0, %st[%i3] : !st
  memref.store %n1, %st[%i4] : !st
  memref.store %n2, %st[%i5] : !st
  memref.store %n3, %st[%i6] : !st
  memref.store %len, %st[%i7] : !st
  memref.store %poolCap, %st[%i8] : !st
  memref.store %capSteps, %st[%i9] : !st
  memref.store %capSets, %st[%i10] : !st
  %root = func.call @kc_alternation(%pat, %st, %nodes, %steps, %sets) : (!s, !st, !m32, !m32, !m64) -> i32
  // a ')' with no '(' before it
  %fl = func.call @kc_failed(%st) : (!st) -> i1
  %p = memref.load %st[%i0] : !st
  %rest = arith.cmpi ne, %p, %len : i32
  %t = arith.constant 1 : i1
  %ok = arith.xori %fl, %t : i1
  %stray = arith.andi %ok, %rest : i1
  scf.if %stray {
    func.call @kc_bad(%st, %k1) : (!st, i32) -> ()
  }
  %fl2 = func.call @kc_failed(%st) : (!st) -> i1
  %ok2 = arith.xori %fl2, %t : i1
  scf.if %ok2 {
    %s0 = func.call @kc_emit(%st, %steps, %k4, %z, %z, %z) : (!st, !m32, i32, i32, i32, i32) -> i32
    func.call @kc_gen(%pat, %st, %nodes, %steps, %sets, %root) : (!s, !st, !m32, !m32, !m64, i32) -> ()
    %s1 = func.call @kc_emit(%st, %steps, %k4, %k1, %z, %z) : (!st, !m32, i32, i32, i32, i32) -> i32
    %s2 = func.call @kc_emit(%st, %steps, %k7, %z, %z, %z) : (!st, !m32, i32, i32, i32, i32) -> i32
  }
  %o0 = memref.load %st[%i3] : !st
  %o1 = memref.load %st[%i4] : !st
  %o2 = memref.load %st[%i5] : !st
  %o3 = memref.load %st[%i6] : !st
  memref.store %o0, %counts[%i0] : !m32
  memref.store %o1, %counts[%i1] : !m32
  memref.store %o2, %counts[%i2] : !m32
  memref.store %o3, %counts[%i3] : !m32
  %err = memref.load %st[%i2] : !st
  return %err : i32
}
