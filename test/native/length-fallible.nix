# refused: length's operand has elements that may fail
# (Nix never forces the elements, and a series computes them all)
builtins.length (builtins.genList (i: i * 4611686018427387904) 3)
