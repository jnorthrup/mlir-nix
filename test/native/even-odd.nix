# refused: over a capture it may not force
# (mutually recursive bodies returning Booleans)
let even = n: if n == 0 then true else odd (n - 1); odd = n: if n == 0 then false else even (n - 1); in even 10
