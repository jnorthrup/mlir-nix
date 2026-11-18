# the printed list, each element a recursive call
let sq = n: if n == 0 then 0 else n + n - 1 + sq (n - 1); in builtins.genList sq 6
