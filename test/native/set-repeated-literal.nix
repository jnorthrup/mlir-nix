# a variable's set twice is «repeated», an equal literal is not
let x = { a = 1; }; in { p = x; q = x; r = { a = 1; }; }
