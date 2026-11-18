# a list selected twice is two cells, so not «repeated»
let s = { l = builtins.genList (i: i) 3; }; in { p = s.l; q = s.l; }
