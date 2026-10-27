// The TrikeShed dialect is generated from include/Composite/TrikeShed.td: borg.trikeshed.lib's algebra as MLIR types and
// ops.  This test is the gate on it being a real dialect -- registerable, parseable and printable -- and on the shapes
// Series.h implements: Join, Series (size j index), MetaSeries over a domain, Series2/split, Cursor with its schema.
// RUN: mlnix-opt %s | FileCheck %s

// CHECK-LABEL: module attributes
// CHECK-SAME: ts.c = !trikeshed.cursor<"BandCol", [i32, i8, i64]>
// CHECK-SAME: ts.j = !trikeshed.join<i64, i64>
// CHECK-SAME: ts.m = !trikeshed.metaseries<!trikeshed.twinpacked<i32>, i64>
// CHECK-SAME: ts.p = !trikeshed.twinpacked<i32>
// CHECK-SAME: ts.s = !trikeshed.series<index>
// CHECK-SAME: ts.s2 = !trikeshed.series2<i64, i8>
// CHECK-SAME: ts.sp = !trikeshed.split<i64, i8>
// CHECK-SAME: ts.t = !trikeshed.twin<i64>
module attributes {
  ts.t = !trikeshed.twin<i64>,
  ts.j = !trikeshed.join<i64, i64>,
  ts.p = !trikeshed.twinpacked<i32>,
  ts.m = !trikeshed.metaseries<!trikeshed.twinpacked<i32>, i64>,
  ts.s = !trikeshed.series<index>,
  ts.s2 = !trikeshed.series2<i64, i8>,
  ts.sp = !trikeshed.split<i64, i8>,
  ts.c = !trikeshed.cursor<"BandCol", [i32, i8, i64]>
} {}
