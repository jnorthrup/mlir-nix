# sets made, merged and selected in a fold's step
builtins.foldl' (acc: i: acc + (let s = { a = i; b = i * 2; } // { c = 1; }; in s.b + s.c)) 0 (builtins.genList (i: i) 10)
