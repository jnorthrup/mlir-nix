// The scripts under pipelines/ are libraries: they run on a payload that does
// not contain them (`--transform-preload-library`). default.transform.mlir is
// also the script that is embedded in the binary (MLNIX_TRANSFORM=embedded);
// full.transform.mlir uses every combinator (include, sequence, alternatives,
// collect_matching, apply_cse/apply_dce).
// RUN: mlnix-opt %s --transform-preload-library='transform-library-paths=pipelines/default.transform.mlir' --transform-interpreter | FileCheck %s --check-prefix=DEFAULT
// RUN: mlnix-opt %s --transform-preload-library='transform-library-paths=pipelines/full.transform.mlir' --transform-interpreter | FileCheck %s --check-prefix=FULL

nix.expr @e {
  %add = nix.builtin "__add"
  %one = nix.int 1
  %two = nix.int 2
  %x = nix.apply %add(%one, %two)
  %y = nix.apply %add(%one, %two)
  %live = nix.list [%x, %y]
  // Dead, and a cycle.
  %d1 = nix.list [%d2]
  %d2 = nix.list [%d1]
  nix.return %live
}

// default: devirtualization only (= builtin.module(nix-prims)).
// DEFAULT-LABEL: nix.expr @e
// DEFAULT-NOT: nix.apply
// DEFAULT: nixnum.add(
// DEFAULT: nixnum.add(
// DEFAULT: nix.list[
// DEFAULT: nix.list[
// DEFAULT: nix.list[

// full: devirtualize, then (on a clone) fold, dce, CSE: one addition, one
// list, no dead cycle.
// FULL-LABEL: nix.expr @e
// FULL-NOT: nix.apply
// FULL: [[S:%.*]] = nixnum.add(
// FULL-NOT: nixnum.add
// FULL: nix.list[[[S]], [[S]]]
// FULL-NOT: nix.list
// FULL: nix.return
