# foldl' forces its first accumulator even over nothing
builtins.foldl' (a: x: a + x) (9223372036854775807 + 1) (builtins.genList (i: i) 0)
