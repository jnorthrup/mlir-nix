// The integer checked-arithmetic core of __add/__sub/__mul/__div, hollowed from lib/Eval/Builtins.cpp's arith template
// into MLIR (the ShowType.mlir recipe: a neutral C-ABI entry in the llvm dialect, linked by mlnix_lower_interface).
// The bridge keeps the forcing (forceInt/forceFloat), the int/float dispatch, mkInt/mkFloat and Nix's error wording;
// this entry computes the result and the overflow flag exactly as __builtin_{add,sub,mul}_overflow did:
//   add: ((x^r)&(y^r)) < 0     sub: ((x^y)&(x^r)) < 0     mul: llvm.intr.smul.with.overflow (struct{i64,i1})
//   div: y == 0 -> flag 2 BEFORE dividing; INT64_MIN / -1 -> flag 1 (branched, never an sdiv on that pair); else x/y.
// @mlnix_arith_int(op, x, y, *r) -> flag: 0 ok, 1 overflow, 2 division by zero.  op is the ASCII operator:
// '+' 43, '-' 45, '*' 42, '/' 47.  On flag 2 nothing is stored; on flag 1 of div, r = 0 (the bridge throws before reading it).
module {
  llvm.func @mlnix_arith_int(%op: i32, %x: i64, %y: i64, %r: !llvm.ptr) -> i32 {
    %c0 = llvm.mlir.constant(0 : i64) : i64
    %c032 = llvm.mlir.constant(0 : i32) : i32
    %c132 = llvm.mlir.constant(1 : i32) : i32
    %c232 = llvm.mlir.constant(2 : i32) : i32
    %c43 = llvm.mlir.constant(43 : i32) : i32
    %c45 = llvm.mlir.constant(45 : i32) : i32
    %c42 = llvm.mlir.constant(42 : i32) : i32
    %min = llvm.mlir.constant(-9223372036854775808 : i64) : i64
    %neg1 = llvm.mlir.constant(-1 : i64) : i64
    %is_add = llvm.icmp "eq" %op, %c43 : i32
    llvm.cond_br %is_add, ^bb_add, ^bb_not_add
  ^bb_add:
    %sum = llvm.add %x, %y : i64
    llvm.store %sum, %r : i64, !llvm.ptr
    %xa = llvm.xor %x, %sum : i64
    %ya = llvm.xor %y, %sum : i64
    %aa = llvm.and %xa, %ya : i64
    %ofa = llvm.icmp "slt" %aa, %c0 : i64
    %fa = llvm.zext %ofa : i1 to i32
    llvm.return %fa : i32
  ^bb_not_add:
    %is_sub = llvm.icmp "eq" %op, %c45 : i32
    llvm.cond_br %is_sub, ^bb_sub, ^bb_not_sub
  ^bb_sub:
    %diff = llvm.sub %x, %y : i64
    llvm.store %diff, %r : i64, !llvm.ptr
    %xy = llvm.xor %x, %y : i64
    %xr = llvm.xor %x, %diff : i64
    %as = llvm.and %xy, %xr : i64
    %ofs = llvm.icmp "slt" %as, %c0 : i64
    %fs = llvm.zext %ofs : i1 to i32
    llvm.return %fs : i32
  ^bb_not_sub:
    %is_mul = llvm.icmp "eq" %op, %c42 : i32
    llvm.cond_br %is_mul, ^bb_mul, ^bb_div
  ^bb_mul:
    %m = "llvm.intr.smul.with.overflow"(%x, %y) : (i64, i64) -> !llvm.struct<(i64, i1)>
    %mv = llvm.extractvalue %m[0] : !llvm.struct<(i64, i1)>
    llvm.store %mv, %r : i64, !llvm.ptr
    %mo = llvm.extractvalue %m[1] : !llvm.struct<(i64, i1)>
    %fm = llvm.zext %mo : i1 to i32
    llvm.return %fm : i32
  ^bb_div:
    %y0 = llvm.icmp "eq" %y, %c0 : i64
    llvm.cond_br %y0, ^bb_divzero, ^bb_divchk
  ^bb_divzero:
    llvm.return %c232 : i32
  ^bb_divchk:
    %xmin = llvm.icmp "eq" %x, %min : i64
    %ym1 = llvm.icmp "eq" %y, %neg1 : i64
    %edge = llvm.and %xmin, %ym1 : i1
    llvm.cond_br %edge, ^bb_divof, ^bb_divok
  ^bb_divof:
    llvm.store %c0, %r : i64, !llvm.ptr
    llvm.return %c132 : i32
  ^bb_divok:
    %q = llvm.sdiv %x, %y : i64
    llvm.store %q, %r : i64, !llvm.ptr
    llvm.return %c032 : i32
  }
}
