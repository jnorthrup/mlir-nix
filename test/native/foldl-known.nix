# foldl' over a list literal: the accumulator forced at each step
builtins.foldl' (a: x: a + x) 0 [ 1 2 3 ]
