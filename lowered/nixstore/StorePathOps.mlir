// The store-path name algebra of lib/Store/StorePaths.cpp hollowed into the TrikeShed dialect: makeStorePath's
// fingerprint `type:algo:hex:storeDir:name` and path `storeDir/nix32-name`, makeType's `type[:ref]*[:self]`, and
// runProgram's argv pointer fill.  The C++ bridges keep checkName, compressHash/hashString and the Text sizing; the
// append-by-append composition is gone, replaced by ONE lazy combine of the pieces drained once into a pre-sized
// buffer (fill-drain).  The store path hashes MUST stay byte-identical: the fingerprint is what is hashed, the path
// is the nix32 of the compressed hash.  The hex/nix32 digits are the Encoders.mlir algebra inlined as a piece (a
// series is never returned from a helper -- it is built and combined in the entry body).  Nothing throws here.
!b = !trikeshed.series<i8>
!q = !trikeshed.series<i64>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @sp_hex : memref<16xi8> =
  dense<[48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101, 102]>
memref.global "private" constant @sp_nix32 : memref<32xi8> =
  dense<[48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 102, 103, 104, 105, 106, 107, 108, 109, 110, 112, 113, 114, 115, 118, 119, 120, 121, 122]>
memref.global "private" constant @sp_colon : memref<1xi8> = dense<58>
memref.global "private" constant @sp_slash : memref<1xi8> = dense<47>
memref.global "private" constant @sp_dash : memref<1xi8> = dense<45>
memref.global "private" constant @sp_self : memref<5xi8> = dense<[58, 115, 101, 108, 102]>

func.func private @sp_desc(%p: !llvm.ptr, %n: i64) -> !d {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %u = llvm.mlir.undef : !d
  %a = llvm.insertvalue %p, %u[0] : !d
  %bb = llvm.insertvalue %p, %a[1] : !d
  %c = llvm.insertvalue %c0, %bb[2] : !d
  %e = llvm.insertvalue %n, %c[3, 0] : !d
  %f = llvm.insertvalue %c1, %e[4, 0] : !d
  return %f : !d
}

// fingerprint: type ':' algo ':' hex(hash) ':' storeDir ':' name -- one combine of nine pieces, drained once.
func.func @nixstore_ts_pathfp(%tp: !llvm.ptr, %tn: i64, %ap: !llvm.ptr, %an: i64, %hp: !llvm.ptr, %hn: i64,
    %sp: !llvm.ptr, %sn: i64, %np: !llvm.ptr, %nn: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c0i64 = arith.constant 0 : i64
  %td = func.call @sp_desc(%tp, %tn) : (!llvm.ptr, i64) -> !d
  %tm = builtin.unrealized_conversion_cast %td : !d to !m
  %ts = builtin.unrealized_conversion_cast %tm : !m to !b
  %ad = func.call @sp_desc(%ap, %an) : (!llvm.ptr, i64) -> !d
  %am = builtin.unrealized_conversion_cast %ad : !d to !m
  %as = builtin.unrealized_conversion_cast %am : !m to !b
  %sd = func.call @sp_desc(%sp, %sn) : (!llvm.ptr, i64) -> !d
  %sm = builtin.unrealized_conversion_cast %sd : !d to !m
  %ss = builtin.unrealized_conversion_cast %sm : !m to !b
  %nd = func.call @sp_desc(%np, %nn) : (!llvm.ptr, i64) -> !d
  %nm = builtin.unrealized_conversion_cast %nd : !d to !m
  %ns = builtin.unrealized_conversion_cast %nm : !m to !b
  // the hex chars of the hash bytes: two lower-case nibbles per byte, high first
  %hd = func.call @sp_desc(%hp, %hn) : (!llvm.ptr, i64) -> !d
  %hm = builtin.unrealized_conversion_cast %hd : !d to !m
  %hb = builtin.unrealized_conversion_cast %hm : !m to !b
  %hg = memref.get_global @sp_hex : memref<16xi8>
  %htab = trikeshed.text %hg : memref<16xi8> -> !b
  %hni = arith.index_cast %hn : i64 to index
  %h2 = arith.constant 2 : index
  %hL = arith.muli %hni, %h2 : index
  %hdigits = trikeshed.series %hL : !q {
  ^bb0(%j: index):
    %bi = arith.divui %j, %h2 : index
    %byte = trikeshed.at %hb[%bi] : !b, index -> i8
    %v = arith.extui %byte : i8 to i64
    %odd = arith.remui %j, %h2 : index
    %odd64 = arith.index_cast %odd : index to i64
    %c4 = arith.constant 4 : i64
    %sh = arith.muli %odd64, %c4 : i64
    %shift = arith.subi %c4, %sh : i64
    %nib = arith.shrui %v, %shift : i64
    %c15 = arith.constant 15 : i64
    %dig = arith.andi %nib, %c15 : i64
    trikeshed.yield %dig : i64
  }
  %hs = trikeshed.alpha %hdigits : !q -> !b {
  ^bb0(%dig: i64):
    %di = arith.index_cast %dig : i64 to index
    %ch = trikeshed.at %htab[%di] : !b, index -> i8
    trikeshed.yield %ch : i8
  }
  %cg = memref.get_global @sp_colon : memref<1xi8>
  %ct = trikeshed.text %cg : memref<1xi8> -> !b
  %col = trikeshed.slice %ct[%c0, %c1] : !b -> !b
  %all = trikeshed.combine %ts, %col, %as, %col, %hs, %col, %ss, %col, %ns : !b, !b, !b, !b, !b, !b, !b, !b, !b -> !b
  %sz = trikeshed.size %all : !b
  %sz64 = arith.index_cast %sz : index to i64
  %neg = arith.subi %c0i64, %sz64 : i64
  %short = arith.cmpi ult, %cap, %sz64 : i64
  %r = scf.if %short -> i64 {
    scf.yield %neg : i64
  } else {
    %od = func.call @sp_desc(%into, %cap) : (!llvm.ptr, i64) -> !d
    %om = builtin.unrealized_conversion_cast %od : !d to !m
    %end = trikeshed.drain %all, %om : !b, !m -> index
    %w = arith.index_cast %end : index to i64
    scf.yield %w : i64
  }
  return %r : i64
}

// path: storeDir '/' nix32(hash) '-' name -- one combine of five pieces, drained once.
func.func @nixstore_ts_storepath(%sp: !llvm.ptr, %sn: i64, %hp: !llvm.ptr, %hn: i64, %np: !llvm.ptr, %nn: i64,
    %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c0i64 = arith.constant 0 : i64
  %sd = func.call @sp_desc(%sp, %sn) : (!llvm.ptr, i64) -> !d
  %sm = builtin.unrealized_conversion_cast %sd : !d to !m
  %ss = builtin.unrealized_conversion_cast %sm : !m to !b
  %nd = func.call @sp_desc(%np, %nn) : (!llvm.ptr, i64) -> !d
  %nm = builtin.unrealized_conversion_cast %nd : !d to !m
  %ns = builtin.unrealized_conversion_cast %nm : !m to !b
  // the nix32 chars of the hash bytes: ceil(8n/5) chars, most significant 5-bit group first
  %hd = func.call @sp_desc(%hp, %hn) : (!llvm.ptr, i64) -> !d
  %hm = builtin.unrealized_conversion_cast %hd : !d to !m
  %hb = builtin.unrealized_conversion_cast %hm : !m to !b
  %hg = memref.get_global @sp_nix32 : memref<32xi8>
  %htab = trikeshed.text %hg : memref<32xi8> -> !b
  %hni = arith.index_cast %hn : i64 to index
  %n1 = arith.constant 1 : index
  %n4 = arith.constant 4 : index
  %n5 = arith.constant 5 : index
  %n8 = arith.constant 8 : index
  %hn8 = arith.muli %hni, %n8 : index
  %hn8p4 = arith.addi %hn8, %n4 : index
  %hlen = arith.divui %hn8p4, %n5 : index
  %hdigits = trikeshed.series %hlen : !q {
  ^bb0(%pos: index):
    %lm1 = arith.subi %hlen, %n1 : index
    %i = arith.subi %lm1, %pos : index
    %b = arith.muli %i, %n5 : index
    %bi = arith.divui %b, %n8 : index
    %bj = arith.remui %b, %n8 : index
    %byte = trikeshed.at %hb[%bi] : !b, index -> i8
    %v = arith.extui %byte : i8 to i64
    %bj64 = arith.index_cast %bj : index to i64
    %c8i = arith.constant 8 : i64
    %lo = arith.shrui %v, %bj64 : i64
    %bip1 = arith.addi %bi, %n1 : index
    %nm1 = arith.subi %hni, %n1 : index
    %valid = arith.cmpi ult, %bip1, %hni : index
    %safe = arith.minsi %bip1, %nm1 : index
    %nb = trikeshed.at %hb[%safe] : !b, index -> i8
    %nv = arith.extui %nb : i8 to i64
    %sh = arith.subi %c8i, %bj64 : i64
    %hi = arith.shli %nv, %sh : i64
    %zero = arith.constant 0 : i64
    %hic = arith.select %valid, %hi, %zero : i64
    %c = arith.ori %lo, %hic : i64
    %c31 = arith.constant 31 : i64
    %dig = arith.andi %c, %c31 : i64
    trikeshed.yield %dig : i64
  }
  %hs = trikeshed.alpha %hdigits : !q -> !b {
  ^bb0(%dig: i64):
    %di = arith.index_cast %dig : i64 to index
    %ch = trikeshed.at %htab[%di] : !b, index -> i8
    trikeshed.yield %ch : i8
  }
  %sg = memref.get_global @sp_slash : memref<1xi8>
  %st = trikeshed.text %sg : memref<1xi8> -> !b
  %slash = trikeshed.slice %st[%c0, %c1] : !b -> !b
  %dg = memref.get_global @sp_dash : memref<1xi8>
  %dt = trikeshed.text %dg : memref<1xi8> -> !b
  %dash = trikeshed.slice %dt[%c0, %c1] : !b -> !b
  %all = trikeshed.combine %ss, %slash, %hs, %dash, %ns : !b, !b, !b, !b, !b -> !b
  %sz = trikeshed.size %all : !b
  %sz64 = arith.index_cast %sz : index to i64
  %neg = arith.subi %c0i64, %sz64 : i64
  %short = arith.cmpi ult, %cap, %sz64 : i64
  %r = scf.if %short -> i64 {
    scf.yield %neg : i64
  } else {
    %od = func.call @sp_desc(%into, %cap) : (!llvm.ptr, i64) -> !d
    %om = builtin.unrealized_conversion_cast %od : !d to !m
    %end = trikeshed.drain %all, %om : !b, !m -> index
    %w = arith.index_cast %end : index to i64
    scf.yield %w : i64
  }
  return %r : i64
}

// makeType: type then ':' ref for each ref (a Text row: ptr@0, u32 size@8, 16-byte stride) then ':self' when asked.
// The refs are a combineAll of (':' + ref) pieces; the whole is one combine drained once.  -needed when cap is short.
func.func @nixstore_ts_maketype(%tp: !llvm.ptr, %tn: i64, %refs: !llvm.ptr, %nrefs: i64, %selfref: i64,
    %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c0i64 = arith.constant 0 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c5 = arith.constant 5 : index
  %td = func.call @sp_desc(%tp, %tn) : (!llvm.ptr, i64) -> !d
  %tm = builtin.unrealized_conversion_cast %td : !d to !m
  %ts = builtin.unrealized_conversion_cast %tm : !m to !b
  %cg = memref.get_global @sp_colon : memref<1xi8>
  %ct = trikeshed.text %cg : memref<1xi8> -> !b
  %col = trikeshed.slice %ct[%c0, %c1] : !b -> !b
  %nri = arith.index_cast %nrefs : i64 to index
  %rs, %rc = trikeshed.combineAll %nri : !b, !trikeshed.series<!trikeshed.twinpacked<i32>> {
  ^bb0(%k: index):
    %k64 = arith.index_cast %k : index to i64
    %off = arith.muli %k64, %c16 : i64
    %rp = llvm.getelementptr %refs[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %p = llvm.load %rp : !llvm.ptr -> !llvm.ptr
    %np = llvm.getelementptr %rp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %n32 = llvm.load %np : !llvm.ptr -> i32
    %n = arith.extui %n32 : i32 to i64
    %rd = func.call @sp_desc(%p, %n) : (!llvm.ptr, i64) -> !d
    %rm = builtin.unrealized_conversion_cast %rd : !d to !m
    %rslice = builtin.unrealized_conversion_cast %rm : !m to !b
    %piece = trikeshed.combine %col, %rslice : !b, !b -> !b
    trikeshed.yield %piece : !b
  }
  %sg = memref.get_global @sp_self : memref<5xi8>
  %st = trikeshed.text %sg : memref<5xi8> -> !b
  %has = arith.cmpi ne, %selfref, %c0i64 : i64
  %slen = arith.select %has, %c5, %c0 : index
  %self = trikeshed.slice %st[%c0, %slen] : !b -> !b
  %all = trikeshed.combine %ts, %rs, %self : !b, !b, !b -> !b
  %sz = trikeshed.size %all : !b
  %sz64 = arith.index_cast %sz : index to i64
  %neg = arith.subi %c0i64, %sz64 : i64
  %short = arith.cmpi ult, %cap, %sz64 : i64
  %r = scf.if %short -> i64 {
    scf.yield %neg : i64
  } else {
    %od = func.call @sp_desc(%into, %cap) : (!llvm.ptr, i64) -> !d
    %om = builtin.unrealized_conversion_cast %od : !d to !m
    %end = trikeshed.drain %all, %om : !b, !m -> index
    %w = arith.index_cast %end : index to i64
    scf.yield %w : i64
  }
  return %r : i64
}

// runProgram's argv: into[0] = prog, into[k+1] = args[k].c_str() (a Text row's data ptr@0, NUL-terminated), into[n+1]
// = null.  A pointer fill into the caller's room, allocation-free (it runs in the fork child).  Returns the count n+2.
func.func @nixstore_ts_argv(%prog: !llvm.ptr, %args: !llvm.ptr, %nargs: i64, %into: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  llvm.store %prog, %into : !llvm.ptr, !llvm.ptr
  %ni = arith.index_cast %nargs : i64 to index
  %z = arith.constant 0 : index
  %s1 = arith.constant 1 : index
  scf.for %k = %z to %ni step %s1 {
    %k64 = arith.index_cast %k : index to i64
    %off = arith.muli %k64, %c16 : i64
    %rp = llvm.getelementptr %args[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %p = llvm.load %rp : !llvm.ptr -> !llvm.ptr
    %slot = arith.addi %k64, %c1 : i64
    %so = arith.muli %slot, %c8 : i64
    %dst = llvm.getelementptr %into[%so] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %p, %dst : !llvm.ptr, !llvm.ptr
  }
  %last = arith.addi %nargs, %c1 : i64
  %lo = arith.muli %last, %c8 : i64
  %ldst = llvm.getelementptr %into[%lo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %null, %ldst : !llvm.ptr, !llvm.ptr
  %cnt = arith.addi %nargs, %c1 : i64
  %cnt2 = arith.addi %cnt, %c1 : i64
  return %cnt2 : i64
}