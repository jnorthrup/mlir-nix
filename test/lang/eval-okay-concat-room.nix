let
  # Each case reads lists that share one ListExtent buffer after `++` wrote into its room; every older list must keep its cells.
  base = builtins.genList (i: i) 10;           # 10 cells: a plain buffer
  a = [ 100 ] ++ base;                         # 11 >= 8: a new buffer, room in front (the smaller side was the left)
  b = [ 200 ] ++ a;                            # into a's room: a still starts at its old cell
  c = [ 300 ] ++ a;                            # a is no longer at the claimed edge: a copy, b keeps its 200
  d = a ++ [ 400 ];                            # a ends at the buffer's claimed end, but the room is in front: a copy
  e = base ++ [ 1 ];                           # room behind
  f = e ++ [ 2 ];                              # into e's room
  g = e ++ [ 3 ];                              # e no longer ends at the claimed edge: a copy, f keeps its 2
  h = builtins.tail b ++ [ 5 ];                # a view inside the buffer, not at an edge
  fold = builtins.foldl' (acc: x: [ x ] ++ acc) [ ] (builtins.genList (i: i) 100);
  foldr = builtins.foldl' (acc: x: acc ++ [ x ]) [ ] (builtins.genList (i: i) 100);
  # two lists claimed from one older list in a fold: the second must copy
  fork = let s = builtins.genList (i: i) 20; p = [ "p" ] ++ s; q = [ "q" ] ++ p; r = [ "r" ] ++ p; in [ (builtins.head q) (builtins.head r) (builtins.elemAt q 1) (builtins.elemAt r 1) (builtins.length p) ];
in
[
  a b c d f g h
  (builtins.head fold) (builtins.length fold) (builtins.elemAt fold 99)
  (builtins.head foldr) (builtins.length foldr) (builtins.elemAt foldr 99)
  fork
  (builtins.length a)
]
