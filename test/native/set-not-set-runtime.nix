# a select of an integer known only at run time
let n = builtins.foldl' (a: x: a + x) 0 (builtins.genList (i: i) 4); in n.x
