# f has nine slots, all strict (no cell): a frame that is allocated grows by 32 B, a virtual one by nothing
let f = x: if x == x then (if x == 0 then 0 else (if x == 1 then 1 else x)) else 0;
in builtins.foldl' (a: x: a + f x) 0 (builtins.genList (i: i) 300000)
