# a step's * overflows: Nix's message, operands as written
builtins.foldl' (a: x: a + x * 4611686018427387904) 0 (builtins.genList (i: i) 3)
