# recursion with lazy arguments: each call's frame escapes through the cells of n - 1 and n - 2
let fib = n: if n < 2 then n else fib (n - 1) + fib (n - 2); in fib 24
