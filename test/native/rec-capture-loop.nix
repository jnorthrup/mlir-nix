# a recursive body that captures a fold step's element: inside its function the captured value is a parameter, also where
# the body refers to itself
builtins.foldl' (acc: x: acc + (let f = n: if n == 0 then x else x + f (n - 1); in f 3)) 0 (builtins.genList (i: i) 5)
