# refused: elemAt's list has elements that may fail
# (Nix forces only the third)
builtins.elemAt (builtins.genList (i: i * 4611686018427387904) 3) 0
