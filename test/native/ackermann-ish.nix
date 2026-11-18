# nested recursive calls of a curried body
let g = m: n: if m == 0 then n + 1 else if n == 0 then g (m - 1) 1 else g (m - 1) (g m (n - 1)); in g 2 3
