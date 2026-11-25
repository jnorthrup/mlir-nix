# refused: filter whose predicate may fail
# (a checked multiplication in the predicate: the order of its failures is not the program's)
builtins.filter (x: x * 2 > 3) (builtins.genList (i: i) 4)
