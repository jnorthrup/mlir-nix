# refused: foldl''s list has elements that may fail
# (a step's error could come before a later element's)
builtins.foldl' (a: x: a + x) 0 (builtins.genList (i: i * 4611686018427387904) 3)
