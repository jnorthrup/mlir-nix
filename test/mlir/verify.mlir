// The arity of a primop is part of its IRDL declaration (irdl.operands); the stock
// IRDL verifier enforces it, so the wording is IRDL's.
// RUN: mlnix-opt %s --split-input-file --verify-diagnostics

nix.expr @too_few {
  %a = nix.int 1
  // expected-error @+1 {{expects exactly 2 operands, but got 1}}
  %0 = nixnum.add(%a)
  nix.return %0
}

// -----

nix.expr @too_many {
  %a = nix.int 1
  // expected-error @+1 {{expects exactly 1 operands, but got 2}}
  %0 = nixlist.length(%a, %a)
  nix.return %0
}

// -----

// A computed path component needs an operand (generic form, since the custom
// syntax cannot express the mismatch).
nix.expr @path_mismatch {
  %s = nix.attrs [](  )
  // expected-error @+1 {{has 1 computed path component(s) but 0 operand(s)}}
  %0 = "nix.select"(%s) <{path = [unit], operandSegmentSizes = array<i32: 1, 0, 0>}> : (!nix.value) -> !nix.value
  nix.return %0
}
