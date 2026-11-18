# a curried call's later argument: in `add (x * 2) (x + 1)` the body that takes the second argument forces it, but it is known only
# once `add (x * 2)` has returned it; computed first, `x + 1` makes no cell over f's frame
let add = a: b: a + b;
    f = x: add (x * 2) (x + 1);
in builtins.foldl' (acc: x: acc + f x) 0 (builtins.genList (i: i) 300000)
