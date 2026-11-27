// evalConcatStrings' remaining composition hollowed out of lib/Eval/Eval.cpp into the TrikeShed dialect.  Two entries:
//
//   nixev_ts_concat_parts(ctx, np, forceString, views, res) -- the per-part COMPOSITION loop.  The forcing
//     (lookupForced/forceValue), the coercion (coerceToWindow), the context merging (own.add) and the error wording
//     (throwCannotAdd / throwIntOverflow) stay C++ callbacks (nixev_cc_part / nixev_cc_overflow); the accumulation
//     arithmetic (int add with the __builtin_add_overflow test, the int->float promotion, the float adds) and the
//     collection of the string/path windows (views[nv], total) are here.  The callback forces part k and returns its
//     kind (0 a window, 1 an int, 2 a float) and payload; a part that cannot be added throws in the callback before
//     the next part is forced, and an int overflow throws in nixev_cc_overflow -- Nix's error order and wording are
//     unchanged (a C++ exception unwinds through the compiled frame, as fold's callFunction does in ListOps.mlir).
//     res holds {firstType, n, nf, nv, total}; the bridge then makes the int/float/path/string result.
//
//   nixev_ts_path_concat(pieces, np, into) -> written -- the PATH case's fill-drain: the windows one after another as
//     a trikeshed.combineAll drained ONCE into the caller's Text (the bridge sizes it to the total and keeps the
//     existing canonPath + mkPath).  The pieces are already-forced windows, so the combineAll's two region passes
//     (size then drain) only read them -- no callback, no cache needed.
//
// A composite::Chars piece is 16 bytes: u32 count @0, const char *data @8.  The callback's record (rec) is 32 bytes:
// u8 ft @0, u8 kind @1, i64 payload @8, Chars w @16 (u32 count @16, ptr data @24).  res is 40 bytes: i64 firstType @0,
// i64 n @8, f64 nf @16, i64 nv @24, i64 total @32.  VType: Int 5, Float 6, String 9, Path 10.
!s = !trikeshed.series<i8>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
!coords = !trikeshed.series<!trikeshed.twinpacked<i32>>
!s64 = !trikeshed.series<i64>
!m64 = memref<?xi64, strided<[1], offset: ?>>

func.func private @nixev_cc_part(!llvm.ptr, i64, i64, i64, !llvm.ptr)
func.func private @nixev_cc_overflow(!llvm.ptr, i64, i64, i64)

// the descriptor of n i8 cells at p (module-unique)
func.func private @cc_desc8(%p: !llvm.ptr, %n: i64) -> !d {
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

// the descriptor of n i64 words at p (the same struct: the caller casts it to an i64 memref at its own use site)
func.func private @cc_words(%p: !llvm.ptr, %n: i64) -> !d {
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


func.func @nixev_ts_concat_parts(%ctx: !llvm.ptr, %np: i64, %fs: i64, %views: !llvm.ptr, %res: !llvm.ptr) {
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c8 = arith.constant 8 : i64
  %ft0 = arith.constant 9 : i64
  %k1 = arith.constant 1 : i8
  %k2 = arith.constant 2 : i8
  %c2i = arith.constant 2 : index
  %c3i = arith.constant 3 : index
  // the callback's record: four words (word 0 holds ft in its low byte and kind in the next, word 1 the payload, words
  // 2 and 3 the Chars: the count in the low half of word 2, the bytes' address in word 3).  i64-aligned so the word
  // reads are aligned.
  %rec = llvm.alloca %c4 x i64 : (i64) -> !llvm.ptr
  %npi = arith.index_cast %np : i64 to index
  %np2 = arith.muli %np, %c2 : i64
  // the views' cells: two words each (the count, then the address); the bridge's array holds np of them
  %vd = func.call @cc_words(%views, %np2) : (!llvm.ptr, i64) -> !d
  %vm = builtin.unrealized_conversion_cast %vd : !d to !m64
  %rd = func.call @cc_words(%rec, %c4) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %rs = builtin.unrealized_conversion_cast %rm : !m64 to !s64
  %r:5 = scf.for %k = %zi to %npi step %oi iter_args(%ft = %ft0, %n = %c0, %nfb = %c0, %nv = %c0, %tot = %c0) -> (i64, i64, i64, i64, i64) {
    %k64 = arith.index_cast %k : index to i64
    %kz = arith.cmpi eq, %k, %zi : index
    %fsz = arith.cmpi eq, %fs, %c0 : i64
    %isf = arith.andi %kz, %fsz : i1
    %isf64 = arith.extui %isf : i1 to i64
    func.call @nixev_cc_part(%ctx, %k64, %ft, %isf64, %rec) : (!llvm.ptr, i64, i64, i64, !llvm.ptr) -> ()
    %w0 = trikeshed.at %rs[%zi] : !s64, index -> i64
    %pay = trikeshed.at %rs[%oi] : !s64, index -> i64
    %ft8 = arith.trunci %w0 : i64 to i8
    %ft2 = arith.extui %ft8 : i8 to i64
    %kw = arith.shrui %w0, %c8 : i64
    %kind = arith.trunci %kw : i64 to i8
    %isInt = arith.cmpi eq, %kind, %k1 : i8
    %isFlt = arith.cmpi eq, %kind, %k2 : i8
    %num = arith.ori %isInt, %isFlt : i1
    %o:5 = scf.if %num -> (i64, i64, i64, i64, i64) {
      %ftI = arith.cmpi eq, %ft2, %c5 : i64
      %ia:3 = scf.if %ftI -> (i64, i64, i64) {
        // firstType Int: an int part adds (overflow throws), a float part promotes
        %ib:3 = scf.if %isInt -> (i64, i64, i64) {
          %s = arith.addi %n, %pay : i64
          %nx = arith.xori %n, %s : i64
          %px = arith.xori %pay, %s : i64
          %an = arith.andi %nx, %px : i64
          %ov = arith.cmpi slt, %an, %c0 : i64
          scf.if %ov {
            func.call @nixev_cc_overflow(%ctx, %k64, %n, %pay) : (!llvm.ptr, i64, i64, i64) -> ()
          }
          scf.yield %ft2, %s, %nfb : i64, i64, i64
        } else {
          %nd = arith.sitofp %n : i64 to f64
          %pd = arith.bitcast %pay : i64 to f64
          %sum = arith.addf %nd, %pd : f64
          %sb = arith.bitcast %sum : f64 to i64
          scf.yield %c6, %n, %sb : i64, i64, i64
        }
        scf.yield %ib#0, %ib#1, %ib#2 : i64, i64, i64
      } else {
        // firstType Float: nf += (int part ? (double)payload : the float payload)
        %ad = scf.if %isInt -> i64 {
          %pd = arith.sitofp %pay : i64 to f64
          %pb = arith.bitcast %pd : f64 to i64
          scf.yield %pb : i64
        } else {
          scf.yield %pay : i64
        }
        %nfd = arith.bitcast %nfb : i64 to f64
        %add = arith.bitcast %ad : i64 to f64
        %sum = arith.addf %nfd, %add : f64
        %sb = arith.bitcast %sum : f64 to i64
        scf.yield %ft2, %n, %sb : i64, i64, i64
      }
      scf.yield %ia#0, %ia#1, %ia#2, %nv, %tot : i64, i64, i64, i64, i64
    } else {
      // a string/path window: views[nv] = w, nv++, total += w.size() (the count word is the Chars' low half)
      %w2 = trikeshed.at %rs[%c2i] : !s64, index -> i64
      %len32 = arith.trunci %w2 : i64 to i32
      %len = arith.extui %len32 : i32 to i64
      %wp = trikeshed.at %rs[%c3i] : !s64, index -> i64
      %nvi = arith.index_cast %nv : i64 to index
      %vo = arith.muli %nv, %c2 : i64
      %voi = arith.index_cast %vo : i64 to index
      %vpi = arith.addi %voi, %oi : index
      memref.store %len, %vm[%voi] : !m64
      memref.store %wp, %vm[%vpi] : !m64
      %nv2 = arith.addi %nv, %c1 : i64
      %tot2 = arith.addi %tot, %len : i64
      scf.yield %ft2, %n, %nfb, %nv2, %tot2 : i64, i64, i64, i64, i64
    }
    scf.yield %o#0, %o#1, %o#2, %o#3, %o#4 : i64, i64, i64, i64, i64
  }
  // the result's five words: firstType, n, nf (its bits), nv, total
  %resd = func.call @cc_words(%res, %c5) : (!llvm.ptr, i64) -> !d
  %resm = builtin.unrealized_conversion_cast %resd : !d to !m64
  memref.store %r#0, %resm[%zi] : !m64
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %i4 = arith.constant 4 : index
  memref.store %r#1, %resm[%i1] : !m64
  memref.store %r#2, %resm[%i2] : !m64
  memref.store %r#3, %resm[%i3] : !m64
  memref.store %r#4, %resm[%i4] : !m64
  return
}

// the PATH fill-drain: the windows as one combineAll drained once into the caller's buffer (sized to the total).
func.func @nixev_ts_path_concat(%pieces: !llvm.ptr, %np: i64, %into: !llvm.ptr) -> i64 {
  %c16 = arith.constant 16 : i64
  %c8 = arith.constant 8 : i64
  %npi = arith.index_cast %np : i64 to index
  %all, %co = trikeshed.combineAll %npi : !s, !coords {
  ^bb0(%k: index):
    %k64 = arith.index_cast %k : index to i64
    %off = arith.muli %k64, %c16 : i64
    %ap = llvm.getelementptr %pieces[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %l32 = llvm.load %ap : !llvm.ptr -> i32
    %l = arith.extui %l32 : i32 to i64
    %dp = llvm.getelementptr %ap[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %p = llvm.load %dp : !llvm.ptr -> !llvm.ptr
    %pd = func.call @cc_desc8(%p, %l) : (!llvm.ptr, i64) -> !d
    %pm = builtin.unrealized_conversion_cast %pd : !d to !m
    %part = builtin.unrealized_conversion_cast %pm : !m to !s
    trikeshed.yield %part : !s
  }
  %sz = trikeshed.size %all : !s
  %szi = arith.index_cast %sz : index to i64
  %di = func.call @cc_desc8(%into, %szi) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m
  %end = trikeshed.drain %all, %mi : !s, !m -> index
  %endi = arith.index_cast %end : index to i64
  return %endi : i64
}
