# foldl' of a named curried function
let add = a: b: a + b; in builtins.foldl' add 0 (builtins.genList (i: i) 100)
