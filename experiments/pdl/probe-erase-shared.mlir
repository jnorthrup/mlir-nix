nix.expr @shared {
  %f = nix.builtin "__add"
  %a = nix.int 1
  %b = nix.int 2
  %r1 = nix.apply %f(%a, %b)
  %r2 = nix.apply %f(%b, %a)
  %l = nix.list [%r1, %r2]
  nix.return %l
}
