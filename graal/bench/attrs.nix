# a set made and selected from: mk's frame escapes through the cell of b; get makes no cell
let
  mk = i: { a = i; b = i + 1; };
  get = s: s.a + s.b;
in builtins.foldl' (acc: i: acc + get (mk i)) 0 (builtins.genList (i: i) 200000)
