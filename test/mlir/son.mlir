// The son dialect (include/NixDialect/Son.td): the demand schedule as IR. nix-defer moves each lambda body to a
// pool row closed over its captures; son-mint puts it back. The nested lambda captures x and k from outside itself.
// RUN: mlnix-opt %s --nix-defer | FileCheck %s --check-prefix=DEFER
// RUN: mlnix-opt %s --nix-defer | mlnix-opt | FileCheck %s --check-prefix=DEFER
// RUN: mlnix-opt %s --nix-defer --son-mint | FileCheck %s --check-prefix=MINT

nix.expr @expr1 {
  %0 = nix.int 10
  %1 = nix.lambda attributes {arg_name = "x", name = "f"} {
  ^bb0(%arg0: !nix.value):
    %5 = nix.lambda attributes {arg_name = "y"} {
    ^bb0(%arg1: !nix.value):
      %6 = nix.concat_strings %arg0, %arg1
      %7 = nix.concat_strings %6, %0
      nix.return %7
    }
    nix.return %5
  }
  %2 = nix.int 1
  %3 = nix.int 2
  %4 = nix.apply %1(%2, %3)
  nix.return %4
}

// The outer lambda captures k; the inner one captures x and k, then takes y.
// DEFER: %[[K:.*]] = nix.int 10
// DEFER: %[[F:.*]] = son.defer @bodies::@row0(%[[K]])
// DEFER: nix.apply %[[F]](
// DEFER-NOT: nix.lambda
// DEFER: son.pool @bodies
// DEFER: son.body @row0 captures 1 lambda {arg_name = "x", name = "f"
// DEFER: ^bb0(%[[K0:.*]]: !nix.value, %[[X:.*]]: !nix.value):
// DEFER: son.defer @bodies::@row1(%[[X]], %[[K0]])
// DEFER: son.body @row1 captures 2 lambda {arg_name = "y"
// DEFER: ^bb0(%[[X1:.*]]: !nix.value, %[[K1:.*]]: !nix.value, %[[Y:.*]]: !nix.value):
// DEFER: nix.concat_strings %[[X1]], %[[Y]]
// DEFER: nix.concat_strings %{{.*}}, %[[K1]]

// Minted again: the module is the one that went in.
// MINT-NOT: son.
// MINT: %[[K:.*]] = nix.int 10
// MINT: nix.lambda attributes {arg_name = "x", name = "f"
// MINT: ^bb0(%[[X:.*]]: !nix.value):
// MINT: nix.lambda attributes {arg_name = "y"
// MINT: ^bb0(%[[Y:.*]]: !nix.value):
// MINT: nix.concat_strings %[[X]], %[[Y]]
// MINT: nix.concat_strings %{{.*}}, %[[K]]
