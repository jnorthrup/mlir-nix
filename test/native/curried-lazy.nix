# refused: a recursive call of row1, whose body does not force its argument
# (x is passed along and never forced, so computing it first (as a call does) would fail where Nix does not)
let f = n: x: if n == 0 then 0 else f (n - 1) x; in f 5 (9223372036854775807 + 1)
