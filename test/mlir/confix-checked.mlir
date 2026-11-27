// confix.checked: builtins.fromJSON's scan (the reader's checks, nlohmann's faults at its offsets, Long vs Double), the body
// of the op in lowered/nixeval/JsonRead.mlir (compiled at build time, linked into NixEval).  The record is Confix.td's:
// src, n, at, end; the rows are the caller's lane, a row (open, close, tag, up), filled by the scan.  The cases below are
// what the reader before it (include/Composite/Confix.h) gave for these texts:
//   [1,"a",{"b":null}]     fault 0, 6 rows
//   {"a" 1}                fault 4 (':' expected) at 5
//   9223372036854775808    fault 14 (Unsigned) from 0 to 19
//   [1,                    fault 1 (end of input) at 3
//   "\ud800x"              fault 12 (a high surrogate alone) at 7
// and the six rows of the first, worked by hand (the array's close 17 and the object's 16 are the ones trikeshed.anchor
// mints when their closers are read):
//   open   0  1  3  7  8 12   sum 31        tag  6 2 4 5 4 0   sum 21
//   close 17  1  5 16 10 15   sum 64        up  -1 0 0 0 3 3   sum  5
// The callbacks of the reification beside it in the module are stubs: only the scan runs here.
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --trikeshed-lower-cursors | FileCheck %s --check-prefix=LOWER
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-scf-to-cf --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-translate --mlir-to-llvmir | llvm-link - build/lib/lowered/JsonRead.ll -S | lli

// ROUND: confix.checked %{{.*}}, %{{.*}} : !llvm.ptr, !trikeshed.lane<i32, i32, i8, i32>
// The body is handed the record and the cells of the lane: its count, and a box a column.
// LOWER-DAG: func.func private @confix_scan_checked(!llvm.ptr, memref<1xindex>, memref<1xmemref<?xmemref<4096xi32>>>, memref<1xmemref<?xmemref<4096xi32>>>, memref<1xmemref<?xmemref<4096xi8>>>, memref<1xmemref<?xmemref<4096xi32>>>) -> i32
// LOWER: call @confix_scan_checked(%{{.*}}, %{{.*}}, %{{.*}}, %{{.*}}, %{{.*}}, %{{.*}}) : (!llvm.ptr, memref<1xindex>,

!rows = !trikeshed.lane<i32, i32, i8, i32>
!l32 = !trikeshed.lane<i32>
!l8 = !trikeshed.lane<i8>

llvm.mlir.global internal constant @t1("[1,\22a\22,{\22b\22:null}]") {addr_space = 0 : i32}
llvm.mlir.global internal constant @t2("{\22a\22 1}") {addr_space = 0 : i32}
llvm.mlir.global internal constant @t3("9223372036854775808") {addr_space = 0 : i32}
llvm.mlir.global internal constant @t4("[1,") {addr_space = 0 : i32}
llvm.mlir.global internal constant @t5("\22\5Cud800x\22") {addr_space = 0 : i32}

llvm.func @nixev_json_value(%st: !llvm.ptr) -> !llvm.ptr {
  llvm.return %st : !llvm.ptr
}
llvm.func @nixev_json_string(%st: !llvm.ptr, %v: !llvm.ptr, %p: !llvm.ptr, %n: i64) {
  llvm.return
}
llvm.func @nixev_json_attrs(%st: !llvm.ptr, %v: !llvm.ptr, %k: !llvm.ptr, %x: !llvm.ptr, %n: i64) {
  llvm.return
}
llvm.func @_ZN5nixev9EvalState6mkListERNS_5ValueEm(%st: !llvm.ptr, %v: !llvm.ptr, %n: i64) {
  llvm.return
}

func.func private @word(%rec: !llvm.ptr, %k: i64) -> i64 {
  %p = llvm.getelementptr %rec[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %p : !llvm.ptr -> i64
  return %v : i64
}
func.func private @put(%rec: !llvm.ptr, %k: i64, %v: i64) {
  %p = llvm.getelementptr %rec[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %p : i64, !llvm.ptr
  return
}
func.func private @putp(%rec: !llvm.ptr, %k: i64, %v: !llvm.ptr) {
  %p = llvm.getelementptr %rec[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  llvm.store %v, %p : !llvm.ptr, !llvm.ptr
  return
}
func.func private @ne(%a: i64, %b: i64) -> i32 {
  %c = arith.cmpi ne, %a, %b : i64
  %r = arith.extui %c : i1 to i32
  return %r : i32
}

// a column of the rows, added up (an open, a close or an up as the signed i32 it is)
func.func private @sum32(%col: !l32) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %z64 = arith.constant 0 : i64
  %n = trikeshed.size %col : !l32
  %s = scf.for %i = %z to %n step %one iter_args(%acc = %z64) -> (i64) {
    %x = trikeshed.at %col[%i] : !l32, index -> i32
    %x64 = arith.extsi %x : i32 to i64
    %next = arith.addi %acc, %x64 : i64
    scf.yield %next : i64
  }
  return %s : i64
}

// scan %n bytes at %src into a lane of this function's: how many of the fault and of word k of the record (at 2, end 3;
// with k 0, the rows the lane holds) differ from what is wanted; with sums, also of the four columns' sums from 31, 64,
// 21 and 5
func.func private @check(%src: !llvm.ptr, %n: i64, %fault: i32, %k: i64, %want: i64, %sums: i1) -> i32 {
  %rows = trikeshed.lane : !rows
  %one = arith.constant 1 : i64
  %rec = llvm.alloca %one x !llvm.array<4 x i64> : (i64) -> !llvm.ptr
  %z = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  func.call @putp(%rec, %z, %src) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @put(%rec, %one, %n) : (!llvm.ptr, i64, i64) -> ()
  func.call @put(%rec, %c2, %z) : (!llvm.ptr, i64, i64) -> ()
  func.call @put(%rec, %c3, %z) : (!llvm.ptr, i64, i64) -> ()
  %got = confix.checked %rec, %rows : !llvm.ptr, !rows
  %bad = arith.cmpi ne, %got, %fault : i32
  %r0 = arith.extui %bad : i1 to i32
  %size = trikeshed.size %rows : !rows
  %size64 = arith.index_cast %size : index to i64
  %word = func.call @word(%rec, %k) : (!llvm.ptr, i64) -> i64
  %count = arith.cmpi eq, %k, %z : i64
  %w = arith.select %count, %size64, %word : i64
  %r1 = func.call @ne(%w, %want) : (i64, i64) -> i32
  %r = arith.addi %r0, %r1 : i32
  %rs = scf.if %sums -> (i32) {
    %i0 = arith.constant 0 : index
    %i1 = arith.constant 1 : index
    %i2 = arith.constant 2 : index
    %i3 = arith.constant 3 : index
    %opens = trikeshed.take %rows[%i0] : !rows -> !l32
    %closes = trikeshed.take %rows[%i1] : !rows -> !l32
    %tags = trikeshed.take %rows[%i2] : !rows -> !l8
    %ups = trikeshed.take %rows[%i3] : !rows -> !l32
    %so = func.call @sum32(%opens) : (!l32) -> i64
    %sc = func.call @sum32(%closes) : (!l32) -> i64
    %su = func.call @sum32(%ups) : (!l32) -> i64
    %st = scf.for %i = %i0 to %size step %i1 iter_args(%acc = %z) -> (i64) {
      %t = trikeshed.at %tags[%i] : !l8, index -> i8
      %t64 = arith.extui %t : i8 to i64
      %next = arith.addi %acc, %t64 : i64
      scf.yield %next : i64
    }
    %wo = arith.constant 31 : i64
    %wc = arith.constant 64 : i64
    %wt = arith.constant 21 : i64
    %wu = arith.constant 5 : i64
    %e0 = func.call @ne(%so, %wo) : (i64, i64) -> i32
    %e1 = func.call @ne(%sc, %wc) : (i64, i64) -> i32
    %e2 = func.call @ne(%st, %wt) : (i64, i64) -> i32
    %e3 = func.call @ne(%su, %wu) : (i64, i64) -> i32
    %e01 = arith.addi %e0, %e1 : i32
    %e23 = arith.addi %e2, %e3 : i32
    %e = arith.addi %e01, %e23 : i32
    %re = arith.addi %r, %e : i32
    scf.yield %re : i32
  } else {
    scf.yield %r : i32
  }
  return %rs : i32
}

func.func @main() -> i32 {
  %t1 = llvm.mlir.addressof @t1 : !llvm.ptr
  %t2 = llvm.mlir.addressof @t2 : !llvm.ptr
  %t3 = llvm.mlir.addressof @t3 : !llvm.ptr
  %t4 = llvm.mlir.addressof @t4 : !llvm.ptr
  %t5 = llvm.mlir.addressof @t5 : !llvm.ptr
  %n1 = arith.constant 18 : i64
  %n2 = arith.constant 7 : i64
  %n3 = arith.constant 19 : i64
  %n4 = arith.constant 3 : i64
  %n5 = arith.constant 9 : i64
  %k0 = arith.constant 0 : i32
  %k1 = arith.constant 1 : i32
  %k4 = arith.constant 4 : i32
  %k12 = arith.constant 12 : i32
  %k14 = arith.constant 14 : i32
  %rows = arith.constant 0 : i64
  %at = arith.constant 2 : i64
  %end = arith.constant 3 : i64
  %six = arith.constant 6 : i64
  %five = arith.constant 5 : i64
  %three = arith.constant 3 : i64
  %seven = arith.constant 7 : i64
  %yes = arith.constant 1 : i1
  %no = arith.constant 0 : i1
  %a = func.call @check(%t1, %n1, %k0, %rows, %six, %yes) : (!llvm.ptr, i64, i32, i64, i64, i1) -> i32
  %b = func.call @check(%t2, %n2, %k4, %at, %five, %no) : (!llvm.ptr, i64, i32, i64, i64, i1) -> i32
  %c = func.call @check(%t3, %n3, %k14, %end, %n3, %no) : (!llvm.ptr, i64, i32, i64, i64, i1) -> i32
  %d = func.call @check(%t4, %n4, %k1, %at, %three, %no) : (!llvm.ptr, i64, i32, i64, i64, i1) -> i32
  %e = func.call @check(%t5, %n5, %k12, %at, %seven, %no) : (!llvm.ptr, i64, i32, i64, i64, i1) -> i32
  %s1 = arith.addi %a, %b : i32
  %s2 = arith.addi %s1, %c : i32
  %s3 = arith.addi %s2, %d : i32
  %s4 = arith.addi %s3, %e : i32
  return %s4 : i32
}
