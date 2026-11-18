// son.release (include/NixDialect/Son.td): what a call's frame may keep when the call returns -- the Graal arm's frame
// (graal/, BodyRoot.release) in the IR.  The input is `mlnix emit-mlir` of
//   let f = x: let a = x + "1"; b = x + "2"; c = a + b; unused = x + "u";
//              in { inherit a; v = [ c x ]; t = (x == "z"); };
//       g = y: y + "!";
//   in [ (f "s").v (g "h") ]
// Worked by hand.  f passes on a, t, v (attribute values) and c (a list element); x is passed on as itself, the caller's
// cell, and holds no frame.  Their closure over operands: x "1" a "2" b c v "z" t.  Released at the return: "u", unused,
// and the attribute set (returned, not passed on).  g passes nothing on and keeps nothing.  The expression keeps all but
// the list it returns.  On the Graal arm (NIXTRUFFLE_CHECK_RELEASE=1) the release at each return keeps a subset.
// g forces its argument on every path that returns (it returns y + "!"), so its body is arg_forced; f returns a set and
// forces x on no path.
// RUN: mlnix-opt %s --nix-defer --son-release | FileCheck %s
// RUN: mlnix-opt %s --nix-defer --son-release | mlnix-opt | FileCheck %s
// RUN: mlnix-opt %s --nix-defer --son-release --son-release | FileCheck %s
// RUN: mlnix-opt %s --nix-defer --son-release --son-mint | FileCheck %s --check-prefix=MINT --implicit-check-not=son.
// RUN: mlnix-opt %S/inputs/son-release-laws.mlir --split-input-file --verify-diagnostics

!char_series = !trikeshed.series<i8>
!nix_string = !trikeshed.join<!char_series, !trikeshed.series<!char_series>>
!nix_list = !trikeshed.series<!nix.value>
!nix_attrs = !trikeshed.series2<i32, !nix.value>

nix.expr @expr1 {
  %0 = nix.lambda attributes {arg_name = "x", name = "f"} {
  ^bb0(%arg0: !nix.value):
    %8 = nix.str "1"
    %9 = nix.concat_strings %arg0, %8 : !nix_string
    %10 = nix.str "2"
    %11 = nix.concat_strings %arg0, %10 : !nix_string
    %12 = nix.concat_strings %9, %11
    %13 = nix.str "u"
    %14 = nix.concat_strings %arg0, %13 : !nix_string
    %15 = nix.list[%12, %arg0]
    %16 = nix.str "z"
    %17 = nix.eq %arg0, %16 : !nix_string
    %18 = nix.attrs ["a", "t", "v"](%9, %17, %15 : !nix_list)
    nix.return %18 : !nix_attrs
  }
  %1 = nix.lambda attributes {arg_name = "y", name = "g"} {
  ^bb0(%arg0: !nix.value):
    %8 = nix.str "!"
    %9 = nix.concat_strings %arg0, %8 : !nix_string
    nix.return %9
  }
  %2 = nix.str "s"
  %3 = nix.apply %0 : (!nix.value) -> !nix.value(%2 : !nix_string)
  %4 = nix.select %3 ["v"]
  %5 = nix.str "h"
  %6 = nix.apply %1 : (!nix.value) -> !nix.value(%5 : !nix_string)
  %7 = nix.list[%4, %6]
  nix.return %7 : !nix_list
}

// CHECK-LABEL: nix.expr @expr1
// CHECK-NEXT:    %[[F:.*]] = son.defer @bodies::@row1()
// CHECK-NEXT:    %[[G:.*]] = son.defer @bodies::@row0()
// CHECK-NEXT:    %[[S:.*]] = nix.str "s"
// CHECK-NEXT:    %[[FS:.*]] = nix.apply %[[F]]
// CHECK-NEXT:    %[[V:.*]] = nix.select %[[FS]] ["v"]
// CHECK-NEXT:    %[[H:.*]] = nix.str "h"
// CHECK-NEXT:    %[[GH:.*]] = nix.apply %[[G]]
// CHECK-NEXT:    %[[L:.*]] = nix.list[%[[V]], %[[GH]]]
// CHECK-NEXT:    son.release(%[[F]] : !nix_fn, %[[G]] : !nix_fn, %[[S]] : !nix_string, %[[FS]], %[[V]], %[[H]] : !nix_string, %[[GH]])
// CHECK-NEXT:    nix.return %[[L]]

// CHECK:       son.body @row0 captures 0 lambda {arg_name = "y", name = "g"{{.*}}} arg_forced {{[{]$}}
// CHECK:         nix.concat_strings
// CHECK-NEXT:    son.release()
// CHECK-NEXT:    nix.return

// CHECK:       son.body @row1 captures 0 lambda {arg_name = "x", name = "f"{{.*}}} {{[{]$}}
// CHECK-NEXT:  ^bb0(%[[X:.*]]: !nix.value):
// CHECK-NEXT:    %[[ONE:.*]] = nix.str "1"
// CHECK-NEXT:    %[[A:.*]] = nix.concat_strings %[[X]], %[[ONE]]
// CHECK-NEXT:    %[[TWO:.*]] = nix.str "2"
// CHECK-NEXT:    %[[B:.*]] = nix.concat_strings %[[X]], %[[TWO]]
// CHECK-NEXT:    %[[C:.*]] = nix.concat_strings %[[A]], %[[B]]
// CHECK-NEXT:    %[[U:.*]] = nix.str "u"
// CHECK-NEXT:    %[[UNUSED:.*]] = nix.concat_strings %[[X]], %[[U]]
// CHECK-NEXT:    %[[VL:.*]] = nix.list[%[[C]], %[[X]]]
// CHECK-NEXT:    %[[Z:.*]] = nix.str "z"
// CHECK-NEXT:    %[[T:.*]] = nix.eq %[[X]], %[[Z]]
// CHECK-NEXT:    %[[SET:.*]] = nix.attrs ["a", "t", "v"](%[[A]], %[[T]], %[[VL]] : !nix_list)
// CHECK-NEXT:    son.release(%[[X]], %[[ONE]] : !nix_string, %[[A]], %[[TWO]] : !nix_string, %[[B]], %[[C]], %[[VL]] : !nix_list, %[[Z]] : !nix_string, %[[T]])
// CHECK-NEXT:    nix.return %[[SET]]

// son-mint puts the lambdas back and drops the releases: a minted lambda is not a frame.
// MINT-LABEL:  nix.expr @expr1
// MINT:          nix.lambda attributes {arg_name = "x", name = "f"}
// MINT:          nix.attrs ["a", "t", "v"]
// MINT:          nix.lambda attributes {arg_name = "y", name = "g"}
// MINT:          nix.list[
// MINT:          nix.return
