# an empty list is never «repeated»
let l = builtins.genList (i: i) 0; in { a = l; b = l; }
