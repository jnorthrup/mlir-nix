// builtins.fromTOML's tables, hollowed out of lib/Eval/Formats.cpp (TomlParser's setKey / header / deliver / toValue and
// the scan's event handler nixev_toml_ev are gone): TomlScan.mlir's events, in order, build the document's tables here --
// a key's parts gathered, a value delivered to the open array or to the open table's dotted key (the tables on the way
// made or entered, a key defined twice refused), a [header] or [[header]] navigating from the root (into the last table
// of an array of tables), an array's elements drained into its list, an inline table's node made into a set when it
// closes -- and nixev_ts_toml_value makes the root's set, the recursion func.call.  The errors are found at the event
// that finds them, so one here still comes before a lexical error later in the text.  Lowered by lib/CMakeLists.txt's
// mlnix_lower_trikeshed into NixEval.
//
// The record (i64 words, the bridge's): 0 the bridge (TomlParser*, for the callbacks), 1 the frames (3 i64 a frame:
// node or 0 for an array, the elems and keys counts when it opened; frame 0 is the current [table]), 2 their count,
// 3 the elems (Value* bits), 4 their count, 5 the key parts (2 i64: ptr, len), 6 their count, 7 the latest event's
// line, 8 the root node.  The bridge's room for each is the input's length + 2 (a frame, an element and a key part each
// take a byte of the input at least).
// A node (the bridge's TomlNode) starts with three words: kind @0 (0 table, 1 array of tables, 2 leaf), defined @8
// (named by a [header]), the leaf's Value* @16.  A table's rows (composite::TextTable's Row, 24 bytes): key ptr @0,
// u32 len @8, node @16.
//
// The callbacks (Formats.cpp) keep the tables' storage and the evaluator: nixev_tt_child (the child slot of a table
// for a key, 0 when none yet: holds until the table's next new key), nixev_tt_make (a new table node), nixev_tt_push /
// nixev_tt_back / nixev_tt_kids (an array's nodes), nixev_tt_rows (a table's rows), nixev_tt_fail (the message, thrown:
// 29 cannot redefine, 30 duplicate key, 31 table defined twice), nixev_tt_value (a string, int, float, bool or
// timestamp's Value), nixev_tt_list (a list Value of n cells), nixev_tt_sym (a key's Symbol, made in the order the
// old toValue made them), nixev_tt_scratch (2n i64 that outlive the children's recursion), nixev_tt_attrs (the set).
!s64 = !trikeshed.series<i64>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

func.func private @nixev_tt_child(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
func.func private @nixev_tt_make(!llvm.ptr) -> !llvm.ptr
func.func private @nixev_tt_push(!llvm.ptr, !llvm.ptr)
func.func private @nixev_tt_back(!llvm.ptr) -> !llvm.ptr
func.func private @nixev_tt_kids(!llvm.ptr, !llvm.ptr) -> !llvm.ptr
func.func private @nixev_tt_rows(!llvm.ptr, !llvm.ptr) -> !llvm.ptr
func.func private @nixev_tt_fail(i64, i64, !llvm.ptr, i64)
func.func private @nixev_tt_value(!llvm.ptr, i64, !llvm.ptr, i64) -> !llvm.ptr
func.func private @nixev_tt_list(!llvm.ptr, i64) -> !llvm.ptr
func.func private @nixev_tt_sym(!llvm.ptr, !llvm.ptr, i64) -> i64
func.func private @nixev_tt_scratch(!llvm.ptr, i64) -> !llvm.ptr
func.func private @nixev_tt_attrs(!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr

// word k of a record / cell array
func.func private @tt_rd(%s: !llvm.ptr, %k: i64) -> i64 {
  %q = llvm.getelementptr %s[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %q : !llvm.ptr -> i64
  return %v : i64
}
func.func private @tt_wr(%s: !llvm.ptr, %k: i64, %v: i64) {
  %q = llvm.getelementptr %s[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %q : i64, !llvm.ptr
  return
}
func.func private @tt_rp(%s: !llvm.ptr, %k: i64) -> !llvm.ptr {
  %q = llvm.getelementptr %s[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %q : !llvm.ptr -> !llvm.ptr
  return %v : !llvm.ptr
}
func.func private @tt_wp(%s: !llvm.ptr, %k: i64, %v: !llvm.ptr) {
  %q = llvm.getelementptr %s[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %q : !llvm.ptr, !llvm.ptr
  return
}
func.func private @tt_desc64(%p: !llvm.ptr, %n: i64) -> !d {
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

// the child slot of table t for key part i
func.func private @tt_child(%tt: !llvm.ptr, %t: !llvm.ptr, %i: i64) -> !llvm.ptr {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c5 = arith.constant 5 : i64
  %P = func.call @tt_rp(%tt, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %keys = func.call @tt_rp(%tt, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  %o = arith.muli %i, %c2 : i64
  %kp = func.call @tt_rp(%keys, %o) : (!llvm.ptr, i64) -> !llvm.ptr
  %o1 = arith.addi %o, %c1 : i64
  %kn = func.call @tt_rd(%keys, %o1) : (!llvm.ptr, i64) -> i64
  %slot = func.call @nixev_tt_child(%P, %t, %kp, %kn) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
  return %slot : !llvm.ptr
}

// the error `code` naming key part i, at the latest event's line (thrown by the callback)
func.func private @tt_fail(%tt: !llvm.ptr, %code: i64, %i: i64) {
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c5 = arith.constant 5 : i64
  %c7 = arith.constant 7 : i64
  %keys = func.call @tt_rp(%tt, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  %o = arith.muli %i, %c2 : i64
  %kp = func.call @tt_rp(%keys, %o) : (!llvm.ptr, i64) -> !llvm.ptr
  %o1 = arith.addi %o, %c1 : i64
  %kn = func.call @tt_rd(%keys, %o1) : (!llvm.ptr, i64) -> i64
  %line = func.call @tt_rd(%tt, %c7) : (!llvm.ptr, i64) -> i64
  func.call @nixev_tt_fail(%code, %line, %kp, %kn) : (i64, i64, !llvm.ptr, i64) -> ()
  return
}

// a slot's node, made (a table) when the slot is empty
func.func private @tt_made(%tt: !llvm.ptr, %slot: !llvm.ptr) -> !llvm.ptr {
  %c0 = arith.constant 0 : i64
  %n = llvm.load %slot : !llvm.ptr -> !llvm.ptr
  %nb = llvm.ptrtoint %n : !llvm.ptr to i64
  %none = arith.cmpi eq, %nb, %c0 : i64
  %r = scf.if %none -> (!llvm.ptr) {
    %P = func.call @tt_rp(%tt, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
    %m = func.call @nixev_tt_make(%P) : (!llvm.ptr) -> !llvm.ptr
    llvm.store %m, %slot : !llvm.ptr, !llvm.ptr
    scf.yield %m : !llvm.ptr
  } else {
    scf.yield %n : !llvm.ptr
  }
  return %r : !llvm.ptr
}

// setKey: the key parts from `from` name v in table tbl, the tables on the way made or entered (a leaf or an array
// there cannot be redefined: 29); the last part must be new (30)
func.func private @tt_setkey(%tt: !llvm.ptr, %tbl: !llvm.ptr, %from: i64, %v: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c6 = arith.constant 6 : i64
  %c16 = arith.constant 16 : i64
  %e29 = arith.constant 29 : i64
  %e30 = arith.constant 30 : i64
  %nk = func.call @tt_rd(%tt, %c6) : (!llvm.ptr, i64) -> i64
  %last = arith.subi %nk, %c1 : i64
  %fi = arith.index_cast %from : i64 to index
  %li = arith.index_cast %last : i64 to index
  %one = arith.constant 1 : index
  %cur = scf.for %i = %fi to %li step %one iter_args(%t = %tbl) -> (!llvm.ptr) {
    %i64 = arith.index_cast %i : index to i64
    %slot = func.call @tt_child(%tt, %t, %i64) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
    %old = llvm.load %slot : !llvm.ptr -> !llvm.ptr
    %ob = llvm.ptrtoint %old : !llvm.ptr to i64
    %fresh = arith.cmpi eq, %ob, %c0 : i64
    scf.if %fresh {
    } else {
      %kind = llvm.load %old : !llvm.ptr -> i64
      %notTable = arith.cmpi ne, %kind, %c0 : i64
      scf.if %notTable {
        func.call @tt_fail(%tt, %e29, %i64) : (!llvm.ptr, i64, i64) -> ()
      }
    }
    %n = func.call @tt_made(%tt, %slot) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
    scf.yield %n : !llvm.ptr
  }
  %slot = func.call @tt_child(%tt, %cur, %last) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
  %old = llvm.load %slot : !llvm.ptr -> !llvm.ptr
  %ob = llvm.ptrtoint %old : !llvm.ptr to i64
  %taken = arith.cmpi ne, %ob, %c0 : i64
  scf.if %taken {
    func.call @tt_fail(%tt, %e30, %last) : (!llvm.ptr, i64, i64) -> ()
  }
  %P = func.call @tt_rp(%tt, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %leaf = func.call @nixev_tt_make(%P) : (!llvm.ptr) -> !llvm.ptr
  llvm.store %leaf, %slot : !llvm.ptr, !llvm.ptr
  llvm.store %c2, %leaf : i64, !llvm.ptr
  %lp = llvm.getelementptr %leaf[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %v, %lp : !llvm.ptr, !llvm.ptr
  return
}

// a [header] (aot 0) or [[header]] (aot 1): the parts but the last navigate from the root (into an array's last
// table; a leaf there: 29), the last names the table that becomes frame 0's: a new table of the array of tables it
// names (anything else there: 29), or a table not defined by a header yet (a leaf, an array or a defined one: 31)
func.func private @tt_header(%tt: !llvm.ptr, %aot: i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c6 = arith.constant 6 : i64
  %c8 = arith.constant 8 : i64
  %e29 = arith.constant 29 : i64
  %e31 = arith.constant 31 : i64
  %zi = arith.constant 0 : index
  %one = arith.constant 1 : index
  %nk = func.call @tt_rd(%tt, %c6) : (!llvm.ptr, i64) -> i64
  %last = arith.subi %nk, %c1 : i64
  %li = arith.index_cast %last : i64 to index
  %root = func.call @tt_rp(%tt, %c8) : (!llvm.ptr, i64) -> !llvm.ptr
  %t = scf.for %i = %zi to %li step %one iter_args(%cur = %root) -> (!llvm.ptr) {
    %i64 = arith.index_cast %i : index to i64
    %slot = func.call @tt_child(%tt, %cur, %i64) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
    %n = func.call @tt_made(%tt, %slot) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
    %kind = llvm.load %n : !llvm.ptr -> i64
    %isArr = arith.cmpi eq, %kind, %c1 : i64
    %next = scf.if %isArr -> (!llvm.ptr) {
      %b = func.call @nixev_tt_back(%n) : (!llvm.ptr) -> !llvm.ptr
      scf.yield %b : !llvm.ptr
    } else {
      %notTable = arith.cmpi ne, %kind, %c0 : i64
      scf.if %notTable {
        func.call @tt_fail(%tt, %e29, %i64) : (!llvm.ptr, i64, i64) -> ()
      }
      scf.yield %n : !llvm.ptr
    }
    scf.yield %next : !llvm.ptr
  }
  %slot = func.call @tt_child(%tt, %t, %last) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
  %old = llvm.load %slot : !llvm.ptr -> !llvm.ptr
  %ob = llvm.ptrtoint %old : !llvm.ptr to i64
  %fresh = arith.cmpi eq, %ob, %c0 : i64
  %P = func.call @tt_rp(%tt, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %frames = func.call @tt_rp(%tt, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %isAot = arith.cmpi ne, %aot, %c0 : i64
  scf.if %isAot {
    %arr = scf.if %fresh -> (!llvm.ptr) {
      %m = func.call @nixev_tt_make(%P) : (!llvm.ptr) -> !llvm.ptr
      llvm.store %c1, %m : i64, !llvm.ptr
      llvm.store %m, %slot : !llvm.ptr, !llvm.ptr
      scf.yield %m : !llvm.ptr
    } else {
      scf.yield %old : !llvm.ptr
    }
    %kind = llvm.load %arr : !llvm.ptr -> i64
    %notArr = arith.cmpi ne, %kind, %c1 : i64
    scf.if %notArr {
      func.call @tt_fail(%tt, %e29, %last) : (!llvm.ptr, i64, i64) -> ()
    }
    %nt = func.call @nixev_tt_make(%P) : (!llvm.ptr) -> !llvm.ptr
    func.call @nixev_tt_push(%arr, %nt) : (!llvm.ptr, !llvm.ptr) -> ()
    func.call @tt_wp(%frames, %c0, %nt) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  } else {
    scf.if %fresh {
    } else {
      %kind = llvm.load %old : !llvm.ptr -> i64
      %dp = llvm.getelementptr %old[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %def = llvm.load %dp : !llvm.ptr -> i64
      %notTable = arith.cmpi ne, %kind, %c0 : i64
      %defined = arith.cmpi ne, %def, %c0 : i64
      %bad = arith.ori %notTable, %defined : i1
      scf.if %bad {
        func.call @tt_fail(%tt, %e31, %last) : (!llvm.ptr, i64, i64) -> ()
      }
    }
    %tbl = func.call @tt_made(%tt, %slot) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
    %dp = llvm.getelementptr %tbl[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1, %dp : i64, !llvm.ptr
    func.call @tt_wp(%frames, %c0, %tbl) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  }
  func.call @tt_wr(%tt, %c6, %c0) : (!llvm.ptr, i64, i64) -> ()
  return
}

// a frame: its node (0 for an array), the elems and keys counts when it opened
func.func private @tt_push_frame(%tt: !llvm.ptr, %node: !llvm.ptr) {
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c6 = arith.constant 6 : i64
  %frames = func.call @tt_rp(%tt, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %nf = func.call @tt_rd(%tt, %c2) : (!llvm.ptr, i64) -> i64
  %ne = func.call @tt_rd(%tt, %c4) : (!llvm.ptr, i64) -> i64
  %nk = func.call @tt_rd(%tt, %c6) : (!llvm.ptr, i64) -> i64
  %o = arith.muli %nf, %c3 : i64
  func.call @tt_wp(%frames, %o, %node) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %o1 = arith.addi %o, %c1 : i64
  func.call @tt_wr(%frames, %o1, %ne) : (!llvm.ptr, i64, i64) -> ()
  %o2 = arith.addi %o, %c2 : i64
  func.call @tt_wr(%frames, %o2, %nk) : (!llvm.ptr, i64, i64) -> ()
  %nf1 = arith.addi %nf, %c1 : i64
  func.call @tt_wr(%tt, %c2, %nf1) : (!llvm.ptr, i64, i64) -> ()
  return
}

// the top frame's word k (0 node, 1 elems, 2 keys)
func.func private @tt_top(%tt: !llvm.ptr, %k: i64) -> i64 {
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %frames = func.call @tt_rp(%tt, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %nf = func.call @tt_rd(%tt, %c2) : (!llvm.ptr, i64) -> i64
  %top = arith.subi %nf, %c1 : i64
  %o = arith.muli %top, %c3 : i64
  %ok = arith.addi %o, %k : i64
  %w = func.call @tt_rd(%frames, %ok) : (!llvm.ptr, i64) -> i64
  return %w : i64
}

// a complete value: an element of the open array, or the value of the open table's key (its parts then dropped)
func.func private @tt_deliver(%tt: !llvm.ptr, %v: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c6 = arith.constant 6 : i64
  %nb = func.call @tt_top(%tt, %c0) : (!llvm.ptr, i64) -> i64
  %isArr = arith.cmpi eq, %nb, %c0 : i64
  scf.if %isArr {
    %elems = func.call @tt_rp(%tt, %c3) : (!llvm.ptr, i64) -> !llvm.ptr
    %ne = func.call @tt_rd(%tt, %c4) : (!llvm.ptr, i64) -> i64
    func.call @tt_wp(%elems, %ne, %v) : (!llvm.ptr, i64, !llvm.ptr) -> ()
    %ne1 = arith.addi %ne, %c1 : i64
    func.call @tt_wr(%tt, %c4, %ne1) : (!llvm.ptr, i64, i64) -> ()
  } else {
    %node = llvm.inttoptr %nb : i64 to !llvm.ptr
    %fk = func.call @tt_top(%tt, %c2) : (!llvm.ptr, i64) -> i64
    func.call @tt_setkey(%tt, %node, %fk, %v) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> ()
    %nk = func.call @tt_rd(%tt, %c6) : (!llvm.ptr, i64) -> i64
    %keep = arith.minsi %nk, %fk : i64
    func.call @tt_wr(%tt, %c6, %keep) : (!llvm.ptr, i64, i64) -> ()
  }
  return
}

// toValue: a leaf's value; an array of tables' list of its tables' sets; a table's set, each row's value made and then
// its key's symbol (the order the old builder made them in)
func.func private @tt_value(%tt: !llvm.ptr, %n: !llvm.ptr) -> !llvm.ptr {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %zi = arith.constant 0 : index
  %one = arith.constant 1 : index
  %P = func.call @tt_rp(%tt, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %kind = llvm.load %n : !llvm.ptr -> i64
  %ki = arith.index_cast %kind : i64 to index
  %r = scf.index_switch %ki -> !llvm.ptr
  case 2 {
    %lp = llvm.getelementptr %n[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %leaf = llvm.load %lp : !llvm.ptr -> !llvm.ptr
    scf.yield %leaf : !llvm.ptr
  }
  case 1 {
    %cnt = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
    %kids = func.call @nixev_tt_kids(%n, %cnt) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
    %k = llvm.load %cnt : !llvm.ptr -> i64
    %v = func.call @nixev_tt_list(%P, %k) : (!llvm.ptr, i64) -> !llvm.ptr
    %cp = llvm.getelementptr %v[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %cells = llvm.load %cp : !llvm.ptr -> !llvm.ptr
    %ki2 = arith.index_cast %k : i64 to index
    scf.for %i = %zi to %ki2 step %one {
      %i64 = arith.index_cast %i : index to i64
      %c = func.call @tt_rp(%kids, %i64) : (!llvm.ptr, i64) -> !llvm.ptr
      %cv = func.call @tt_value(%tt, %c) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
      func.call @tt_wp(%cells, %i64, %cv) : (!llvm.ptr, i64, !llvm.ptr) -> ()
    }
    scf.yield %v : !llvm.ptr
  }
  default {
    %cnt = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
    %rows = func.call @nixev_tt_rows(%n, %cnt) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
    %k = llvm.load %cnt : !llvm.ptr -> i64
    %k2 = arith.muli %k, %c2 : i64
    %cells = func.call @nixev_tt_scratch(%P, %k2) : (!llvm.ptr, i64) -> !llvm.ptr
    %ki2 = arith.index_cast %k : i64 to index
    scf.for %i = %zi to %ki2 step %one {
      %i64 = arith.index_cast %i : index to i64
      %ro = arith.muli %i64, %c24 : i64
      %rp = llvm.getelementptr %rows[%ro] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %kp = llvm.load %rp : !llvm.ptr -> !llvm.ptr
      %klp = llvm.getelementptr %rp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %kl32 = llvm.load %klp : !llvm.ptr -> i32
      %kl = arith.extui %kl32 : i32 to i64
      %cnp = llvm.getelementptr %rp[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %c = llvm.load %cnp : !llvm.ptr -> !llvm.ptr
      %cv = func.call @tt_value(%tt, %c) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
      %sym = func.call @nixev_tt_sym(%P, %kp, %kl) : (!llvm.ptr, !llvm.ptr, i64) -> i64
      %o = arith.muli %i64, %c2 : i64
      func.call @tt_wr(%cells, %o, %sym) : (!llvm.ptr, i64, i64) -> ()
      %o1 = arith.addi %o, %c1 : i64
      func.call @tt_wp(%cells, %o1, %cv) : (!llvm.ptr, i64, !llvm.ptr) -> ()
    }
    %v = func.call @nixev_tt_attrs(%P, %cells, %k) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
    scf.yield %v : !llvm.ptr
  }
  return %r : !llvm.ptr
}

func.func @nixev_ts_toml_value(%tt: !llvm.ptr, %n: !llvm.ptr) -> !llvm.ptr {
  %v = func.call @tt_value(%tt, %n) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
  return %v : !llvm.ptr
}

// The scan's events (TomlScan.mlir's header lists them), in order.
func.func @nixev_toml_ev(%tt: !llvm.ptr, %kind: i64, %p: !llvm.ptr, %a: i64, %line: i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  func.call @tt_wr(%tt, %c7, %line) : (!llvm.ptr, i64, i64) -> ()
  %P = func.call @tt_rp(%tt, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %null = llvm.inttoptr %c0 : i64 to !llvm.ptr
  %ki = arith.index_cast %kind : i64 to index
  %v = scf.index_switch %ki -> !llvm.ptr
  case 0 {
    // a key part (ptr, len)
    %keys = func.call @tt_rp(%tt, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
    %nk = func.call @tt_rd(%tt, %c6) : (!llvm.ptr, i64) -> i64
    %o = arith.muli %nk, %c2 : i64
    func.call @tt_wp(%keys, %o, %p) : (!llvm.ptr, i64, !llvm.ptr) -> ()
    %o1 = arith.addi %o, %c1 : i64
    func.call @tt_wr(%keys, %o1, %a) : (!llvm.ptr, i64, i64) -> ()
    %nk1 = arith.addi %nk, %c1 : i64
    func.call @tt_wr(%tt, %c6, %nk1) : (!llvm.ptr, i64, i64) -> ()
    scf.yield %null : !llvm.ptr
  }
  case 6 {
    func.call @tt_push_frame(%tt, %null) : (!llvm.ptr, !llvm.ptr) -> ()
    scf.yield %null : !llvm.ptr
  }
  case 7 {
    // an array's end: its elements (a window of the elems) drained once into the list's cells
    %from = func.call @tt_top(%tt, %c1) : (!llvm.ptr, i64) -> i64
    %ne = func.call @tt_rd(%tt, %c4) : (!llvm.ptr, i64) -> i64
    %n = arith.subi %ne, %from : i64
    %lv = func.call @nixev_tt_list(%P, %n) : (!llvm.ptr, i64) -> !llvm.ptr
    %elems = func.call @tt_rp(%tt, %c3) : (!llvm.ptr, i64) -> !llvm.ptr
    %ep = llvm.getelementptr %elems[%from] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    %sd = func.call @tt_desc64(%ep, %n) : (!llvm.ptr, i64) -> !d
    %sm = builtin.unrealized_conversion_cast %sd : !d to !m64
    %ss = builtin.unrealized_conversion_cast %sm : !m64 to !s64
    %cells = func.call @tt_rp(%lv, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
    %id = func.call @tt_desc64(%cells, %n) : (!llvm.ptr, i64) -> !d
    %im = builtin.unrealized_conversion_cast %id : !d to !m64
    %end = trikeshed.drain %ss, %im : !s64, !m64 -> index
    func.call @tt_wr(%tt, %c4, %from) : (!llvm.ptr, i64, i64) -> ()
    %nf = func.call @tt_rd(%tt, %c2) : (!llvm.ptr, i64) -> i64
    %nf1 = arith.subi %nf, %c1 : i64
    func.call @tt_wr(%tt, %c2, %nf1) : (!llvm.ptr, i64, i64) -> ()
    scf.yield %lv : !llvm.ptr
  }
  case 8 {
    %m = func.call @nixev_tt_make(%P) : (!llvm.ptr) -> !llvm.ptr
    func.call @tt_push_frame(%tt, %m) : (!llvm.ptr, !llvm.ptr) -> ()
    scf.yield %null : !llvm.ptr
  }
  case 9 {
    // an inline table's end: its node's set
    %nb = func.call @tt_top(%tt, %c0) : (!llvm.ptr, i64) -> i64
    %node = llvm.inttoptr %nb : i64 to !llvm.ptr
    %tv = func.call @tt_value(%tt, %node) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
    %nf = func.call @tt_rd(%tt, %c2) : (!llvm.ptr, i64) -> i64
    %nf1 = arith.subi %nf, %c1 : i64
    func.call @tt_wr(%tt, %c2, %nf1) : (!llvm.ptr, i64, i64) -> ()
    scf.yield %tv : !llvm.ptr
  }
  case 10 {
    func.call @tt_header(%tt, %a) : (!llvm.ptr, i64) -> ()
    scf.yield %null : !llvm.ptr
  }
  default {
    // 1 string, 2 int, 3 float bits, 4 bool, 5 date: the evaluator's value
    %sv = func.call @nixev_tt_value(%P, %kind, %p, %a) : (!llvm.ptr, i64, !llvm.ptr, i64) -> !llvm.ptr
    scf.yield %sv : !llvm.ptr
  }
  %vb = llvm.ptrtoint %v : !llvm.ptr to i64
  %some = arith.cmpi ne, %vb, %c0 : i64
  scf.if %some {
    func.call @tt_deliver(%tt, %v) : (!llvm.ptr, !llvm.ptr) -> ()
  }
  return
}
