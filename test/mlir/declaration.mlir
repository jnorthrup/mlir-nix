// The primop declaration is data.  Changing one attribute of one irdl.operation in
// a copy of NixPrims.irdl.mlir (MLNIX_PRIMS_IRDL=...) changes what the stock passes
// and verifier do, with no C++ and no rebuild.
//
// RUN: [cse-dynamic-ops] mlnix-opt %s -cse | FileCheck %s --check-prefix=PURE
// RUN: [cse-dynamic-ops] MLNIX_PRIMS_IRDL=%S/inputs/impure-add.irdl.mlir mlnix-opt %s -cse | FileCheck %s --check-prefix=IMPURE
// RUN: MLNIX_PRIMS_IRDL=%S/inputs/unary-add.irdl.mlir not mlnix-opt %s 2>&1 | FileCheck %s --check-prefix=ARITY
// RUN: MLNIX_PRIMS_IRDL=%S/inputs/bad-fx.irdl.mlir not --crash mlnix-opt %s 2>&1 | FileCheck %s --check-prefix=BADFX
// RUN: MLNIX_PRIMS_IRDL=%S/inputs/dup-key.irdl.mlir not --crash mlnix-opt %s 2>&1 | FileCheck %s --check-prefix=DUP
// RUN: MLNIX_PRIMS_IRDL=%S/inputs/nonexistent.irdl.mlir not --crash mlnix-opt %s 2>&1 | FileCheck %s --check-prefix=MISSING

nix.expr @e {
  %a = nix.int 1
  %b = nix.int 2
  %x = nixnum.add(%a, %b)
  %y = nixnum.add(%a, %b)
  %r = nix.list [%x, %y]
  nix.return %r
}

// Declared pure (nix.fx = "pure"): the duplicate is merged.
// PURE: [[S:%.*]] = nixnum.add(
// PURE-NOT: nixnum.add
// PURE: nix.list[[[S]], [[S]]]

// Declared as running user code (nix.fx = "user"): both calls stay.
// IMPURE: nixnum.add(
// IMPURE: nixnum.add(

// Declared with one operand (irdl.operands): the IRDL verifier rejects the call.
// ARITY: expects exactly 1 operands, but got 2

// Rejected by the loader, with the position in the declaration.
// BADFX: unknown nix.fx 'magic'
// DUP: duplicate nix.key '__add'
// MISSING: cannot read MLNIX_PRIMS_IRDL
