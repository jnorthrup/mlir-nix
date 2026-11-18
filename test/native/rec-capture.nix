# a recursive body over a captured integer
let k = 3; f = n: if n == 0 then k else k + f (n - 1); in f 10
