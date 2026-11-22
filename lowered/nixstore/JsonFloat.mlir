// nixstore::jsonFloat (lib/Store/StorePaths.cpp) hollowed into the TrikeShed dialect: a float as toJSON writes it, the
// shortest "%.*e" reading that round-trips (nlohmann's grisu2 digits), then nlohmann::detail::format_buffer's layout.
// StorePaths.cpp keeps only the snprintf (a variadic call, nixstore_jf_sci); strtod is called here.  The digits are a
// where over the mantissa's byte positions mapped to their bytes (alpha), the trailing zeros cut by a fold, the exponent
// read by a fold, and the text one combine of slices drained once:
//   sign, a literal, zeros, digits, zeros, a literal, digits, a literal, the exponent's digits
// each case of format_buffer choosing the slices' extents:
//   k <= n <= 15        digits[0,k] zeros[n-k] ".0"
//   0 < n <= 15         digits[0,n] "." digits[n,k-n]
//   -4 < n <= 0         "0." zeros[-n] digits[0,k]
//   otherwise           digits[0,1] ["." digits[1,k-1]] "e+"/"e-" ["0"] |n-1|
// with k the digits kept and n the decimal exponent + 1.  NaN and the infinities are "null", the zeros "0.0" / "-0.0".
!b = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// "-.00.e+0e-0null-0.0": "-" 0, "." 1, ".0" 1+2, "0." 3+2, "e+0" 5, "e-0" 8, "null" 11, "-0.0" 15, "0.0" 16
memref.global "private" constant @jf_lits : memref<19xi8> = dense<"0x2d2e30302e652b30652d306e756c6c2d302e30">
memref.global "private" constant @jf_zeros : memref<24xi8> = dense<48>

func.func private @nixstore_jf_sci(f64, i64, !llvm.ptr) -> i64
func.func private @strtod(!llvm.ptr, !llvm.ptr) -> f64

func.func private @jf_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// the literal at [off, off + len) drained into `into`: its length
func.func private @jf_lit(%off: index, %len: index, %into: !llvm.ptr) -> i64 {
  %g = memref.get_global @jf_lits : memref<19xi8>
  %lits = trikeshed.text %g : memref<19xi8> -> !b
  %s = trikeshed.slice %lits[%off, %len] : !b -> !b
  %n = arith.index_cast %len : index to i64
  %od = func.call @jf_desc(%into, %n) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %s, %om : !b, !m -> index
  return %n : i64
}

// The text of d drained into `into` (room for 32 bytes); `buf` is room for snprintf (64 bytes).  Returns its length.
func.func @nixstore_ts_jsonfloat(%x: f64, %into: !llvm.ptr, %buf: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c17 = arith.constant 17 : i64
  %i0 = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %i4 = arith.constant 4 : index
  %zf = arith.constant 0.0 : f64
  %true = arith.constant true
  %inf = arith.constant 0x7FF0000000000000 : f64
  %ninf = arith.constant 0xFFF0000000000000 : f64
  %nan = arith.cmpf uno, %x, %x : f64
  %pinf = arith.cmpf oeq, %x, %inf : f64
  %minf = arith.cmpf oeq, %x, %ninf : f64
  %isinf = arith.ori %pinf, %minf : i1
  %bad = arith.ori %nan, %isinf : i1
  %r = scf.if %bad -> (i64) {
    %i11 = arith.constant 11 : index
    %n = func.call @jf_lit(%i11, %i4, %into) : (index, index, !llvm.ptr) -> i64
    scf.yield %n : i64
  } else {
    %zero = arith.cmpf oeq, %x, %zf : f64
    %r2 = scf.if %zero -> (i64) {
      %bits = arith.bitcast %x : f64 to i64
      %neg0 = arith.cmpi slt, %bits, %c0 : i64
      %i15 = arith.constant 15 : index
      %i16 = arith.constant 16 : index
      %off = arith.select %neg0, %i15, %i16 : index
      %len = arith.select %neg0, %i4, %i3 : index
      %n = func.call @jf_lit(%off, %len, %into) : (index, index, !llvm.ptr) -> i64
      scf.yield %n : i64
    } else {
      // the shortest precision whose reading is x (17 at most)
      %null = llvm.inttoptr %c0 : i64 to !llvm.ptr
      %w:2 = scf.while (%prec = %c1) : (i64) -> (i64, i64) {
        %len = func.call @nixstore_jf_sci(%x, %prec, %buf) : (f64, i64, !llvm.ptr) -> i64
        %back = func.call @strtod(%buf, %null) : (!llvm.ptr, !llvm.ptr) -> f64
        %same = arith.cmpf oeq, %back, %x : f64
        %last = arith.cmpi sge, %prec, %c17 : i64
        %stop = arith.ori %same, %last : i1
        %more = arith.xori %stop, %true : i1
        scf.condition(%more) %prec, %len : i64, i64
      } do {
      ^bb0(%p: i64, %l: i64):
        %p1 = arith.addi %p, %c1 : i64
        scf.yield %p1 : i64
      }
      %len = arith.index_cast %w#1 : i64 to index
      %bd = func.call @jf_desc(%buf, %w#1) : (!llvm.ptr, i64) -> !d
      %bm = builtin.unrealized_conversion_cast %bd : !d to !m
      %all = builtin.unrealized_conversion_cast %bm : !m to !b
      // [-]d.ddde[+-]XX: the sign, the mantissa's digits, the exponent
      %first = trikeshed.at %all[%i0] : !b, index -> i8
      %minus = arith.constant 45 : i8
      %neg = arith.cmpi eq, %first, %minus : i8
      %from = arith.select %neg, %i1, %i0 : index
      %rest = arith.subi %len, %from : index
      %s = trikeshed.slice %all[%from, %rest] : !b -> !b
      %pos = trikeshed.series %rest : !s64 {
      ^bb0(%i: index):
        %i64 = arith.index_cast %i : index to i64
        trikeshed.yield %i64 : i64
      }
      %es = trikeshed.where %pos : !s64 -> !s64 {
      ^bb0(%i: i64):
        %ii = arith.index_cast %i : i64 to index
        %ch = trikeshed.at %s[%ii] : !b, index -> i8
        %ce = arith.constant 101 : i8
        %is = arith.cmpi eq, %ch, %ce : i8
        trikeshed.yield %is : i1
      }
      %epos64 = trikeshed.at %es[%i0] : !s64, index -> i64
      %epos = arith.index_cast %epos64 : i64 to index
      %mant = trikeshed.slice %s[%i0, %epos] : !b -> !b
      %mpos = trikeshed.series %epos : !s64 {
      ^bb0(%i: index):
        %i64 = arith.index_cast %i : index to i64
        trikeshed.yield %i64 : i64
      }
      %dpos = trikeshed.where %mpos : !s64 -> !s64 {
      ^bb0(%i: i64):
        %ii = arith.index_cast %i : i64 to index
        %ch = trikeshed.at %mant[%ii] : !b, index -> i8
        %c48 = arith.constant 48 : i8
        %c57 = arith.constant 57 : i8
        %ge = arith.cmpi sge, %ch, %c48 : i8
        %le = arith.cmpi sle, %ch, %c57 : i8
        %is = arith.andi %ge, %le : i1
        trikeshed.yield %is : i1
      }
      %digits = trikeshed.alpha %dpos : !s64 -> !b {
      ^bb0(%i: i64):
        %ii = arith.index_cast %i : i64 to index
        %ch = trikeshed.at %mant[%ii] : !b, index -> i8
        trikeshed.yield %ch : i8
      }
      // k: the digits up to the last one that is not '0', at least one
      %nd = trikeshed.size %digits : !b
      %dix = trikeshed.series %nd : !s64 {
      ^bb0(%i: index):
        %i64 = arith.index_cast %i : index to i64
        trikeshed.yield %i64 : i64
      }
      %k64 = trikeshed.fold %dix, %c1 : !s64, i64 -> i64 {
      ^bb0(%acc: i64, %i: i64):
        %ii = arith.index_cast %i : i64 to index
        %ch = trikeshed.at %digits[%ii] : !b, index -> i8
        %c48 = arith.constant 48 : i8
        %nz = arith.cmpi ne, %ch, %c48 : i8
        %one = arith.constant 1 : i64
        %i1p = arith.addi %i, %one : i64
        %k = arith.select %nz, %i1p, %acc : i64
        trikeshed.yield %k : i64
      }
      // the exponent: a sign, then decimal digits
      %eat = arith.addi %epos, %i1 : index
      %elen = arith.subi %rest, %eat : index
      %etext = trikeshed.slice %s[%eat, %elen] : !b -> !b
      %esign = trikeshed.at %etext[%i0] : !b, index -> i8
      %eneg = arith.cmpi eq, %esign, %minus : i8
      %emag = trikeshed.fold %etext, %c0 : !b, i64 -> i64 {
      ^bb0(%acc: i64, %ch: i8):
        %c48 = arith.constant 48 : i8
        %c57 = arith.constant 57 : i8
        %ge = arith.cmpi sge, %ch, %c48 : i8
        %le = arith.cmpi sle, %ch, %c57 : i8
        %is = arith.andi %ge, %le : i1
        %ten = arith.constant 10 : i64
        %c48w = arith.constant 48 : i64
        %chw = arith.extui %ch : i8 to i64
        %dv = arith.subi %chw, %c48w : i64
        %m10 = arith.muli %acc, %ten : i64
        %nv = arith.addi %m10, %dv : i64
        %v = arith.select %is, %nv, %acc : i64
        trikeshed.yield %v : i64
      }
      %enegv = arith.subi %c0, %emag : i64
      %exp10 = arith.select %eneg, %enegv, %emag : i64
      %n = arith.addi %exp10, %c1 : i64
      // format_buffer's cases
      %c15 = arith.constant 15 : i64
      %cm4 = arith.constant -4 : i64
      %nle15 = arith.cmpi sle, %n, %c15 : i64
      %kle = arith.cmpi sle, %k64, %n : i64
      %case1 = arith.andi %kle, %nle15 : i1
      %npos = arith.cmpi sgt, %n, %c0 : i64
      %case2 = arith.andi %npos, %nle15 : i1
      %ngt = arith.cmpi sgt, %n, %cm4 : i64
      %nle0 = arith.cmpi sle, %n, %c0 : i64
      %case3 = arith.andi %ngt, %nle0 : i1
      %k = arith.index_cast %k64 : i64 to index
      %ni = arith.index_cast %n : i64 to index
      %negn = arith.subi %i0, %ni : index
      %kmn = arith.subi %k, %ni : index
      %km1 = arith.subi %k, %i1 : index
      %kgt1 = arith.cmpi sgt, %k, %i1 : index
      // case 4: the exponent e = n - 1, its magnitude's digits
      %e = arith.subi %n, %c1 : i64
      %eneg4 = arith.cmpi slt, %e, %c0 : i64
      %ee = arith.subi %c0, %e : i64
      %ae = arith.select %eneg4, %ee, %e : i64
      %c10 = arith.constant 10 : i64
      %c100 = arith.constant 100 : i64
      %ge10 = arith.cmpi sge, %ae, %c10 : i64
      %ge100 = arith.cmpi sge, %ae, %c100 : i64
      %nd2 = arith.select %ge10, %i2, %i1 : index
      %ndig = arith.select %ge100, %i3, %nd2 : index
      // the nine slices' (offset, count), case by case (1, 2, 3, else 4)
      %i5 = arith.constant 5 : index
      %i8 = arith.constant 8 : index
      %p3off = arith.select %eneg4, %i8, %i5 : index
      %p3len = arith.select %ge10, %i2, %i3 : index
      %d2c4 = arith.select %kgt1, %km1, %i0 : index
      %p2c4 = arith.select %kgt1, %i1, %i0 : index
      // P1: "0." in case 3
      %c3n = arith.xori %case1, %true : i1
      %c3a = arith.xori %case2, %true : i1
      %only3 = arith.andi %c3n, %c3a : i1
      %is3 = arith.andi %only3, %case3 : i1
      %not12 = arith.andi %c3n, %c3a : i1
      %c3x = arith.xori %case3, %true : i1
      %is4 = arith.andi %not12, %c3x : i1
      %is2 = arith.andi %c3n, %case2 : i1
      %p1len = arith.select %is3, %i2, %i0 : index
      %z1len = arith.select %is3, %negn, %i0 : index
      // D1: digits[0, k | n | k | 1]
      %d1a = arith.select %is4, %i1, %k : index
      %d1len = arith.select %is2, %ni, %d1a : index
      %nmk = arith.subi %ni, %k : index
      %z2len2 = arith.select %case1, %nmk, %i0 : index
      // P2: ".0" (1) / "." (2) / "" (3) / "." or "" (4)
      %p2a = arith.select %is4, %p2c4, %i0 : index
      %p2b = arith.select %is2, %i1, %p2a : index
      %p2len = arith.select %case1, %i2, %p2b : index
      // D2: digits[n, k-n] (2) / digits[1, k-1] (4)
      %d2a = arith.select %is4, %d2c4, %i0 : index
      %d2len = arith.select %is2, %kmn, %d2a : index
      %d2o4 = arith.select %is4, %i1, %i0 : index
      %d2o = arith.select %is2, %ni, %d2o4 : index
      %p3l = arith.select %is4, %p3len, %i0 : index
      %xl = arith.select %is4, %ndig, %i0 : index
      %slen = arith.select %neg, %i1, %i0 : index
      %lg = memref.get_global @jf_lits : memref<19xi8>
      %lits = trikeshed.text %lg : memref<19xi8> -> !b
      %zg = memref.get_global @jf_zeros : memref<24xi8>
      %zeros = trikeshed.text %zg : memref<24xi8> -> !b
      %ps = trikeshed.slice %lits[%i0, %slen] : !b -> !b
      %pp1 = trikeshed.slice %lits[%i3, %p1len] : !b -> !b
      %pz1 = trikeshed.slice %zeros[%i0, %z1len] : !b -> !b
      %pd1 = trikeshed.slice %digits[%i0, %d1len] : !b -> !b
      %pz2 = trikeshed.slice %zeros[%i0, %z2len2] : !b -> !b
      %pp2 = trikeshed.slice %lits[%i1, %p2len] : !b -> !b
      %pd2 = trikeshed.slice %digits[%d2o, %d2len] : !b -> !b
      %pp3 = trikeshed.slice %lits[%p3off, %p3l] : !b -> !b
      %px = trikeshed.series %xl : !b {
      ^bb0(%i: index):
        // digit i of ae, most significant first
        %i64 = arith.index_cast %i : index to i64
        %nd64 = arith.index_cast %ndig : index to i64
        %last = arith.subi %nd64, %c1 : i64
        %pw = arith.subi %last, %i64 : i64
        %one = arith.constant 1 : i64
        %ten = arith.constant 10 : i64
        %is0 = arith.cmpi eq, %pw, %c0 : i64
        %is1 = arith.cmpi eq, %pw, %one : i64
        %hund = arith.constant 100 : i64
        %dv1 = arith.select %is1, %ten, %hund : i64
        %div = arith.select %is0, %one, %dv1 : i64
        %q = arith.divui %ae, %div : i64
        %dgt = arith.remui %q, %ten : i64
        %c48 = arith.constant 48 : i64
        %ch = arith.addi %dgt, %c48 : i64
        %b8 = arith.trunci %ch : i64 to i8
        trikeshed.yield %b8 : i8
      }
      %text = trikeshed.combine %ps, %pp1, %pz1, %pd1, %pz2, %pp2, %pd2, %pp3, %px : !b, !b, !b, !b, !b, !b, !b, !b, !b -> !b
      %tn = trikeshed.size %text : !b
      %tn64 = arith.index_cast %tn : index to i64
      %od = func.call @jf_desc(%into, %tn64) : (!llvm.ptr, i64) -> !d
      %om = builtin.unrealized_conversion_cast %od : !d to !m
      %end = trikeshed.drain %text, %om : !b, !m -> index
      scf.yield %tn64 : i64
    }
    scf.yield %r2 : i64
  }
  return %r : i64
}
