// The optimization stages are separate passes. They compose in a textual
// pipeline (`--pass-pipeline`), also with stock passes: `cse` is sound on Nix IR
// because primop effects are declared (NixPrims.td). `nix-simplify` is only an
// alias of nix-prims,nix-fold,nix-dce.
//
// RUN: mlnix-opt %s --nix-prims | FileCheck %s --check-prefix=PRIMS
// RUN: mlnix-opt %s --nix-dce | FileCheck %s --check-prefix=DCE
// RUN: mlnix-opt %s --pass-pipeline='builtin.module(nix-prims,cse,nix-dce)' | FileCheck %s --check-prefix=PIPE
// RUN: mlnix-opt %s --pass-pipeline='builtin.module(nix.expr(nix-prims,cse,nix-dce))' | FileCheck %s --check-prefix=PIPE
// RUN: diff <(mlnix-opt %s --nix-simplify) <(mlnix-opt %s --pass-pipeline='builtin.module(nix-prims,nix-fold,nix-dce)')

nix.expr @e {
  %add = nix.builtin "__add"
  %one = nix.int 1
  %two = nix.int 2
  %x = nix.apply %add(%one, %two)
  %y = nix.apply %add(%one, %two)
  %live = nix.list [%x, %y]
  // Dead, and a cycle: each member is used (by the other), so the stock DCE
  // keeps both.
  %d1 = nix.list [%d2]
  %d2 = nix.list [%d1]
  nix.return %live
}

// nix-prims alone: calls become ops, nothing is merged, nothing is removed.
// PRIMS-LABEL: nix.expr @e
// PRIMS-NOT: nix.apply
// PRIMS: nixnum.add(
// PRIMS: nixnum.add(
// PRIMS: nix.list[
// PRIMS: nix.list[
// PRIMS: nix.list[

// nix-dce alone: the dead cycle is gone, the calls are still calls.
// DCE-LABEL: nix.expr @e
// DCE: nix.apply
// DCE: nix.apply
// DCE: nix.list[
// DCE-NOT: nix.list[
// DCE: nix.return

// prims, then stock cse, then dce: one addition, one list, no cycle.
// PIPE-LABEL: nix.expr @e
// PIPE-NOT: nix.apply
// PIPE: [[S:%.*]] = nixnum.add(
// PIPE-NOT: nixnum.add
// PIPE: nix.list[[[S]], [[S]]]
// PIPE-NOT: nix.list
// PIPE: nix.return
