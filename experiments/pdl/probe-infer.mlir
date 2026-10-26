nix.expr @infer {
  %f = nix.builtin "__length"
  %l = nix.list []
  %r = nix.apply %f(%l)
  nix.return %r
}
