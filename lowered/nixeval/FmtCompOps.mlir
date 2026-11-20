// The composition residue of lib/Eval/Formats.cpp, hollowed out of the XML printer and fromTOML's array close:
// the attribute rows' dedup scan and their sort into the tag's key/value windows (the room the tag needs), the
// formals' name windows sorted and emitted one tag a name, and an open TOML array's elements drained into the
// list's cells.  The byte emission of a tag line stays XmlOps.mlir's nixev_ts_xml_tag; the recursion/forcing of
// toXML, the element stack and the TOML tables stay in the C++ bridge.  Lowered by lib/CMakeLists.txt's
// mlnix_lower_trikeshed into NixEval.
//
// nixev_ts_xml_find(rows, stride, n, k): the first row whose NUL-terminated key equals k (unsigned byte order,
//   as strcmp), or -1.  rows is the bridge's Attrs::Row array: key ptr @0, the value Text @8 (data ptr @8, u32
//   count @16); stride is sizeof(Row).
// nixev_ts_xml_prep(rows, stride, n, depth, nn, keys, vals): the rows sorted by key (trikeshed.sorted, stable),
//   their keys and values written as composite::Chars windows (u32 count @0, ptr @8) in sorted order, and the
//   room the tag line needs returned: 2*depth + 2 + nn + 4, plus 4 + key + 6 a value byte a row.
// nixev_ts_xml_formals(doc, wins, n): wins is n {ptr, len} windows (llvm::StringRef cells); sorted by the bytes
//   (unsigned), each calls nixev_xml_formal(doc, wins, k) once, in order -- the bridge emits one <attr> tag.
// nixev_ts_toml_cells(elems, n, into): n Value* cells (pointer bits, i64) drained once into the list's elems.
!text = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

func.func private @strlen(!llvm.ptr) -> i64
func.func private @nixev_xml_formal(!llvm.ptr, !llvm.ptr, i64)

// the descriptor of n cells at p (a struct, not a memref: returning it allocates nothing and clones nothing)
func.func private @fc_desc8(%p: !llvm.ptr, %n: i64) -> !d {
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
func.func private @fc_desc64(%p: !llvm.ptr, %n: i64) -> !d {
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

// two NUL-terminated keys in unsigned byte order (strcmp's): the slices live and die in this helper
func.func private @fc_key_cmp(%a: !llvm.ptr, %b: !llvm.ptr) -> i32 {
  %zi = arith.constant 0 : index
  %na = func.call @strlen(%a) : (!llvm.ptr) -> i64
  %nb = func.call @strlen(%b) : (!llvm.ptr) -> i64
  %da = func.call @fc_desc8(%a, %na) : (!llvm.ptr, i64) -> !d
  %ma = builtin.unrealized_conversion_cast %da : !d to !m8
  %sa = builtin.unrealized_conversion_cast %ma : !m8 to !text
  %nai = arith.index_cast %na : i64 to index
  %va = trikeshed.slice %sa[%zi, %nai] : !text -> !text
  %db = func.call @fc_desc8(%b, %nb) : (!llvm.ptr, i64) -> !d
  %mb = builtin.unrealized_conversion_cast %db : !d to !m8
  %sb = builtin.unrealized_conversion_cast %mb : !m8 to !text
  %nbi = arith.index_cast %nb : i64 to index
  %vb = trikeshed.slice %sb[%zi, %nbi] : !text -> !text
  %c = trikeshed.compare %va, %vb unsigned : !text, !text
  return %c : i32
}

// two {ptr, len} windows at wins + 16i, in unsigned byte order (lessChars')
func.func private @fc_win_cmp(%wins: !llvm.ptr, %a: i64, %b: i64) -> i32 {
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %zi = arith.constant 0 : index
  %oa = arith.muli %a, %c16 : i64
  %pa = llvm.getelementptr %wins[%oa] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %dap = llvm.load %pa : !llvm.ptr -> !llvm.ptr
  %lap = llvm.getelementptr %pa[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %na = llvm.load %lap : !llvm.ptr -> i64
  %ob = arith.muli %b, %c16 : i64
  %pb = llvm.getelementptr %wins[%ob] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %dbp = llvm.load %pb : !llvm.ptr -> !llvm.ptr
  %lbp = llvm.getelementptr %pb[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %nb = llvm.load %lbp : !llvm.ptr -> i64
  %da = func.call @fc_desc8(%dap, %na) : (!llvm.ptr, i64) -> !d
  %ma = builtin.unrealized_conversion_cast %da : !d to !m8
  %sa = builtin.unrealized_conversion_cast %ma : !m8 to !text
  %nai = arith.index_cast %na : i64 to index
  %va = trikeshed.slice %sa[%zi, %nai] : !text -> !text
  %db = func.call @fc_desc8(%dbp, %nb) : (!llvm.ptr, i64) -> !d
  %mb = builtin.unrealized_conversion_cast %db : !d to !m8
  %sb = builtin.unrealized_conversion_cast %mb : !m8 to !text
  %nbi = arith.index_cast %nb : i64 to index
  %vb = trikeshed.slice %sb[%zi, %nbi] : !text -> !text
  %c = trikeshed.compare %va, %vb unsigned : !text, !text
  return %c : i32
}

// the first row whose key equals k, or -1: the scan stops at the first match, as the C++ loop returned
func.func @nixev_ts_xml_find(%rows: !llvm.ptr, %stride: i64, %n: i64, %k: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %neg1 = arith.constant -1 : i64
  %zi = arith.constant 0 : index
  %one = arith.constant 1 : index
  %ni = arith.index_cast %n : i64 to index
  %w:2 = scf.while (%i = %zi, %res = %neg1) : (index, i64) -> (index, i64) {
    %in = arith.cmpi ult, %i, %ni : index
    %miss = arith.cmpi slt, %res, %c0 : i64
    %go = arith.andi %in, %miss : i1
    scf.condition(%go) %i, %res : index, i64
  } do {
  ^bb0(%i: index, %res: i64):
    %i64 = arith.index_cast %i : index to i64
    %off = arith.muli %i64, %stride : i64
    %rp = llvm.getelementptr %rows[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %kp = llvm.load %rp : !llvm.ptr -> !llvm.ptr
    %c = func.call @fc_key_cmp(%kp, %k) : (!llvm.ptr, !llvm.ptr) -> i32
    %z32 = arith.constant 0 : i32
    %eq = arith.cmpi eq, %c, %z32 : i32
    %nres = arith.select %eq, %i64, %res : i64
    %ni2 = arith.addi %i, %one : index
    scf.yield %ni2, %nres : index, i64
  }
  return %w#1 : i64
}

// the rows sorted by key, their windows written in sorted order, the tag's room returned
func.func @nixev_ts_xml_prep(%rows: !llvm.ptr, %stride: i64, %n: i64, %depth: i64, %nn: i64,
                             %keys: !llvm.ptr, %vals: !llvm.ptr) -> i64 {
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c6 = arith.constant 6 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %zi = arith.constant 0 : index
  %one = arith.constant 1 : index
  %ni = arith.index_cast %n : i64 to index
  %idx = trikeshed.series %ni : !s64 {
  ^bb0(%q: index):
    %q64 = arith.index_cast %q : index to i64
    trikeshed.yield %q64 : i64
  }
  %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
  ^bb0(%a: i64, %b: i64):
    %oa = arith.muli %a, %stride : i64
    %pa = llvm.getelementptr %rows[%oa] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %ka = llvm.load %pa : !llvm.ptr -> !llvm.ptr
    %ob = arith.muli %b, %stride : i64
    %pb = llvm.getelementptr %rows[%ob] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %kb = llvm.load %pb : !llvm.ptr -> !llvm.ptr
    %c = func.call @fc_key_cmp(%ka, %kb) : (!llvm.ptr, !llvm.ptr) -> i32
    trikeshed.yield %c : i32
  }
  // the base room: 2 a depth, 2 the prefix, the name, 4 the suffix
  %d2 = arith.muli %depth, %c2 : i64
  %t1 = arith.addi %d2, %c2 : i64
  %t2 = arith.addi %t1, %nn : i64
  %base = arith.addi %t2, %c4 : i64
  %room = scf.for %j = %zi to %ni step %one iter_args(%rm = %base) -> (i64) {
    %e = trikeshed.at %srt[%j] : !s64, index -> i64
    %off = arith.muli %e, %stride : i64
    %rp = llvm.getelementptr %rows[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %kp = llvm.load %rp : !llvm.ptr -> !llvm.ptr
    %kn = func.call @strlen(%kp) : (!llvm.ptr) -> i64
    %vpp = llvm.getelementptr %rp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %vp = llvm.load %vpp : !llvm.ptr -> !llvm.ptr
    %vnp = llvm.getelementptr %rp[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %vn32 = llvm.load %vnp : !llvm.ptr -> i32
    %vn = llvm.zext %vn32 : i32 to i64
    // the key and value windows at keys/vals + 16j (Chars: u32 count @0, ptr @8)
    %j64 = arith.index_cast %j : index to i64
    %jo = arith.muli %j64, %c16 : i64
    %k0 = llvm.getelementptr %keys[%jo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %kn, %k0 : i64, !llvm.ptr
    %k1 = llvm.getelementptr %k0[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %kp, %k1 : !llvm.ptr, !llvm.ptr
    %v0 = llvm.getelementptr %vals[%jo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %vn, %v0 : i64, !llvm.ptr
    %v1 = llvm.getelementptr %v0[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %vp, %v1 : !llvm.ptr, !llvm.ptr
    // 4 + the key + 6 a value byte
    %v6 = arith.muli %vn, %c6 : i64
    %s1 = arith.addi %kn, %v6 : i64
    %s2 = arith.addi %s1, %c4 : i64
    %nrm = arith.addi %rm, %s2 : i64
    scf.yield %nrm : i64
  }
  return %room : i64
}

// the formals' windows sorted by their bytes, one callback a name in sorted order (the emission is the bridge's)
func.func @nixev_ts_xml_formals(%doc: !llvm.ptr, %wins: !llvm.ptr, %n: i64) {
  %zi = arith.constant 0 : index
  %one = arith.constant 1 : index
  %ni = arith.index_cast %n : i64 to index
  %idx = trikeshed.series %ni : !s64 {
  ^bb0(%q: index):
    %q64 = arith.index_cast %q : index to i64
    trikeshed.yield %q64 : i64
  }
  %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
  ^bb0(%a: i64, %b: i64):
    %c = func.call @fc_win_cmp(%wins, %a, %b) : (!llvm.ptr, i64, i64) -> i32
    trikeshed.yield %c : i32
  }
  scf.for %j = %zi to %ni step %one {
    %e = trikeshed.at %srt[%j] : !s64, index -> i64
    func.call @nixev_xml_formal(%doc, %wins, %e) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  }
  return
}

// an open TOML array's elements: the window of Value* bits drained once into the list's cells
func.func @nixev_ts_toml_cells(%elems: !llvm.ptr, %n: i64, %into: !llvm.ptr) {
  %sd = func.call @fc_desc64(%elems, %n) : (!llvm.ptr, i64) -> !d
  %sm = builtin.unrealized_conversion_cast %sd : !d to !m64
  %ss = builtin.unrealized_conversion_cast %sm : !m64 to !s64
  %id = func.call @fc_desc64(%into, %n) : (!llvm.ptr, i64) -> !d
  %im = builtin.unrealized_conversion_cast %id : !d to !m64
  %end = trikeshed.drain %ss, %im : !s64, !m64 -> index
  return
}
