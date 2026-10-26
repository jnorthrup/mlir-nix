nix.expr @groups {
  %b = nix.builtin "builtins"
  %d = nix.int 42
  %with = nix.select %b ["add"] or %d
  %without = nix.select %b ["add"]
  %other = nix.select %b ["sub"] or %d
  %r = nix.list [%with, %without, %other]
  nix.return %r
}
