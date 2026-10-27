// Not a test: scripts/run-mlir-tests.py runs `mlnix-opt -cse` on this to learn whether the LLVM this build links
// merges two equal ops of an IRDL-defined dialect (the feature `cse-dynamic-ops`).
nix.expr @probe {
  %a = nix.int 1
  %b = nix.int 2
  %x = nixnum.add(%a, %b)
  %y = nixnum.add(%a, %b)
  %r = nix.list [%x, %y]
  nix.return %r
}
