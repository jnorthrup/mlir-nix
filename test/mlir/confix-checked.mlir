// confix.checked: builtins.fromJSON's scan (the reader's checks, nlohmann's faults at its offsets, Long vs Double), the body
// of the op in lowered/nixeval/JsonRead.mlir (compiled at build time, linked into NixEval).  The record is Confix.td's:
// src, n, rows, rowCap, span, tag, kids, kid, nkid, stack, sp, stackCap, pend, npend, at, end.  The cases below are what
// the reader before it (include/Composite/Confix.h) gave for these texts:
//   [1,"a",{"b":null}]     fault 0, 6 rows
//   {"a" 1}                fault 4 (':' expected) at 5
//   9223372036854775808    fault 14 (Unsigned) from 0 to 19
//   [1,                    fault 1 (end of input) at 3
//   "\ud800x"              fault 12 (a high surrogate alone) at 7
// The callbacks of the reification beside it in the module are stubs: only the scan runs here.
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --trikeshed-lower-cursors | FileCheck %s --check-prefix=LOWER
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --convert-scf-to-cf --convert-func-to-llvm --convert-cf-to-llvm --convert-arith-to-llvm --reconcile-unrealized-casts | mlir-translate --mlir-to-llvmir | llvm-link - build/lib/lowered/JsonRead.ll -S | lli

// ROUND: confix.checked %{{.*}} : !llvm.ptr
// LOWER-DAG: func.func private @confix_scan_checked(!llvm.ptr) -> i32
// LOWER: call @confix_scan_checked(%{{.*}}) : (!llvm.ptr) -> i32

llvm.mlir.global internal constant @t1("[1,\22a\22,{\22b\22:null}]") {addr_space = 0 : i32}
llvm.mlir.global internal constant @t2("{\22a\22 1}") {addr_space = 0 : i32}
llvm.mlir.global internal constant @t3("9223372036854775808") {addr_space = 0 : i32}
llvm.mlir.global internal constant @t4("[1,") {addr_space = 0 : i32}
llvm.mlir.global internal constant @t5("\22\5Cud800x\22") {addr_space = 0 : i32}

llvm.func @nixev_json_grow(%r: !llvm.ptr, %w: i64) {
  llvm.return
}
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

// scan %n bytes at %src into a record with room for 32 rows: how many of fault, at (or end, or rows) differ from what is wanted
func.func private @check(%src: !llvm.ptr, %n: i64, %fault: i32, %k: i64, %want: i64) -> i32 {
  %one = arith.constant 1 : i64
  %rec = llvm.alloca %one x !llvm.array<16 x i64> : (i64) -> !llvm.ptr
  %a64 = llvm.alloca %one x !llvm.array<96 x i64> : (i64) -> !llvm.ptr
  %a8 = llvm.alloca %one x !llvm.array<32 x i8> : (i64) -> !llvm.ptr
  %a32 = llvm.alloca %one x !llvm.array<64 x i32> : (i64) -> !llvm.ptr
  %z = arith.constant 0 : i64
  %c32 = arith.constant 32 : i64
  %c64 = arith.constant 64 : i64
  %c16 = arith.constant 16 : i64
  scf.for %i = %z to %c16 step %one : i64 {
    func.call @put(%rec, %i, %z) : (!llvm.ptr, i64, i64) -> ()
  }
  %span = llvm.getelementptr %a64[0] : (!llvm.ptr) -> !llvm.ptr, i64
  %kids = llvm.getelementptr %a64[32] : (!llvm.ptr) -> !llvm.ptr, i64
  %stack = llvm.getelementptr %a64[64] : (!llvm.ptr) -> !llvm.ptr, i64
  %kid = llvm.getelementptr %a32[0] : (!llvm.ptr) -> !llvm.ptr, i32
  %pend = llvm.getelementptr %a32[32] : (!llvm.ptr) -> !llvm.ptr, i32
  %f0 = arith.constant 0 : i64
  %f1 = arith.constant 1 : i64
  %f3 = arith.constant 3 : i64
  %f4 = arith.constant 4 : i64
  %f5 = arith.constant 5 : i64
  %f6 = arith.constant 6 : i64
  %f7 = arith.constant 7 : i64
  %f9 = arith.constant 9 : i64
  %f11 = arith.constant 11 : i64
  %f12 = arith.constant 12 : i64
  func.call @putp(%rec, %f0, %src) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @put(%rec, %f1, %n) : (!llvm.ptr, i64, i64) -> ()
  func.call @put(%rec, %f3, %c32) : (!llvm.ptr, i64, i64) -> ()
  func.call @putp(%rec, %f4, %span) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @putp(%rec, %f5, %a8) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @putp(%rec, %f6, %kids) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @putp(%rec, %f7, %kid) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @putp(%rec, %f9, %stack) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  func.call @put(%rec, %f11, %c32) : (!llvm.ptr, i64, i64) -> ()
  func.call @putp(%rec, %f12, %pend) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %got = confix.checked %rec : !llvm.ptr
  %bad = arith.cmpi ne, %got, %fault : i32
  %r0 = arith.extui %bad : i1 to i32
  %w = func.call @word(%rec, %k) : (!llvm.ptr, i64) -> i64
  %r1 = func.call @ne(%w, %want) : (i64, i64) -> i32
  %r = arith.addi %r0, %r1 : i32
  return %r : i32
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
  %rows = arith.constant 2 : i64
  %at = arith.constant 14 : i64
  %end = arith.constant 15 : i64
  %six = arith.constant 6 : i64
  %five = arith.constant 5 : i64
  %three = arith.constant 3 : i64
  %seven = arith.constant 7 : i64
  %a = func.call @check(%t1, %n1, %k0, %rows, %six) : (!llvm.ptr, i64, i32, i64, i64) -> i32
  %b = func.call @check(%t2, %n2, %k4, %at, %five) : (!llvm.ptr, i64, i32, i64, i64) -> i32
  %c = func.call @check(%t3, %n3, %k14, %end, %n3) : (!llvm.ptr, i64, i32, i64, i64) -> i32
  %d = func.call @check(%t4, %n4, %k1, %at, %three) : (!llvm.ptr, i64, i32, i64, i64) -> i32
  %e = func.call @check(%t5, %n5, %k12, %at, %seven) : (!llvm.ptr, i64, i32, i64, i64) -> i32
  %s1 = arith.addi %a, %b : i32
  %s2 = arith.addi %s1, %c : i32
  %s3 = arith.addi %s2, %d : i32
  %s4 = arith.addi %s3, %e : i32
  return %s4 : i32
}
