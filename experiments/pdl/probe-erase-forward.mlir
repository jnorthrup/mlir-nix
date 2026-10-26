nix.expr @forward {
  %a = nix.int 1
  %b = nix.int 2
  %r = nix.apply %f(%a, %b)
  %f = nix.builtin "__add"
  nix.return %r
}
