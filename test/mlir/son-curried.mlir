// son.body's forced_captures (include/NixDialect/Son.td): the captures a body forces on every path on which it returns, beside
// arg_forced for its argument.  The input is `mlnix emit-mlir` of
//   let add = a: b: a + b; k = a: b: b; in [ (add "x" "y") (k "u" "v") ]
// add's inner body forces its capture `a` as well as its argument, so add forces its argument once the closure it returns is
// applied: a curried call `add x y` may compute x first (the Graal arm, ApplyNode, reads it through the son.defer add returns).
// k's inner body captures nothing, and k's outer body is neither.
// RUN: mlnix-opt %s --nix-defer --son-release | FileCheck %s
// RUN: mlnix-opt %s --nix-defer --son-release | mlnix-opt | FileCheck %s
// RUN: mlnix-opt %s --nix-defer --son-release --son-release | FileCheck %s
// RUN: mlnix-opt %s --nix-defer --son-release --son-mint | FileCheck %s --check-prefix=MINT --implicit-check-not=son.

!char_series = !trikeshed.series<i8>
!nix_string = !trikeshed.join<!char_series, !trikeshed.series<!char_series>>

nix.expr @expr1 {
  %0 = nix.lambda attributes {arg_name = "a", name = "add"} {
  ^bb0(%arg0: !nix.value):
    %9 = nix.lambda attributes {arg_name = "b"} {
    ^bb0(%arg1: !nix.value):
      %10 = nix.concat_strings %arg0, %arg1
      nix.return %10
    }
    nix.return %9 : (!nix.value) -> !nix.value
  }
  %1 = nix.lambda attributes {arg_name = "a", name = "k"} {
  ^bb0(%arg0: !nix.value):
    %9 = nix.lambda attributes {arg_name = "b"} {
    ^bb0(%arg1: !nix.value):
      nix.return %arg1
    }
    nix.return %9 : (!nix.value) -> !nix.value
  }
  %2 = nix.str "x"
  %3 = nix.str "y"
  %4 = nix.apply %0 : (!nix.value) -> !nix.value(%2 : !nix_string, %3 : !nix_string)
  %5 = nix.str "u"
  %6 = nix.str "v"
  %7 = nix.apply %1 : (!nix.value) -> !nix.value(%5 : !nix_string, %6 : !nix_string)
  %8 = nix.list[%4, %7]
  nix.return %8 : !trikeshed.series<!nix.value>
}

// CHECK-LABEL: son.pool @bodies
// CHECK:       son.body @row0 captures 0 lambda {arg_name = "a", name = "k"{{.*}}} {{[{]$}}
// CHECK:         son.defer @bodies::@row1()
// CHECK:       son.body @row1 captures 0 lambda {arg_name = "b"{{.*}}} arg_forced {{[{]$}}
// CHECK:       son.body @row2 captures 0 lambda {arg_name = "a", name = "add"{{.*}}} {{[{]$}}
// CHECK:         son.defer @bodies::@row3(%arg0)
// CHECK:       son.body @row3 captures 1 lambda {arg_name = "b"{{.*}}} arg_forced forced_captures [0] {{[{]$}}
// CHECK-NEXT:  ^bb0(%[[A:.*]]: !nix.value, %[[B:.*]]: !nix.value):
// CHECK-NEXT:    nix.concat_strings %[[A]], %[[B]]

// son-mint puts the lambdas back: forced_captures, like arg_forced, is son's and goes with the body.
// MINT-LABEL:  nix.expr @expr1
// MINT:          nix.lambda attributes {arg_name = "a", name = "add"}
// MINT:          nix.lambda attributes {arg_name = "b"}
// MINT:          nix.lambda attributes {arg_name = "a", name = "k"}
