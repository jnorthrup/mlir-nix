# f has one slot (its argument): the frame's size is the least it can be
let f = x: x; in builtins.foldl' (a: x: a + f x) 0 (builtins.genList (i: i) 300000)
