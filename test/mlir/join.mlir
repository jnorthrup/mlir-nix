// The PRELOAD composite's first layer: Join and its collapse into one integer.
//
// Twin<Int> is TrikeShed's TwInt, one Long.  LLVM has integers of any width, so the collapse does
// not stop at 64 bits: a segment of an immutable buffer, Join<buffer, Twin<start, end>>, is an i96.
// The first component takes the high bits (include/Composite/Pack.h makes the same word).
//
// RUN: mlnix-opt %s -join-densify -canonicalize | FileCheck %s
// RUN: mlnix-opt %s -canonicalize | FileCheck %s --check-prefix=FOLD

// CHECK-LABEL: func.func @twint
// CHECK: %[[C:.*]] = arith.constant 30064771081 : i64
// CHECK-NEXT: return %[[C]] : i64
func.func @twint() -> !join.pair<i32, i32> {
  %a = arith.constant 7 : i32
  %b = arith.constant 9 : i32
  %j = join.make %a, %b : !join.pair<i32, i32>
  return %j : !join.pair<i32, i32>
}

// A segment is a join of a buffer and a twin: i32 + (i32 + i32) = i96
// CHECK-LABEL: func.func @segment
// CHECK: arith.constant 55340232264078327825 : i96
func.func @segment() -> !join.pair<i32, !join.pair<i32, i32>> {
  %buf = arith.constant 3 : i32
  %start = arith.constant 10 : i32
  %end = arith.constant 17 : i32
  %bounds = join.make %start, %end : !join.pair<i32, i32>
  %seg = join.make %buf, %bounds : !join.pair<i32, !join.pair<i32, i32>>
  return %seg : !join.pair<i32, !join.pair<i32, i32>>
}

// Twin<Long> does not fit a Long
// CHECK-LABEL: func.func @twin_of_longs
// CHECK: arith.constant 18446744073709551618 : i128
func.func @twin_of_longs() -> !join.pair<i64, i64> {
  %a = arith.constant 1 : i64
  %b = arith.constant 2 : i64
  %j = join.make %a, %b : !join.pair<i64, i64>
  return %j : !join.pair<i64, i64>
}

// Floats travel as their bits (1.0f = 0x3F800000)
// CHECK-LABEL: func.func @float_and_int
// CHECK: arith.constant 4575657221408423941 : i64
func.func @float_and_int() -> !join.pair<f32, i32> {
  %a = arith.constant 1.0 : f32
  %b = arith.constant 5 : i32
  %j = join.make %a, %b : !join.pair<f32, i32>
  return %j : !join.pair<f32, i32>
}

// The projections of a densified value are shifts and truncations
// CHECK-LABEL: func.func @project
// CHECK-SAME: (%[[P:.*]]: i64) -> (i32, i32)
// CHECK: %[[HI:.*]] = arith.shrui %[[P]], %{{.*}} : i64
// CHECK: %[[A:.*]] = arith.trunci %[[HI]] : i64 to i32
// CHECK: %[[B:.*]] = arith.trunci %[[P]] : i64 to i32
// CHECK: return %[[A]], %[[B]] : i32, i32
func.func @project(%p: !join.pair<i32, i32>) -> (i32, i32) {
  %a = join.first %p : !join.pair<i32, i32>
  %b = join.second %p : !join.pair<i32, i32>
  return %a, %b : i32, i32
}

// A pair that is built and taken apart again is the two things it was built from
// CHECK-LABEL: func.func @roundtrip
// CHECK-SAME: (%[[X:.*]]: i32, %[[Y:.*]]: f64) -> (i32, f64)
// CHECK-NEXT: return %[[X]], %[[Y]] : i32, f64
// FOLD-LABEL: func.func @roundtrip
// FOLD-NEXT: return %arg0, %arg1 : i32, f64
func.func @roundtrip(%x: i32, %y: f64) -> (i32, f64) {
  %j = join.make %x, %y : !join.pair<i32, f64>
  %a = join.first %j : !join.pair<i32, f64>
  %b = join.second %j : !join.pair<i32, f64>
  return %a, %b : i32, f64
}

// ... and the other way round
// FOLD-LABEL: func.func @rebuild
// FOLD-NEXT: return %arg0 : !join.pair<i32, i32>
func.func @rebuild(%p: !join.pair<i32, i32>) -> !join.pair<i32, i32> {
  %a = join.first %p : !join.pair<i32, i32>
  %b = join.second %p : !join.pair<i32, i32>
  %j = join.make %a, %b : !join.pair<i32, i32>
  return %j : !join.pair<i32, i32>
}
