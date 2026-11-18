# two calls of a function make two sets
let f = x: { a = x; }; in { p = f 1; q = f 1; }
