# a set reached twice through selects is the same set: «repeated»
let s = { x = { a = 1; }; }; in { p = s.x; q = s.x; }
