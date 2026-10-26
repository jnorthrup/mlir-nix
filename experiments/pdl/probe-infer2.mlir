nix.expr @infer2 {
  %f = nix.builtin "__length"
  %l = nix.list []
  %x = nix.int 1
  %r = nix.apply %f(%l, %x)
  nix.return %r
}
