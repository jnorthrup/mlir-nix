# a select of a Boolean known only at run time
let b = builtins.foldl' (a: x: a + x) 0 (builtins.genList (i: i) 4) < 7; in b.x
