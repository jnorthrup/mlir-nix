# a strict leaf function under a fold: no cell is made in either body (x is an argument, f x is forced by +)
let
  f = x: x * 3 + 1;
  step = a: x: a + f x;
in builtins.foldl' step 0 (builtins.genList (i: i) 300000)
