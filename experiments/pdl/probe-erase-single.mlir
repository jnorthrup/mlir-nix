nix.expr @single {
  %f = nix.builtin "__add"
  %a = nix.int 1
  %b = nix.int 2
  %r = nix.apply %f(%a, %b)
  nix.return %r
}
