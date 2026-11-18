# `s // { }` and `{ } // s` are s itself
let s = { a = 1; }; in { p = s; q = s // { }; r = { } // s; }
