// The C++ attribute-set / list algebra primops (__groupBy, __zipAttrsWith, __partition, __catAttrs, removeAttrs,
// __listToAttrs, __mapAttrs) hollowed into the TrikeShed dialect.  lib/Eval/Builtins.cpp keeps the forcing of the
// operands it forced before (Nix's error order and wording) and calls these entries; the algebra is here: the stable
// grouping by name (trikeshed.sorted over `name << 32 | row` words, then a where of the run starts), the per-run lists
// (slices drained into the arena cells), removeAttrs' membership (a sorted series bisected), the selections (where /
// alpha), and the set rows written as two i64 words an Attr (drain).  Lowered by --trikeshed-lower-cursors and the stock
// buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
//
// Layouts (as SetOps.mlir): a Bindings is u32 size_@0, PosPtr pos@8, Attr attrs[0]@16, rows sorted by Symbol (u32).  An
// Attr is 16 bytes: Symbol name@0, PosIdx pos@4, Value* value@8, so its first word is name | pos << 32.  A Value is 24
// bytes: VType u8@0 (Attrs 11, List 12), aux u32@4 (a list's size), union@8 (list.elems / attrs).  A list's cells are a
// series<i64> of pointer bits.
//
// Every evaluator interaction is a callback in Builtins.cpp, called at the point the C++ loop made it, in the same order:
// a function application and its result's forcing (nixev_gr_sym / nixev_gr_side), an element's forcing to a set
// (nixev_gr_force), a {name, value} pair (nixev_gr_pair: its throws carry their traces), a run's list cell and the
// `f name values` thunk (nixev_gr_run), mkAttrAppValue (nixev_gr_app), the result set (nixev_gr_set: allocBindings, or
// the shared empty set) and partition's two-list set (nixev_gr_partition).  Symbols are created by the callbacks in the
// order the C++ made them, so later sets iterate the same way.
!s = !trikeshed.series<i64>
!m = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
!coords = !trikeshed.series<!trikeshed.twinpacked<i32>>

func.func private @_ZN5nixev9EvalState6mkListERNS_5ValueEm(!llvm.ptr, !llvm.ptr, i64)
func.func private @_ZN5nixev9EvalState13allocBindingsEm(!llvm.ptr, i64) -> !llvm.ptr
func.func private @_ZNK5nixev8Bindings3getEj(!llvm.ptr, i32) -> !llvm.ptr
func.func private @nixev_gr_sym(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
func.func private @nixev_gr_side(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
func.func private @nixev_gr_force(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
func.func private @nixev_gr_pair(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
func.func private @nixev_gr_run(!llvm.ptr, !llvm.ptr, i64, i64, i64, !llvm.ptr) -> !llvm.ptr
func.func private @nixev_gr_app(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> !llvm.ptr
func.func private @nixev_gr_set(!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> !llvm.ptr
func.func private @nixev_gr_partition(!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr)

// the descriptor of n i64 cells at p (module-unique)
func.func private @gr_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// the descriptor of a forced list's cells
func.func private @gr_list_desc(%list: !llvm.ptr) -> !d {
  %ep = llvm.getelementptr %list[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %elems = llvm.load %ep : !llvm.ptr -> !llvm.ptr
  %np = llvm.getelementptr %list[4] : (!llvm.ptr) -> !llvm.ptr, i8
  %n32 = llvm.load %np : !llvm.ptr -> i32
  %n = llvm.zext %n32 : i32 to i64
  %d = func.call @gr_desc(%elems, %n) : (!llvm.ptr, i64) -> !d
  return %d : !d
}

// the descriptor of a set's rows as 2 * size words
func.func private @gr_rows_desc(%set: !llvm.ptr) -> !d {
  %n32 = llvm.load %set : !llvm.ptr -> i32
  %n = llvm.zext %n32 : i32 to i64
  %c2 = arith.constant 2 : i64
  %w = arith.muli %n, %c2 : i64
  %attrs = llvm.getelementptr %set[16] : (!llvm.ptr) -> !llvm.ptr, i8
  %d = func.call @gr_desc(%attrs, %w) : (!llvm.ptr, i64) -> !d
  return %d : !d
}

// a set's size
func.func private @gr_set_size(%set: !llvm.ptr) -> i64 {
  %n32 = llvm.load %set : !llvm.ptr -> i32
  %n = llvm.zext %n32 : i32 to i64
  return %n : i64
}

// the result Value: an attribute set over b
func.func private @gr_mkattrs(%v: !llvm.ptr, %b: !llvm.ptr) {
  %t = arith.constant 11 : i8
  llvm.store %t, %v : i8, !llvm.ptr
  %ap = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %b, %ap : !llvm.ptr, !llvm.ptr
  return
}

// the unsigned order of two words
func.func private @gr_order(%a: i64, %b: i64) -> i32 {
  %lt = arith.cmpi ult, %a, %b : i64
  %gt = arith.cmpi ugt, %a, %b : i64
  %m1 = arith.constant -1 : i32
  %p1 = arith.constant 1 : i32
  %z = arith.constant 0 : i32
  %t = arith.select %gt, %p1, %z : i32
  %r = arith.select %lt, %m1, %t : i32
  return %r : i32
}

// __groupBy (mode 0) and __zipAttrsWith (mode 1).  The (name, value) rows in list order: groupBy's are each element's
// group name (f x forced to a string, its symbol: the callback, in list order) and the element; zipAttrsWith forces
// every element to a set first (in list order, the callback), then its rows are every (name, value) of every set in list
// order, the combineAll of the sets' rows.  The rows as name << 32 | row words, sorted unsigned (stable: each name keeps
// its rows' order); the run starts are a where; one result row a name, its value the run's list (groupBy) or the
// `f name values` thunk over it (zipAttrsWith), each run's values a slice of the values in sorted order drained into the
// cells its list was made with; the result rows drained into the set two words each.  The bridge forced the list.
func.func @nixev_ts_group(%st: !llvm.ptr, %f: !llvm.ptr, %list: !llvm.ptr, %v: !llvm.ptr, %pos: !llvm.ptr, %mode: i64) {
  %d = func.call @gr_list_desc(%list) : (!llvm.ptr) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %cells = builtin.unrealized_conversion_cast %mm : !m to !s
  %n = trikeshed.size %cells : !s
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c32 = arith.constant 32 : i64
  %lo = arith.constant 4294967295 : i64
  %c0i = arith.constant 0 : index
  %c1i = arith.constant 1 : index
  %c2i = arith.constant 2 : index
  %zip = arith.cmpi ne, %mode, %c0 : i64
  %n64 = arith.index_cast %n : index to i64
  %total = scf.if %zip -> (i64) {
    %t = trikeshed.fold %cells, %c0 : !s, i64 -> i64 {
    ^bb0(%acc: i64, %x: i64):
      %xp = llvm.inttoptr %x : i64 to !llvm.ptr
      %b = func.call @nixev_gr_force(%st, %xp, %pos, %c0) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
      %sz = func.call @gr_set_size(%b) : (!llvm.ptr) -> i64
      %acc2 = arith.addi %acc, %sz : i64
      trikeshed.yield %acc2 : i64
    }
    scf.yield %t : i64
  } else {
    scf.yield %n64 : i64
  }
  %nsets = arith.select %zip, %n, %c0i : index
  %all, %co = trikeshed.combineAll %nsets : !s, !coords {
  ^bb0(%k: index):
    %x = trikeshed.at %cells[%k] : !s, index -> i64
    %xp = llvm.inttoptr %x : i64 to !llvm.ptr
    %bp = llvm.getelementptr %xp[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %b = llvm.load %bp : !llvm.ptr -> !llvm.ptr
    %rd = func.call @gr_rows_desc(%b) : (!llvm.ptr) -> !d
    %rm = builtin.unrealized_conversion_cast %rd : !d to !m
    %part = builtin.unrealized_conversion_cast %rm : !m to !s
    trikeshed.yield %part : !s
  }
  %ti = arith.index_cast %total : i64 to index
  %keyed = trikeshed.series %ti : !s {
  ^bb0(%i: index):
    %name = scf.if %zip -> (i64) {
      %k = arith.muli %i, %c2i : index
      %w = trikeshed.at %all[%k] : !s, index -> i64
      %nm = arith.andi %w, %lo : i64
      scf.yield %nm : i64
    } else {
      %x = trikeshed.at %cells[%i] : !s, index -> i64
      %xp = llvm.inttoptr %x : i64 to !llvm.ptr
      %one = arith.constant 1 : i64
      %sym = func.call @nixev_gr_sym(%st, %f, %xp, %pos, %one) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
      scf.yield %sym : i64
    }
    %hi = arith.shli %name, %c32 : i64
    %i64 = arith.index_cast %i : index to i64
    %kw = arith.ori %hi, %i64 : i64
    trikeshed.yield %kw : i64
  }
  %keyed2 = trikeshed.sorted %keyed : !s -> !s by {
  ^bb0(%a: i64, %b: i64):
    %c = func.call @gr_order(%a, %b) : (i64, i64) -> i32
    trikeshed.yield %c : i32
  }
  %rows = trikeshed.series %ti : !s {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %starts = trikeshed.where %rows : !s -> !s {
  ^bb0(%r: i64):
    %first = arith.cmpi eq, %r, %c0 : i64
    %rm1 = arith.subi %r, %c1 : i64
    %prev = arith.select %first, %r, %rm1 : i64
    %ri = arith.index_cast %r : i64 to index
    %pi = arith.index_cast %prev : i64 to index
    %a = trikeshed.at %keyed2[%ri] : !s, index -> i64
    %b = trikeshed.at %keyed2[%pi] : !s, index -> i64
    %ka = arith.shrui %a, %c32 : i64
    %kb = arith.shrui %b, %c32 : i64
    %new = arith.cmpi ne, %ka, %kb : i64
    %start = arith.ori %first, %new : i1
    trikeshed.yield %start : i1
  }
  // the values in sorted order: the element (groupBy) or the row's value word (zipAttrsWith) of each sorted row
  %sorted = trikeshed.alpha %keyed2 : !s -> !s {
  ^bb0(%w: i64):
    %row = arith.andi %w, %lo : i64
    %ri = arith.index_cast %row : i64 to index
    %x = scf.if %zip -> (i64) {
      %k = arith.muli %ri, %c2i : index
      %k1 = arith.addi %k, %c1i : index
      %vw = trikeshed.at %all[%k1] : !s, index -> i64
      scf.yield %vw : i64
    } else {
      %cw = trikeshed.at %cells[%ri] : !s, index -> i64
      scf.yield %cw : i64
    }
    trikeshed.yield %x : i64
  }
  %m = trikeshed.size %starts : !s
  %m64 = arith.index_cast %m : index to i64
  %null = llvm.mlir.zero : !llvm.ptr
  %set = func.call @nixev_gr_set(%st, %v, %m64, %m64, %null) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> !llvm.ptr
  %words = arith.muli %m, %c2i : index
  %w64 = arith.index_cast %words : index to i64
  %slot = llvm.alloca %c1 x !llvm.ptr : (i64) -> !llvm.ptr
  %wcells = trikeshed.series %words : !s {
  ^bb0(%q: index):
    %r = arith.divui %q, %c2i : index
    %odd = arith.remui %q, %c2i : index
    %s0 = trikeshed.at %starts[%r] : !s, index -> i64
    %si = arith.index_cast %s0 : i64 to index
    %ks = trikeshed.at %keyed2[%si] : !s, index -> i64
    %key = arith.shrui %ks, %c32 : i64
    %isodd = arith.cmpi ne, %odd, %c0i : index
    %word = scf.if %isodd -> (i64) {
      %r1 = arith.addi %r, %c1i : index
      %last = arith.cmpi uge, %r1, %m : index
      %r1c = arith.select %last, %r, %r1 : index
      %nx = trikeshed.at %starts[%r1c] : !s, index -> i64
      %e = arith.select %last, %total, %nx : i64
      %cnt = arith.subi %e, %s0 : i64
      %cell = func.call @nixev_gr_run(%st, %f, %mode, %key, %cnt, %slot) : (!llvm.ptr, !llvm.ptr, i64, i64, i64, !llvm.ptr) -> !llvm.ptr
      %el = llvm.load %slot : !llvm.ptr -> !llvm.ptr
      %cnti = arith.index_cast %cnt : i64 to index
      %part = trikeshed.slice %sorted[%si, %cnti] : !s -> !s
      %dd = func.call @gr_desc(%el, %cnt) : (!llvm.ptr, i64) -> !d
      %into = builtin.unrealized_conversion_cast %dd : !d to !m
      %end = trikeshed.drain %part, %into : !s, !m -> index
      %cb = llvm.ptrtoint %cell : !llvm.ptr to i64
      scf.yield %cb : i64
    } else {
      scf.yield %key : i64
    }
    trikeshed.yield %word : i64
  }
  %attrs = llvm.getelementptr %set[16] : (!llvm.ptr) -> !llvm.ptr, i8
  %sd = func.call @gr_desc(%attrs, %w64) : (!llvm.ptr, i64) -> !d
  %sinto = builtin.unrealized_conversion_cast %sd : !d to !m
  %send = trikeshed.drain %wcells, %sinto : !s, !m -> index
  return
}

// __partition: each element's side (forced, f applied, its Bool forced: the callback, in list order), then the rows of
// each side (two wheres over the row indices) and their cells, drained into the two lists the callback made.  The
// bridge forced the list.
func.func @nixev_ts_partition(%st: !llvm.ptr, %f: !llvm.ptr, %list: !llvm.ptr, %v: !llvm.ptr, %pos: !llvm.ptr) {
  %d = func.call @gr_list_desc(%list) : (!llvm.ptr) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %cells = builtin.unrealized_conversion_cast %mm : !m to !s
  %n = trikeshed.size %cells : !s
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %sides = trikeshed.series %n : !s {
  ^bb0(%i: index):
    %x = trikeshed.at %cells[%i] : !s, index -> i64
    %xp = llvm.inttoptr %x : i64 to !llvm.ptr
    %b = func.call @nixev_gr_side(%st, %f, %xp, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
    %i64 = arith.index_cast %i : index to i64
    %c1s = arith.constant 1 : i64
    %hi = arith.shli %i64, %c1s : i64
    %w = arith.ori %hi, %b : i64
    trikeshed.yield %w : i64
  }
  %right = trikeshed.where %sides : !s -> !s {
  ^bb0(%w: i64):
    %b = arith.andi %w, %c1 : i64
    %t = arith.cmpi ne, %b, %c0 : i64
    trikeshed.yield %t : i1
  }
  %wrong = trikeshed.where %sides : !s -> !s {
  ^bb0(%w: i64):
    %b = arith.andi %w, %c1 : i64
    %t = arith.cmpi eq, %b, %c0 : i64
    trikeshed.yield %t : i1
  }
  %rc = trikeshed.alpha %right : !s -> !s {
  ^bb0(%w: i64):
    %r = arith.shrui %w, %c1 : i64
    %ri = arith.index_cast %r : i64 to index
    %x = trikeshed.at %cells[%ri] : !s, index -> i64
    trikeshed.yield %x : i64
  }
  %wc = trikeshed.alpha %wrong : !s -> !s {
  ^bb0(%w: i64):
    %r = arith.shrui %w, %c1 : i64
    %ri = arith.index_cast %r : i64 to index
    %x = trikeshed.at %cells[%ri] : !s, index -> i64
    trikeshed.yield %x : i64
  }
  %nr = trikeshed.size %right : !s
  %nw = trikeshed.size %wrong : !s
  %nr64 = arith.index_cast %nr : index to i64
  %nw64 = arith.index_cast %nw : index to i64
  %re = llvm.alloca %c1 x !llvm.ptr : (i64) -> !llvm.ptr
  %we = llvm.alloca %c1 x !llvm.ptr : (i64) -> !llvm.ptr
  func.call @nixev_gr_partition(%st, %v, %nr64, %nw64, %re, %we) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr) -> ()
  %rel = llvm.load %re : !llvm.ptr -> !llvm.ptr
  %wel = llvm.load %we : !llvm.ptr -> !llvm.ptr
  %rd = func.call @gr_desc(%rel, %nr64) : (!llvm.ptr, i64) -> !d
  %rinto = builtin.unrealized_conversion_cast %rd : !d to !m
  %e1 = trikeshed.drain %rc, %rinto : !s, !m -> index
  %wd = func.call @gr_desc(%wel, %nw64) : (!llvm.ptr, i64) -> !d
  %winto = builtin.unrealized_conversion_cast %wd : !d to !m
  %e2 = trikeshed.drain %wc, %winto : !s, !m -> index
  return
}

// __catAttrs: each element forced to a set (the callback, in list order) and looked up (Bindings::get), then the values
// found (a where over the looked-up cells, 0 where absent) drained into the result list.  The bridge forced the name and
// the list.
func.func @nixev_ts_catAttrs(%st: !llvm.ptr, %sym: i64, %list: !llvm.ptr, %v: !llvm.ptr, %pos: !llvm.ptr) {
  %d = func.call @gr_list_desc(%list) : (!llvm.ptr) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %cells = builtin.unrealized_conversion_cast %mm : !m to !s
  %c0 = arith.constant 0 : i64
  %which = arith.constant 1 : i64
  %s32 = arith.trunci %sym : i64 to i32
  %got = trikeshed.alpha %cells : !s -> !s {
  ^bb0(%x: i64):
    %xp = llvm.inttoptr %x : i64 to !llvm.ptr
    %b = func.call @nixev_gr_force(%st, %xp, %pos, %which) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
    %a = func.call @_ZNK5nixev8Bindings3getEj(%b, %s32) : (!llvm.ptr, i32) -> !llvm.ptr
    %ai = llvm.ptrtoint %a : !llvm.ptr to i64
    %has = arith.cmpi ne, %ai, %c0 : i64
    %val = scf.if %has -> (i64) {
      %vp = llvm.getelementptr %a[8] : (!llvm.ptr) -> !llvm.ptr, i8
      %vv = llvm.load %vp : !llvm.ptr -> i64
      scf.yield %vv : i64
    } else {
      scf.yield %c0 : i64
    }
    trikeshed.yield %val : i64
  }
  %kept = trikeshed.where %got : !s -> !s {
  ^bb0(%x: i64):
    %t = arith.cmpi ne, %x, %c0 : i64
    trikeshed.yield %t : i1
  }
  %k = trikeshed.size %kept : !s
  %k64 = arith.index_cast %k : index to i64
  func.call @_ZN5nixev9EvalState6mkListERNS_5ValueEm(%st, %v, %k64) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %ep = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %elems = llvm.load %ep : !llvm.ptr -> !llvm.ptr
  %ed = func.call @gr_desc(%elems, %k64) : (!llvm.ptr, i64) -> !d
  %into = builtin.unrealized_conversion_cast %ed : !d to !m
  %end = trikeshed.drain %kept, %into : !s, !m -> index
  return
}

// removeAttrs: the names to drop (each forced and made a symbol: the callback, in list order), sorted; the set's rows
// whose name does not bisect into them, drained (two words a row) into a new set of the input's size.  The bridge forced
// the set and the list.
func.func @nixev_ts_removeAttrs(%st: !llvm.ptr, %in: !llvm.ptr, %list: !llvm.ptr, %v: !llvm.ptr, %pos: !llvm.ptr) {
  %d = func.call @gr_list_desc(%list) : (!llvm.ptr) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %cells = builtin.unrealized_conversion_cast %mm : !m to !s
  %null = llvm.mlir.zero : !llvm.ptr
  %which = arith.constant 0 : i64
  %syms = trikeshed.alpha %cells : !s -> !s {
  ^bb0(%x: i64):
    %xp = llvm.inttoptr %x : i64 to !llvm.ptr
    %sym = func.call @nixev_gr_sym(%st, %null, %xp, %pos, %which) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
    trikeshed.yield %sym : i64
  }
  %rm = trikeshed.sorted %syms : !s -> !s
  %n = func.call @gr_set_size(%in) : (!llvm.ptr) -> i64
  %rd = func.call @gr_rows_desc(%in) : (!llvm.ptr) -> !d
  %rmm = builtin.unrealized_conversion_cast %rd : !d to !m
  %rows = builtin.unrealized_conversion_cast %rmm : !m to !s
  %ni = arith.index_cast %n : i64 to index
  %c0i = arith.constant 0 : index
  %c1i = arith.constant 1 : index
  %c2i = arith.constant 2 : index
  %lo = arith.constant 4294967295 : i64
  %idx = trikeshed.series %ni : !s {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %kept = trikeshed.where %idx : !s -> !s {
  ^bb0(%r: i64):
    %ri = arith.index_cast %r : i64 to index
    %k = arith.muli %ri, %c2i : index
    %w = trikeshed.at %rows[%k] : !s, index -> i64
    %name = arith.andi %w, %lo : i64
    %j = trikeshed.bisect %rm, %name : !s, i64 -> index
    %absent = arith.cmpi slt, %j, %c0i : index
    trikeshed.yield %absent : i1
  }
  %out = func.call @_ZN5nixev9EvalState13allocBindingsEm(%st, %n) : (!llvm.ptr, i64) -> !llvm.ptr
  %k = trikeshed.size %kept : !s
  %words = arith.muli %k, %c2i : index
  %wcells = trikeshed.series %words : !s {
  ^bb0(%q: index):
    %r = arith.divui %q, %c2i : index
    %h = arith.remui %q, %c2i : index
    %row = trikeshed.at %kept[%r] : !s, index -> i64
    %rowi = arith.index_cast %row : i64 to index
    %at = arith.muli %rowi, %c2i : index
    %at2 = arith.addi %at, %h : index
    %w = trikeshed.at %rows[%at2] : !s, index -> i64
    trikeshed.yield %w : i64
  }
  %w64 = arith.index_cast %words : index to i64
  %attrs = llvm.getelementptr %out[16] : (!llvm.ptr) -> !llvm.ptr, i8
  %od = func.call @gr_desc(%attrs, %w64) : (!llvm.ptr, i64) -> !d
  %into = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %wcells, %into : !s, !m -> index
  %k64 = arith.index_cast %k : index to i64
  %k32 = arith.trunci %k64 : i64 to i32
  llvm.store %k32, %out : i32, !llvm.ptr
  func.call @gr_mkattrs(%v, %out) : (!llvm.ptr, !llvm.ptr) -> ()
  return
}

// __mapAttrs: a new set of the input's size whose rows are the input's names and positions, each value the
// `f name value` thunk (the callback, in row order), drained two words a row.  The bridge forced the set.
func.func @nixev_ts_mapAttrs(%st: !llvm.ptr, %f: !llvm.ptr, %in: !llvm.ptr, %v: !llvm.ptr) {
  %n = func.call @gr_set_size(%in) : (!llvm.ptr) -> i64
  %out = func.call @_ZN5nixev9EvalState13allocBindingsEm(%st, %n) : (!llvm.ptr, i64) -> !llvm.ptr
  %rd = func.call @gr_rows_desc(%in) : (!llvm.ptr) -> !d
  %rmm = builtin.unrealized_conversion_cast %rd : !d to !m
  %rows = builtin.unrealized_conversion_cast %rmm : !m to !s
  %c0i = arith.constant 0 : index
  %c1i = arith.constant 1 : index
  %c2i = arith.constant 2 : index
  %lo = arith.constant 4294967295 : i64
  %words = trikeshed.size %rows : !s
  %wcells = trikeshed.series %words : !s {
  ^bb0(%q: index):
    %h = arith.remui %q, %c2i : index
    %w = trikeshed.at %rows[%q] : !s, index -> i64
    %odd = arith.cmpi ne, %h, %c0i : index
    %word = scf.if %odd -> (i64) {
      %q0 = arith.subi %q, %c1i : index
      %w0 = trikeshed.at %rows[%q0] : !s, index -> i64
      %name = arith.andi %w0, %lo : i64
      %xp = llvm.inttoptr %w : i64 to !llvm.ptr
      %cell = func.call @nixev_gr_app(%st, %f, %name, %xp) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> !llvm.ptr
      %cb = llvm.ptrtoint %cell : !llvm.ptr to i64
      scf.yield %cb : i64
    } else {
      scf.yield %w : i64
    }
    trikeshed.yield %word : i64
  }
  %w64 = arith.index_cast %words : index to i64
  %attrs = llvm.getelementptr %out[16] : (!llvm.ptr) -> !llvm.ptr, i8
  %od = func.call @gr_desc(%attrs, %w64) : (!llvm.ptr, i64) -> !d
  %into = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %wcells, %into : !s, !m -> index
  %n32 = arith.trunci %n : i64 to i32
  llvm.store %n32, %out : i32, !llvm.ptr
  func.call @gr_mkattrs(%v, %out) : (!llvm.ptr, !llvm.ptr) -> ()
  return
}

// __listToAttrs: each element's {name, value} pair (forced, looked up, the name forced and made a symbol: the callback,
// in list order) as the row's two words; the rows sorted by name (stable: name << 32 | row words), the first row of
// each name kept (BindingsBuilder::finish's rule), drained into the set.  The set has room for a row an element: made
// before the pairs when there are more than 12 of them (BindingsBuilder's arena block), after them otherwise.  The
// bridge forced the list.
func.func @nixev_ts_listToAttrs(%st: !llvm.ptr, %list: !llvm.ptr, %v: !llvm.ptr, %pos: !llvm.ptr) {
  %d = func.call @gr_list_desc(%list) : (!llvm.ptr) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %cells = builtin.unrealized_conversion_cast %mm : !m to !s
  %n = trikeshed.size %cells : !s
  %n64 = arith.index_cast %n : index to i64
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c12 = arith.constant 12 : i64
  %c32 = arith.constant 32 : i64
  %lo = arith.constant 4294967295 : i64
  %c0i = arith.constant 0 : index
  %c1i = arith.constant 1 : index
  %c2i = arith.constant 2 : index
  %null = llvm.mlir.zero : !llvm.ptr
  %big = arith.cmpi ugt, %n64, %c12 : i64
  %pre = scf.if %big -> (!llvm.ptr) {
    %b = func.call @_ZN5nixev9EvalState13allocBindingsEm(%st, %n64) : (!llvm.ptr, i64) -> !llvm.ptr
    scf.yield %b : !llvm.ptr
  } else {
    scf.yield %null : !llvm.ptr
  }
  %stash = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %two = arith.muli %n, %c2i : index
  %rows = trikeshed.series %two : !s {
  ^bb0(%q: index):
    %h = arith.remui %q, %c2i : index
    %odd = arith.cmpi ne, %h, %c0i : index
    %word = scf.if %odd -> (i64) {
      %vw = llvm.load %stash : !llvm.ptr -> i64
      scf.yield %vw : i64
    } else {
      %r = arith.divui %q, %c2i : index
      %x = trikeshed.at %cells[%r] : !s, index -> i64
      %xp = llvm.inttoptr %x : i64 to !llvm.ptr
      %w0 = func.call @nixev_gr_pair(%st, %xp, %pos, %stash) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
      scf.yield %w0 : i64
    }
    trikeshed.yield %word : i64
  }
  %keyed = trikeshed.series %n : !s {
  ^bb0(%i: index):
    %k = arith.muli %i, %c2i : index
    %w = trikeshed.at %rows[%k] : !s, index -> i64
    %name = arith.andi %w, %lo : i64
    %hi = arith.shli %name, %c32 : i64
    %i64 = arith.index_cast %i : index to i64
    %kw = arith.ori %hi, %i64 : i64
    trikeshed.yield %kw : i64
  }
  %sorted = trikeshed.sorted %keyed : !s -> !s by {
  ^bb0(%a: i64, %b: i64):
    %c = func.call @gr_order(%a, %b) : (i64, i64) -> i32
    trikeshed.yield %c : i32
  }
  %idx = trikeshed.series %n : !s {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %firsts = trikeshed.where %idx : !s -> !s {
  ^bb0(%r: i64):
    %first = arith.cmpi eq, %r, %c0 : i64
    %rm1 = arith.subi %r, %c1 : i64
    %prev = arith.select %first, %r, %rm1 : i64
    %ri = arith.index_cast %r : i64 to index
    %pi = arith.index_cast %prev : i64 to index
    %a = trikeshed.at %sorted[%ri] : !s, index -> i64
    %b = trikeshed.at %sorted[%pi] : !s, index -> i64
    %ka = arith.shrui %a, %c32 : i64
    %kb = arith.shrui %b, %c32 : i64
    %new = arith.cmpi ne, %ka, %kb : i64
    %start = arith.ori %first, %new : i1
    trikeshed.yield %start : i1
  }
  %m = trikeshed.size %firsts : !s
  %m64 = arith.index_cast %m : index to i64
  %set = func.call @nixev_gr_set(%st, %v, %m64, %n64, %pre) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> !llvm.ptr
  %words = arith.muli %m, %c2i : index
  %wcells = trikeshed.series %words : !s {
  ^bb0(%q: index):
    %r = arith.divui %q, %c2i : index
    %h = arith.remui %q, %c2i : index
    %fi = trikeshed.at %firsts[%r] : !s, index -> i64
    %fii = arith.index_cast %fi : i64 to index
    %sw = trikeshed.at %sorted[%fii] : !s, index -> i64
    %row = arith.andi %sw, %lo : i64
    %rowi = arith.index_cast %row : i64 to index
    %at = arith.muli %rowi, %c2i : index
    %at2 = arith.addi %at, %h : index
    %w = trikeshed.at %rows[%at2] : !s, index -> i64
    trikeshed.yield %w : i64
  }
  %w64 = arith.index_cast %words : index to i64
  %attrs = llvm.getelementptr %set[16] : (!llvm.ptr) -> !llvm.ptr, i8
  %od = func.call @gr_desc(%attrs, %w64) : (!llvm.ptr, i64) -> !d
  %into = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %wcells, %into : !s, !m -> index
  return
}
