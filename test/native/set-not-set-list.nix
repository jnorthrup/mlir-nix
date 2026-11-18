# refused: a set expected where the value is a list
# (Nix's error prints the list, «thunk»s and all)
let x = builtins.genList (i: i) 3; in x.a
