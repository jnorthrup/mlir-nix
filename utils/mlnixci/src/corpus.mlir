// corpus.mlir -- the corpus: the evaluation's JSON as one series, its Confix index, and the columns of its options.
//
// A corpus is a record of 8-byte slots (below).  Every text in it is a coordinate: into the evaluation's JSON (a value,
// a state, the name a code stands for -- written inside quotes there, and emitted as written), or into one of two series
// made at load by columns.mlir's opt_text: the paths joined by '.' (each row's key), and the path and description a row
// is searched by, their escapes read and lower-cased.  The two names no option writes, "?" and "(none)", are bytes put
// after the JSON in the same buffer.
//
//   0 text  1 len  2 flat  3 n  4 obj[n]  5 value[n]  6 state[n]  7 keys  8 key[n]  9 hay  10 hayAt[n]
//   11..16 column[n] i32: section kind state module whatif match      17..20 dict: each code's name, per column 0..3
//   21..24 codes per column 0..3   25 the etc object's row, or -1   26 ms (f64)   27 order[n] i32: rows by key
//   28 baseOf[n] i32: the base row with the same key, or -1 (set by corpus_mark)   29 the length of keys

llvm.func @malloc(i64) -> !llvm.ptr
llvm.func @calloc(i64, i64) -> !llvm.ptr
llvm.func @realloc(!llvm.ptr, i64) -> !llvm.ptr
llvm.func @free(!llvm.ptr)
llvm.func @memcpy(!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
// columns.mlir (TrikeShed's ops): a column's codes and names, and rows in the order of their pieces
llvm.func @_mlir_ciface_col_code(!llvm.ptr, !llvm.ptr, !llvm.ptr)
llvm.func @_mlir_ciface_col_order(!llvm.ptr, !llvm.ptr, !llvm.ptr)
llvm.func @_mlir_ciface_opt_members(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64)
llvm.func @_mlir_ciface_opt_cells(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, i64)
llvm.func @_mlir_ciface_opt_text(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64)
llvm.func @_mlir_ciface_mark(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)

func.func private @tw(i64, i64) -> i64
func.func private @view(!llvm.ptr, !llvm.ptr, i64)
func.func private @tw_s(i64) -> i64
func.func private @tw_e(i64) -> i64
func.func private @tw_n(i64) -> i64
func.func private @at(!llvm.ptr, i64) -> i8
func.func private @off(!llvm.ptr, i64) -> !llvm.ptr
func.func private @same(!llvm.ptr, i64, !llvm.ptr, i64) -> i1
func.func private @cx_scan(!llvm.ptr, i64) -> !llvm.ptr
func.func private @cx_free(!llvm.ptr)
func.func private @cx_tag(!llvm.ptr, i64) -> i64
func.func private @cx_raw(!llvm.ptr, i64) -> i64
func.func private @cx_str(!llvm.ptr, i64) -> i64
func.func private @cx_nkids(!llvm.ptr, i64) -> i64
func.func private @cx_kid(!llvm.ptr, i64, i64) -> i64
func.func private @cx_member(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
func.func private @cx_d(!llvm.ptr, i32) -> !llvm.ptr
func.func private @cx_text(!llvm.ptr) -> !llvm.ptr

llvm.mlir.global internal constant @k_options("options") : !llvm.array<7 x i8>
llvm.mlir.global internal constant @k_etc("etc") : !llvm.array<3 x i8>
llvm.mlir.global internal constant @k_suffix("?(none)") : !llvm.array<7 x i8>
llvm.mlir.global internal constant @k_notobject("the evaluation is not a JSON object") : !llvm.array<35 x i8>
llvm.mlir.global internal constant @k_nooptions("the evaluation has no options") : !llvm.array<29 x i8>

llvm.mlir.global internal @why_p() : !llvm.ptr {
  %0 = llvm.mlir.zero : !llvm.ptr
  llvm.return %0 : !llvm.ptr
}
llvm.mlir.global internal @why_n(0 : i64) : i64

// why the last corpus_load refused
func.func @corpus_why() -> !llvm.ptr {
  %pp = llvm.mlir.addressof @why_p : !llvm.ptr
  %p = llvm.load %pp : !llvm.ptr -> !llvm.ptr
  return %p : !llvm.ptr
}
func.func @corpus_why_n() -> i64 {
  %np = llvm.mlir.addressof @why_n : !llvm.ptr
  %n = llvm.load %np : !llvm.ptr -> i64
  return %n : i64
}

// ---- slots and arrays

func.func @getp(%c: !llvm.ptr, %k: i64) -> !llvm.ptr {
  %s = llvm.getelementptr %c[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %s : !llvm.ptr -> !llvm.ptr
  return %v : !llvm.ptr
}
func.func @geti(%c: !llvm.ptr, %k: i64) -> i64 {
  %s = llvm.getelementptr %c[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %s : !llvm.ptr -> i64
  return %v : i64
}
func.func @setp(%c: !llvm.ptr, %k: i64, %v: !llvm.ptr) {
  %s = llvm.getelementptr %c[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %s : !llvm.ptr, !llvm.ptr
  return
}
func.func @seti(%c: !llvm.ptr, %k: i64, %v: i64) {
  %s = llvm.getelementptr %c[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %s : i64, !llvm.ptr
  return
}
func.func @ld64(%a: !llvm.ptr, %i: i64) -> i64 {
  %s = llvm.getelementptr %a[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %s : !llvm.ptr -> i64
  return %v : i64
}
func.func @st64(%a: !llvm.ptr, %i: i64, %v: i64) {
  %s = llvm.getelementptr %a[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %s : i64, !llvm.ptr
  return
}
func.func @ld32(%a: !llvm.ptr, %i: i64) -> i64 {
  %s = llvm.getelementptr %a[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i32
  %v = llvm.load %s : !llvm.ptr -> i32
  %z = arith.extsi %v : i32 to i64
  return %z : i64
}
func.func @st32(%a: !llvm.ptr, %i: i64, %v: i64) {
  %s = llvm.getelementptr %a[%i] : (!llvm.ptr, i64) -> !llvm.ptr, i32
  %t = arith.trunci %v : i64 to i32
  llvm.store %t, %s : i32, !llvm.ptr
  return
}

// rows 0 ..< n (i32) in the order of their pieces of base (n coordinates at tws, into the bn bytes at base): columns.mlir's
// col_order; the buffer is malloc'd
func.func @sorted_rows(%n: i64, %base: !llvm.ptr, %bn: i64, %tws: !llvm.ptr) -> !llvm.ptr {
  %one = arith.constant 1 : i32
  %td = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%td, %base, %bn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %pd = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%pd, %tws, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %rd = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  llvm.call @_mlir_ciface_col_order(%rd, %td, %pd) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  // a fresh buffer: its allocation is its data (offset 0)
  %perm = llvm.load %rd : !llvm.ptr -> !llvm.ptr
  return %perm : !llvm.ptr
}


// ---- load

// The corpus of the evaluation's JSON text (whose buffer it takes), or null (corpus_why says why).
func.func @corpus_load(%json: !llvm.ptr, %len: i64, %ms: f64) -> !llvm.ptr {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c32 = arith.constant 32 : i64
  %m1 = arith.constant -1 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  // the JSON, then "?(none)"
  %tl = arith.addi %len, %c8 : i64
  %t = llvm.call @realloc(%json, %tl) : (!llvm.ptr, i64) -> !llvm.ptr
  %suffix = llvm.mlir.addressof @k_suffix : !llvm.ptr
  %tend = func.call @off(%t, %len) : (!llvm.ptr, i64) -> !llvm.ptr
  %r0 = llvm.call @memcpy(%tend, %suffix, %c7) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
  %len1 = arith.addi %len, %c1 : i64
  %len7 = arith.addi %len, %c7 : i64
  %qmark = func.call @tw(%len, %len1) : (i64, i64) -> i64
  %none = func.call @tw(%len1, %len7) : (i64, i64) -> i64
  %empty = func.call @tw(%len, %len) : (i64, i64) -> i64
  %f = func.call @cx_scan(%t, %len) : (!llvm.ptr, i64) -> !llvm.ptr
  %bad = llvm.icmp "eq" %f, %null : !llvm.ptr
  %rootTag = scf.if %bad -> (i64) {
    scf.yield %m1 : i64
  } else {
    %tg = func.call @cx_tag(%f, %c0) : (!llvm.ptr, i64) -> i64
    scf.yield %tg : i64
  }
  %isObj = arith.cmpi eq, %rootTag, %c5 : i64
  %kopt = llvm.mlir.addressof @k_options : !llvm.ptr
  %opts = scf.if %isObj -> (i64) {
    %o = func.call @cx_member(%t, %f, %c0, %kopt, %c7) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
    scf.yield %o : i64
  } else {
    scf.yield %m1 : i64
  }
  %hasOpts = arith.cmpi sge, %opts, %c0 : i64
  %optsTag = scf.if %hasOpts -> (i64) {
    %tg = func.call @cx_tag(%f, %opts) : (!llvm.ptr, i64) -> i64
    scf.yield %tg : i64
  } else {
    scf.yield %m1 : i64
  }
  %isArr = arith.cmpi eq, %optsTag, %c6 : i64
  %result = scf.if %isArr -> (!llvm.ptr) {
    %c = func.call @corpus_rows(%t, %len, %f, %opts, %qmark, %none, %empty, %ms) : (!llvm.ptr, i64, !llvm.ptr, i64, i64, i64, i64, f64) -> !llvm.ptr
    scf.yield %c : !llvm.ptr
  } else {
    %whyp = llvm.mlir.addressof @why_p : !llvm.ptr
    %whyn = llvm.mlir.addressof @why_n : !llvm.ptr
    %m1n = llvm.mlir.addressof @k_notobject : !llvm.ptr
    %m2n = llvm.mlir.addressof @k_nooptions : !llvm.ptr
    %l35 = arith.constant 35 : i64
    %l29 = arith.constant 29 : i64
    %msg = arith.select %isObj, %m2n, %m1n : !llvm.ptr
    %ml = arith.select %isObj, %l29, %l35 : i64
    llvm.store %msg, %whyp : !llvm.ptr, !llvm.ptr
    llvm.store %ml, %whyn : i64, !llvm.ptr
    func.call @cx_free(%f) : (!llvm.ptr) -> ()
    llvm.call @free(%t) : (!llvm.ptr) -> ()
    scf.yield %null : !llvm.ptr
  }
  return %result : !llvm.ptr
}

// The Columns facet over the elements of row opts of the index h (columns.mlir's opt_members): for each element, the rows
// of its members path, valueShown, value, state, kind, declarations and description, or -1, as seven malloc'd i32
// arrays, written to out[0 ..< 7] (fresh buffers: their allocation is their data)
func.func @options_members(%h: !llvm.ptr, %opts: i64, %out: !llvm.ptr) {
  %one = arith.constant 1 : i32
  %i0 = arith.constant 0 : i32
  %i1 = arith.constant 1 : i32
  %i2 = arith.constant 2 : i32
  %i3 = arith.constant 3 : i32
  %d0 = func.call @cx_d(%h, %i0) : (!llvm.ptr, i32) -> !llvm.ptr
  %d1 = func.call @cx_d(%h, %i1) : (!llvm.ptr, i32) -> !llvm.ptr
  %d2 = func.call @cx_d(%h, %i2) : (!llvm.ptr, i32) -> !llvm.ptr
  %d3 = func.call @cx_d(%h, %i3) : (!llvm.ptr, i32) -> !llvm.ptr
  %td = func.call @cx_text(%h) : (!llvm.ptr) -> !llvm.ptr
  %res = llvm.alloca %one x !llvm.array<7 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>> : (i32) -> !llvm.ptr
  llvm.call @_mlir_ciface_opt_members(%res, %d0, %d1, %d2, %d3, %td, %opts) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> ()
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c7 = arith.constant 7 : i64
  scf.for %k = %c0 to %c7 step %c1 : i64 {
    %pk = llvm.getelementptr %res[0, %k, 0] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.array<7 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>>
    %col = llvm.load %pk : !llvm.ptr -> !llvm.ptr
    func.call @setp(%out, %k, %col) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  }
  return
}

// The cells of each option (columns.mlir's opt_cells over the members' table): its section, its value when it is shown
// (else -1), its state, its kind and its module, as five malloc'd arrays of n coordinates written to out[0 ..< 5]
// (fresh buffers: their allocation is their data)
func.func @options_cells(%h: !llvm.ptr, %members: !llvm.ptr, %n: i64, %qmark: i64, %none: i64, %empty: i64, %out: !llvm.ptr) {
  %one = arith.constant 1 : i32
  %i0 = arith.constant 0 : i32
  %i1 = arith.constant 1 : i32
  %i2 = arith.constant 2 : i32
  %i3 = arith.constant 3 : i32
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c5 = arith.constant 5 : i64
  %d0 = func.call @cx_d(%h, %i0) : (!llvm.ptr, i32) -> !llvm.ptr
  %d1 = func.call @cx_d(%h, %i1) : (!llvm.ptr, i32) -> !llvm.ptr
  %d2 = func.call @cx_d(%h, %i2) : (!llvm.ptr, i32) -> !llvm.ptr
  %d3 = func.call @cx_d(%h, %i3) : (!llvm.ptr, i32) -> !llvm.ptr
  %td = func.call @cx_text(%h) : (!llvm.ptr) -> !llvm.ptr
  // the members' columns 0 path  1 valueShown  2 value  3 state  4 kind  5 declarations, as descriptors
  %m = llvm.alloca %one x !llvm.array<6 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>> : (i32) -> !llvm.ptr
  %c6 = arith.constant 6 : i64
  scf.for %k = %c0 to %c6 step %c1 : i64 {
    %dk = llvm.getelementptr %m[0, %k] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.array<6 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>>
    %col = func.call @getp(%members, %k) : (!llvm.ptr, i64) -> !llvm.ptr
    func.call @view(%dk, %col, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  }
  %mp = llvm.getelementptr %m[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<6 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>>
  %ms = llvm.getelementptr %m[0, 1] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<6 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>>
  %mv = llvm.getelementptr %m[0, 2] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<6 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>>
  %mt = llvm.getelementptr %m[0, 3] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<6 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>>
  %mk = llvm.getelementptr %m[0, 4] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<6 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>>
  %md = llvm.getelementptr %m[0, 5] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<6 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>>
  %res = llvm.alloca %one x !llvm.array<5 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>> : (i32) -> !llvm.ptr
  llvm.call @_mlir_ciface_opt_cells(%res, %d0, %d1, %d2, %d3, %td, %mp, %ms, %mv, %mt, %mk, %md, %qmark, %none, %empty) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, i64) -> ()
  scf.for %k = %c0 to %c5 step %c1 : i64 {
    %pk = llvm.getelementptr %res[0, %k, 0] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.array<5 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>>
    %col = llvm.load %pk : !llvm.ptr -> !llvm.ptr
    func.call @setp(%out, %k, %col) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  }
  return
}

// The keys and what each row is searched by (columns.mlir's opt_text over the members path and description): the keys,
// each row's key, the search text, each row's place in it, written to out[0 ..< 4] (fresh buffers: their allocation is
// their data); the result is the length of the keys
func.func @options_text(%h: !llvm.ptr, %members: !llvm.ptr, %n: i64, %empty: i64, %out: !llvm.ptr) -> i64 {
  %one = arith.constant 1 : i32
  %i0 = arith.constant 0 : i32
  %i1 = arith.constant 1 : i32
  %i2 = arith.constant 2 : i32
  %i3 = arith.constant 3 : i32
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c4 = arith.constant 4 : i64
  %c6 = arith.constant 6 : i64
  %d0 = func.call @cx_d(%h, %i0) : (!llvm.ptr, i32) -> !llvm.ptr
  %d1 = func.call @cx_d(%h, %i1) : (!llvm.ptr, i32) -> !llvm.ptr
  %d2 = func.call @cx_d(%h, %i2) : (!llvm.ptr, i32) -> !llvm.ptr
  %d3 = func.call @cx_d(%h, %i3) : (!llvm.ptr, i32) -> !llvm.ptr
  %td = func.call @cx_text(%h) : (!llvm.ptr) -> !llvm.ptr
  // the members' columns 0 path and 6 description, as descriptors
  %m = llvm.alloca %one x !llvm.array<2 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>> : (i32) -> !llvm.ptr
  %mp = llvm.getelementptr %m[0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<2 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>>
  %md = llvm.getelementptr %m[0, 1] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<2 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>>
  %path = func.call @getp(%members, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %desc = func.call @getp(%members, %c6) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @view(%mp, %path, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  func.call @view(%md, %desc, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %res = llvm.alloca %one x !llvm.array<4 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>> : (i32) -> !llvm.ptr
  llvm.call @_mlir_ciface_opt_text(%res, %d0, %d1, %d2, %d3, %td, %mp, %md, %empty) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> ()
  scf.for %k = %c0 to %c4 step %c1 : i64 {
    %pk = llvm.getelementptr %res[0, %k, 0] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.array<4 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>>
    %buf = llvm.load %pk : !llvm.ptr -> !llvm.ptr
    func.call @setp(%out, %k, %buf) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  }
  %pn = llvm.getelementptr %res[0, 0, 3, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.array<4 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>>
  %keysLen = llvm.load %pn : !llvm.ptr -> i64
  return %keysLen : i64
}

func.func @corpus_rows(%t: !llvm.ptr, %len: i64, %f: !llvm.ptr, %opts: i64, %qmark: i64, %none: i64, %empty: i64, %ms: f64) -> !llvm.ptr {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c8 = arith.constant 8 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %c12 = arith.constant 12 : i64
  %c32 = arith.constant 32 : i64
  %m1 = arith.constant -1 : i64
  %c = llvm.call @calloc(%c32, %c8) : (i64, i64) -> !llvm.ptr
  %n = func.call @cx_nkids(%f, %opts) : (!llvm.ptr, i64) -> i64
  %n1 = arith.maxsi %n, %c1 : i64
  // each option's members, by name: 0 path  1 valueShown  2 value  3 state  4 kind  5 declarations  6 description
  %members = llvm.call @calloc(%c8, %c8) : (i64, i64) -> !llvm.ptr
  func.call @options_members(%f, %opts, %members) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @setp(%c, %c0, %t) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @seti(%c, %c1, %len) : (!llvm.ptr, i64, i64) -> ()
  %k2 = arith.constant 2 : i64
  func.call @setp(%c, %k2, %f) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @seti(%c, %c3, %n) : (!llvm.ptr, i64, i64) -> ()
  %obj = llvm.call @calloc(%n1, %c8) : (i64, i64) -> !llvm.ptr
  // the cells: 0 section  1 value (when shown)  2 state  3 kind  4 module
  %cells = llvm.call @calloc(%c8, %c8) : (i64, i64) -> !llvm.ptr
  func.call @options_cells(%f, %members, %n, %qmark, %none, %empty, %cells) : (!llvm.ptr, !llvm.ptr, i64, i64, i64, i64, !llvm.ptr) -> ()
  %cell0 = func.call @getp(%cells, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %val = func.call @getp(%cells, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %k2c = arith.constant 2 : i64
  %st = func.call @getp(%cells, %k2c) : (!llvm.ptr, i64) -> !llvm.ptr
  %cell1 = func.call @getp(%cells, %c3) : (!llvm.ptr, i64) -> !llvm.ptr
  %cell3 = func.call @getp(%cells, %c4) : (!llvm.ptr, i64) -> !llvm.ptr
  llvm.call @free(%cells) : (!llvm.ptr) -> ()
  func.call @setp(%c, %c4, %obj) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @setp(%c, %c5, %val) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @setp(%c, %c6, %st) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  // each option's element
  scf.for %i = %c0 to %n step %c1 : i64 {
    %o = func.call @cx_kid(%f, %opts, %i) : (!llvm.ptr, i64, i64) -> i64
    func.call @st64(%obj, %i, %o) : (!llvm.ptr, i64, i64) -> ()
  }
  // the keys, each row's path with its segments joined by '.', and what a row is searched by, its key and its description
  // with their escapes read, lower-cased (columns.mlir's opt_text): 0 keys  1 key[n]  2 hay  3 hayAt[n]
  %texts = llvm.call @calloc(%c8, %c8) : (i64, i64) -> !llvm.ptr
  %keysLen = func.call @options_text(%f, %members, %n, %empty, %texts) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %keys = func.call @getp(%texts, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %key = func.call @getp(%texts, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %k2t = arith.constant 2 : i64
  %hay = func.call @getp(%texts, %k2t) : (!llvm.ptr, i64) -> !llvm.ptr
  %hayAt = func.call @getp(%texts, %c3) : (!llvm.ptr, i64) -> !llvm.ptr
  llvm.call @free(%texts) : (!llvm.ptr) -> ()
  %k7 = arith.constant 7 : i64
  func.call @setp(%c, %k7, %keys) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %k8 = arith.constant 8 : i64
  func.call @setp(%c, %k8, %key) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %k9 = arith.constant 9 : i64
  func.call @setp(%c, %k9, %hay) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @setp(%c, %c10, %hayAt) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %k29 = arith.constant 29 : i64
  func.call @seti(%c, %k29, %keysLen) : (!llvm.ptr, i64, i64) -> ()
  %c7m = arith.constant 7 : i64
  scf.for %k = %c0 to %c7m step %c1 : i64 {
    %col = func.call @getp(%members, %k) : (!llvm.ptr, i64) -> !llvm.ptr
    llvm.call @free(%col) : (!llvm.ptr) -> ()
  }
  llvm.call @free(%members) : (!llvm.ptr) -> ()
  // the coded columns: codes in the order of the names, so a name keeps its place as the counts change; the pieces are
  // in the JSON and the 7 bytes of "?(none)" after it
  %c7 = arith.constant 7 : i64
  %tn = arith.addi %len, %c7 : i64
  func.call @code_column(%c, %c0, %t, %tn, %cell0, %n) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @code_column(%c, %c1, %t, %tn, %cell1, %n) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> ()
  %k2b = arith.constant 2 : i64
  func.call @code_column(%c, %k2b, %t, %tn, %st, %n) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> ()
  func.call @code_column(%c, %c3, %t, %tn, %cell3, %n) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> ()
  llvm.call @free(%cell0) : (!llvm.ptr) -> ()
  llvm.call @free(%cell1) : (!llvm.ptr) -> ()
  llvm.call @free(%cell3) : (!llvm.ptr) -> ()
  %k15 = arith.constant 15 : i64
  %k16 = arith.constant 16 : i64
  %whatif = llvm.call @calloc(%n1, %c4) : (i64, i64) -> !llvm.ptr
  %match = llvm.call @calloc(%n1, %c4) : (i64, i64) -> !llvm.ptr
  scf.for %i = %c0 to %n step %c1 : i64 {
    func.call @st32(%match, %i, %c1) : (!llvm.ptr, i64, i64) -> ()
  }
  func.call @setp(%c, %k15, %whatif) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @setp(%c, %k16, %match) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  // etc
  %ketc = llvm.mlir.addressof @k_etc : !llvm.ptr
  %er = func.call @cx_member(%t, %f, %c0, %ketc, %c3) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
  %hasE = arith.cmpi sge, %er, %c0 : i64
  %etcRow = scf.if %hasE -> (i64) {
    %et = func.call @cx_tag(%f, %er) : (!llvm.ptr, i64) -> i64
    %isO = arith.cmpi eq, %et, %c5 : i64
    %r = arith.select %isO, %er, %m1 : i64
    scf.yield %r : i64
  } else {
    scf.yield %m1 : i64
  }
  %k25 = arith.constant 25 : i64
  func.call @seti(%c, %k25, %etcRow) : (!llvm.ptr, i64, i64) -> ()
  %msBits = arith.bitcast %ms : f64 to i64
  %k26 = arith.constant 26 : i64
  func.call @seti(%c, %k26, %msBits) : (!llvm.ptr, i64, i64) -> ()
  // the rows in the order of their keys, for the join with another corpus
  %order = func.call @sorted_rows(%n, %keys, %keysLen, %key) : (i64, !llvm.ptr, i64, !llvm.ptr) -> !llvm.ptr
  %k27 = arith.constant 27 : i64
  func.call @setp(%c, %k27, %order) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %baseOf = llvm.call @calloc(%n1, %c4) : (i64, i64) -> !llvm.ptr
  scf.for %i = %c0 to %n step %c1 : i64 {
    func.call @st32(%baseOf, %i, %m1) : (!llvm.ptr, i64, i64) -> ()
  }
  %k28 = arith.constant 28 : i64
  func.call @setp(%c, %k28, %baseOf) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  return %c : !llvm.ptr
}

// column k (0..3) from the cells (n pieces of the tn bytes at t): columns.mlir's col_code, each row's code and each code's
// name; both buffers are malloc'd, and fresh (their allocation is their data)
func.func @code_column(%c: !llvm.ptr, %k: i64, %t: !llvm.ptr, %tn: i64, %cells: !llvm.ptr, %n: i64) {
  %one = arith.constant 1 : i32
  %c11 = arith.constant 11 : i64
  %c17 = arith.constant 17 : i64
  %c21 = arith.constant 21 : i64
  %td = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%td, %t, %tn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %pd = llvm.alloca %one x !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> : (i32) -> !llvm.ptr
  func.call @view(%pd, %cells, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %res = llvm.alloca %one x !llvm.struct<(struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>)> : (i32) -> !llvm.ptr
  llvm.call @_mlir_ciface_col_code(%res, %td, %pd) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  %pc = llvm.getelementptr %res[0, 0, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>)>
  %col = llvm.load %pc : !llvm.ptr -> !llvm.ptr
  %pdict = llvm.getelementptr %res[0, 1, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>)>
  %dict = llvm.load %pdict : !llvm.ptr -> !llvm.ptr
  %pcount = llvm.getelementptr %res[0, 1, 3, 0] : (!llvm.ptr) -> !llvm.ptr, !llvm.struct<(struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>)>
  %count = llvm.load %pcount : !llvm.ptr -> i64
  %colSlot = arith.addi %c11, %k : i64
  %dictSlot = arith.addi %c17, %k : i64
  %countSlot = arith.addi %c21, %k : i64
  func.call @setp(%c, %colSlot, %col) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @setp(%c, %dictSlot, %dict) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @seti(%c, %countSlot, %count) : (!llvm.ptr, i64, i64) -> ()
  return
}

func.func @corpus_free(%c: !llvm.ptr) {
  %null = llvm.mlir.zero : !llvm.ptr
  %isnull = llvm.icmp "eq" %c, %null : !llvm.ptr
  scf.if %isnull {
  } else {
    %c0 = arith.constant 0 : i64
    %c2 = arith.constant 2 : i64
    %t = func.call @getp(%c, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
    llvm.call @free(%t) : (!llvm.ptr) -> ()
    %f = func.call @getp(%c, %c2) : (!llvm.ptr, i64) -> !llvm.ptr
    func.call @cx_free(%f) : (!llvm.ptr) -> ()
    // the arrays and series: slots 4..20, 27, 28
    %c1 = arith.constant 1 : i64
    %c4 = arith.constant 4 : i64
    %c21 = arith.constant 21 : i64
    scf.for %k = %c4 to %c21 step %c1 : i64 {
      %p = func.call @getp(%c, %k) : (!llvm.ptr, i64) -> !llvm.ptr
      llvm.call @free(%p) : (!llvm.ptr) -> ()
    }
    %k27 = arith.constant 27 : i64
    %k28 = arith.constant 28 : i64
    %o = func.call @getp(%c, %k27) : (!llvm.ptr, i64) -> !llvm.ptr
    llvm.call @free(%o) : (!llvm.ptr) -> ()
    %b = func.call @getp(%c, %k28) : (!llvm.ptr, i64) -> !llvm.ptr
    llvm.call @free(%b) : (!llvm.ptr) -> ()
    llvm.call @free(%c) : (!llvm.ptr) -> ()
  }
  return
}

// ---- the join of two corpora by key: what the overlay changed

// cur's rows whose value or state differs from base's row of the same key, or that base lacks, marked in the whatif
// column; each row's base row in baseOf: columns.mlir's mark, a KeyedJoin with base's key order as its index.
func.func @corpus_mark(%cur: !llvm.ptr, %base: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c15 = arith.constant 15 : i64
  %c27 = arith.constant 27 : i64
  %c28 = arith.constant 28 : i64
  %c29 = arith.constant 29 : i64
  %c2i = arith.constant 2 : i64
  %c4i = arith.constant 4 : i64
  %c9i = arith.constant 9 : i64
  %c10i = arith.constant 10 : i64
  %c11i = arith.constant 11 : i64
  %c12i = arith.constant 12 : i64
  // the views: the descriptors of the texts and arrays mark reads, and of the two it fills
  %v = llvm.alloca %c1 x !llvm.array<13 x struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>> : (i64) -> !llvm.ptr
  %nc = func.call @geti(%cur, %c3) : (!llvm.ptr, i64) -> i64
  %nb = func.call @geti(%base, %c3) : (!llvm.ptr, i64) -> i64
  %d0 = func.call @view_at(%v, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %keysC = func.call @getp(%cur, %c7) : (!llvm.ptr, i64) -> !llvm.ptr
  %keysCn = func.call @geti(%cur, %c29) : (!llvm.ptr, i64) -> i64
  func.call @view(%d0, %keysC, %keysCn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %d1 = func.call @view_at(%v, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %keyC = func.call @getp(%cur, %c8) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @view(%d1, %keyC, %nc) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %d2 = func.call @view_at(%v, %c2i) : (!llvm.ptr, i64) -> !llvm.ptr
  %tc = func.call @getp(%cur, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %tcn = func.call @text_len(%cur) : (!llvm.ptr) -> i64
  func.call @view(%d2, %tc, %tcn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %d3 = func.call @view_at(%v, %c3) : (!llvm.ptr, i64) -> !llvm.ptr
  %valC = func.call @getp(%cur, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @view(%d3, %valC, %nc) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %d4 = func.call @view_at(%v, %c4i) : (!llvm.ptr, i64) -> !llvm.ptr
  %stC = func.call @getp(%cur, %c6) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @view(%d4, %stC, %nc) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %d5 = func.call @view_at(%v, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  %keysB = func.call @getp(%base, %c7) : (!llvm.ptr, i64) -> !llvm.ptr
  %keysBn = func.call @geti(%base, %c29) : (!llvm.ptr, i64) -> i64
  func.call @view(%d5, %keysB, %keysBn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %d6 = func.call @view_at(%v, %c6) : (!llvm.ptr, i64) -> !llvm.ptr
  %keyB = func.call @getp(%base, %c8) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @view(%d6, %keyB, %nb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %d7 = func.call @view_at(%v, %c7) : (!llvm.ptr, i64) -> !llvm.ptr
  %ordB = func.call @getp(%base, %c27) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @view(%d7, %ordB, %nb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %d8 = func.call @view_at(%v, %c8) : (!llvm.ptr, i64) -> !llvm.ptr
  %tb = func.call @getp(%base, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %tbn = func.call @text_len(%base) : (!llvm.ptr) -> i64
  func.call @view(%d8, %tb, %tbn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %d9 = func.call @view_at(%v, %c9i) : (!llvm.ptr, i64) -> !llvm.ptr
  %valB = func.call @getp(%base, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @view(%d9, %valB, %nb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %d10 = func.call @view_at(%v, %c10i) : (!llvm.ptr, i64) -> !llvm.ptr
  %stB = func.call @getp(%base, %c6) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @view(%d10, %stB, %nb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %d11 = func.call @view_at(%v, %c11i) : (!llvm.ptr, i64) -> !llvm.ptr
  %baseOf = func.call @getp(%cur, %c28) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @view(%d11, %baseOf, %nc) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %d12 = func.call @view_at(%v, %c12i) : (!llvm.ptr, i64) -> !llvm.ptr
  %whatif = func.call @getp(%cur, %c15) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @view(%d12, %whatif, %nc) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  llvm.call @_mlir_ciface_mark(%d0, %d1, %d2, %d3, %d4, %d5, %d6, %d7, %d8, %d9, %d10, %d11, %d12) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  return
}

// the k-th of an array of descriptors
func.func @view_at(%v: !llvm.ptr, %k: i64) -> !llvm.ptr {
  %p = llvm.getelementptr %v[%k] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
  return %p : !llvm.ptr
}

// the length of a corpus's text: the JSON, and the 7 bytes of "?(none)" after it
func.func @text_len(%c: !llvm.ptr) -> i64 {
  %c1 = arith.constant 1 : i64
  %c7 = arith.constant 7 : i64
  %len = func.call @geti(%c, %c1) : (!llvm.ptr, i64) -> i64
  %n = arith.addi %len, %c7 : i64
  return %n : i64
}
