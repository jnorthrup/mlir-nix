# refused: over a closure with values
# (g captures add, which captures the step's x: a function sees none of the caller's values)
builtins.foldl' (acc: x: acc + (let add = z: z + x; g = y: add y; f = n: if n == 0 then 0 else g n + f (n - 1); in f 3)) 0 (builtins.genList (i: i) 4)
