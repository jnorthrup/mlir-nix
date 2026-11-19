// The value printer's fixed byte emission hollowed out of lib/Eval/Eval.cpp: the literals and separators of
// EvalState::printValue and the TracePrinter (printValueForTrace), the integer digits, and the elision counts.
// The C++ keeps the recursion / forcing / seen-table (firstTime/WordTable) / depth guard and the attribute-name
// sorting; the bytes are here, drained from a constant word table (trikeshed.slice / text / at / drain), the digits
// a fold over the powers of ten (as PrintOps.mlir's nixev_ts_int), the elision one combine.  One entry
// nixev_ts_pv(kind, a, b, into, cap) writes into room the caller reserved and returns how many it wrote:
//   kind 0: the fixed word a (id into the table below)
//   kind 1: the integer a in decimal (a sign and at most 19 digits)
//   kind 2: the elision "«N unit elided»" of a count a, unit b (0 byte/bytes, 1 attribute/attributes, 2 item/items;
//           singular when a == 1).  Room: 2 + 20 + 1 + 10 + 8.
// Word ids (the C++ enum PvWord mirrors these):
//   0 true  1 false  2 null  3 «repeated»  4 "{ "  5 " = "  6 "; "  7 "}"  8 "[ "  9 " "  10 "]"
//   11 <CODE>  12 «potential infinite recursion»  13 <LAMBDA>  14 <PRIMOP>  15 <PRIMOP-APP>
//   16 «error:  17 »  18 «derivation  19 "{ ... }"  20 "[ ... ]"  21 «lambda  22 " @ "  23 «primop
//   24 «partially applied primop  25 «thunk»  26 ";"  27 «  28 " elided»"
//   29 byte  30 bytes  31 attribute  32 attributes  33 item  34 items  35 "?"
//   36 "{"  37 " }"  38 "["  39 " ]"
!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @pv_blob : memref<252xi8> = dense<"0x7472756566616c73656e756c6cc2ab7265706561746564c2bb7b20203d203b207d5b20205d3c434f44453ec2ab706f74656e7469616c20696e66696e69746520726563757273696f6ec2bb3c4c414d4244413e3c5052494d4f503e3c5052494d4f502d4150503ec2ab6572726f723a20c2bbc2ab64657269766174696f6e7b202e2e2e207d5b202e2e2e205dc2ab6c616d626461204020c2ab7072696d6f7020c2ab7061727469616c6c79206170706c696564207072696d6f7020c2ab7468756e6bc2bb3bc2ab20656c69646564c2bb627974656279746573617474726962757465617474726962757465736974656d6974656d733f7b207d5b205d">
memref.global "private" constant @pv_off : memref<40xi32> = dense<[0, 4, 9, 13, 25, 27, 30, 32, 33, 35, 36, 37, 43, 75, 83, 91, 103, 112, 114, 126, 133, 140, 148, 151, 160, 187, 196, 197, 199, 208, 212, 217, 226, 236, 240, 245, 246, 247, 249, 250]>
memref.global "private" constant @pv_len : memref<40xi32> = dense<[4, 5, 4, 12, 2, 3, 2, 1, 2, 1, 1, 6, 32, 8, 8, 12, 9, 2, 12, 7, 7, 8, 3, 9, 27, 9, 1, 2, 9, 4, 5, 9, 10, 4, 5, 1, 1, 2, 1, 2]>
memref.global "private" constant @pv_pow : memref<19xi64> = dense<[1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000, 10000000000, 100000000000, 1000000000000, 10000000000000, 100000000000000, 1000000000000000, 10000000000000000, 100000000000000000, 1000000000000000000]>
memref.global "private" constant @pv_minus : memref<1xi8> = dense<45>

func.func private @pv_desc8(%p: !llvm.ptr, %n: i64) -> !d {
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

// the (start, length) of word wid in the blob (two scalar reads; returning indices allocates nothing)
func.func private @pv_bounds(%wid: index) -> (index, index) {
  %og = memref.get_global @pv_off : memref<40xi32>
  %offs = trikeshed.text %og : memref<40xi32> -> !s32
  %lg = memref.get_global @pv_len : memref<40xi32>
  %lens = trikeshed.text %lg : memref<40xi32> -> !s32
  %o = trikeshed.at %offs[%wid] : !s32, index -> i32
  %l = trikeshed.at %lens[%wid] : !s32, index -> i32
  %oi = arith.index_cast %o : i32 to index
  %li = arith.index_cast %l : i32 to index
  return %oi, %li : index, index
}

// the decimal digits of x (a sign when negative, the magnitude's digits most-significant first), as a view.
// Inlined at each use (a series must not cross a func return).  The digit count is a fold over the powers of ten.
func.func @nixev_ts_pv(%kind: i32, %a: i64, %b: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c18 = arith.constant 18 : index
  %c29 = arith.constant 29 : index
  %c2 = arith.constant 2 : index
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %ten = arith.constant 10 : i64
  %d0 = arith.constant 48 : i8
  %k0 = arith.constant 0 : i32
  %k1 = arith.constant 1 : i32
  %di = func.call @pv_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %bg = memref.get_global @pv_blob : memref<252xi8>
  %blob = trikeshed.text %bg : memref<252xi8> -> !text
  %pg = memref.get_global @pv_pow : memref<19xi64>
  %powers = trikeshed.text %pg : memref<19xi64> -> !s64
  %above = trikeshed.slice %powers[%c1, %c18] : !s64 -> !s64
  %mg = memref.get_global @pv_minus : memref<1xi8>
  %minus = trikeshed.text %mg : memref<1xi8> -> !text
  %isWord = arith.cmpi eq, %kind, %k0 : i32
  %r = scf.if %isWord -> (i64) {
    // kind 0: the fixed word a
    %wid = arith.index_cast %a : i64 to index
    %start, %len = func.call @pv_bounds(%wid) : (index) -> (index, index)
    %word = trikeshed.slice %blob[%start, %len] : !text -> !text
    %end = trikeshed.drain %word, %mi : !text, !m8 -> index
    %ri = arith.index_cast %end : index to i64
    scf.yield %ri : i64
  } else {
    %isInt = arith.cmpi eq, %kind, %k1 : i32
    %r2 = scf.if %isInt -> (i64) {
      // kind 1: the integer a (signed decimal)
      %neg = arith.cmpi slt, %a, %z : i64
      %minusv = arith.subi %z, %a : i64
      %mag = arith.select %neg, %minusv, %a : i64
      %count = trikeshed.fold %above, %c1 : !s64, index -> index {
      ^bb0(%acc: index, %p: i64):
        %reach = arith.cmpi uge, %mag, %p : i64
        %more = arith.addi %acc, %c1 : index
        %rr = arith.select %reach, %more, %acc : index
        trikeshed.yield %rr : index
      }
      %digits = trikeshed.series %count : !text {
      ^bb0(%k: index):
        %last = arith.subi %count, %c1 : index
        %e = arith.subi %last, %k : index
        %p = trikeshed.at %powers[%e] : !s64, index -> i64
        %q = arith.divui %mag, %p : i64
        %dd = arith.remui %q, %ten : i64
        %d8 = arith.trunci %dd : i64 to i8
        %ch = arith.addi %d8, %d0 : i8
        trikeshed.yield %ch : i8
      }
      %signs = arith.select %neg, %c1, %c0 : index
      %sign = trikeshed.slice %minus[%c0, %signs] : !text -> !text
      %all = trikeshed.combine %sign, %digits : !text, !text -> !text
      %end = trikeshed.drain %all, %mi : !text, !m8 -> index
      %ri = arith.index_cast %end : index to i64
      scf.yield %ri : i64
    } else {
      // kind 2: "«a unit elided»" (a >= 0; unit b selects the singular/plural pair, singular when a == 1)
      %neg = arith.cmpi slt, %a, %z : i64
      %minusv = arith.subi %z, %a : i64
      %mag = arith.select %neg, %minusv, %a : i64
      %count = trikeshed.fold %above, %c1 : !s64, index -> index {
      ^bb0(%acc: index, %p: i64):
        %reach = arith.cmpi uge, %mag, %p : i64
        %more = arith.addi %acc, %c1 : index
        %rr = arith.select %reach, %more, %acc : index
        trikeshed.yield %rr : index
      }
      %digits = trikeshed.series %count : !text {
      ^bb0(%k: index):
        %last = arith.subi %count, %c1 : index
        %e = arith.subi %last, %k : index
        %p = trikeshed.at %powers[%e] : !s64, index -> i64
        %q = arith.divui %mag, %p : i64
        %dd = arith.remui %q, %ten : i64
        %d8 = arith.trunci %dd : i64 to i8
        %ch = arith.addi %d8, %d0 : i8
        trikeshed.yield %ch : i8
      }
      // unit word id = 29 + 2 b + (a == 1 ? 0 : 1)
      %bi = arith.index_cast %b : i64 to index
      %twob = arith.muli %bi, %c2 : index
      %base = arith.addi %c29, %twob : index
      %isOne = arith.cmpi eq, %a, %one : i64
      %pl = arith.select %isOne, %c0, %c1 : index
      %wid = arith.addi %base, %pl : index
      %ustart, %ulen = func.call @pv_bounds(%wid) : (index) -> (index, index)
      %unit = trikeshed.slice %blob[%ustart, %ulen] : !text -> !text
      // the guillemets and the fixed pieces are words 27 («), 9 (space), 28 ( elided»)
      %w27 = arith.constant 27 : index
      %gs, %gl = func.call @pv_bounds(%w27) : (index) -> (index, index)
      %guil = trikeshed.slice %blob[%gs, %gl] : !text -> !text
      %w9 = arith.constant 9 : index
      %ss, %sl = func.call @pv_bounds(%w9) : (index) -> (index, index)
      %space = trikeshed.slice %blob[%ss, %sl] : !text -> !text
      %w28 = arith.constant 28 : index
      %es, %el = func.call @pv_bounds(%w28) : (index) -> (index, index)
      %tail = trikeshed.slice %blob[%es, %el] : !text -> !text
      %p1 = trikeshed.combine %guil, %digits : !text, !text -> !text
      %p2 = trikeshed.combine %p1, %space : !text, !text -> !text
      %p3 = trikeshed.combine %p2, %unit : !text, !text -> !text
      %all = trikeshed.combine %p3, %tail : !text, !text -> !text
      %end = trikeshed.drain %all, %mi : !text, !m8 -> index
      %ri = arith.index_cast %end : index to i64
      scf.yield %ri : i64
    }
    scf.yield %r2 : i64
  }
  return %r : i64
}
