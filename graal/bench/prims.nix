# a builtin's first operand that is an op of the body: lessThan forces x * 2 before anything else (nix.first), so computed first
# it makes no cell, and f's frame need not escape
let f = x: if builtins.lessThan (x * 2) 7 then 1 else 0;
in builtins.foldl' (a: x: a + f x) 0 (builtins.genList (i: i) 300000)
