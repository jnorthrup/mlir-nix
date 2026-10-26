// The arity of a primop is part of its declaration; the verifier enforces it.
// RUN: mlnix-opt %s --split-input-file --verify-diagnostics

nix.expr @too_few {
  %a = nix.int 1
  // expected-error @+1 {{expects 2 operand(s) but has 1}}
  %0 = nixnum.add(%a)
  nix.return %0
}

// -----

nix.expr @too_many {
  %a = nix.int 1
  // expected-error @+1 {{expects 1 operand(s) but has 2}}
  %0 = nixlist.length(%a, %a)
  nix.return %0
}
