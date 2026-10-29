let
  id = x: x;
  proj = s: s.a;
  deep = s: s.a.b.c;
  neg = b: !b;
  isNull' = x: x == null;
  both = x: (x ? a) && (x ? b);
  tern = c: if c then 1 else 2;
  lazyId = id (throw "never forced by id's caller");
  keep = id { a = 1; };
  apply = f: x: f x;
  # a body that is a call whose callee and arguments are its argument or captured values
  pred = x: x > 2;
  negPred = x: !(pred x);
  twice = f: x: f (f x);
  viaCapture = x: apply id x;
  lazyArg = f: f (throw "the callee decides whether this is forced");
  constant = k: _: k;
  compose = f: g: x: f (g x);
  filtered = builtins.filter negPred [ 1 2 3 4 ];
  counter = n: if n == 0 then 0 else 1 + counter (n - 1);
in {
  a = id 5;
  b = proj { a = 7; b = throw "unused field stays lazy"; };
  c = deep { a.b.c = "deep"; };
  d = neg true;
  e = isNull' null;
  f = both { a = 1; b = 2; };
  g = both { a = 1; };
  h = tern (1 < 2);
  i = builtins.map proj [ { a = 1; } { a = 2; } ];
  j = builtins.length [ lazyId ];
  k = keep.a;
  l = apply id 9;
  m = apply neg false;
  n = builtins.foldl' (acc: x: acc + proj x) 0 [ { a = 1; } { a = 2; } { a = 3; } ];
  o = id id 3;
  p = filtered;
  q = twice (x: x + 1) 5;
  r = viaCapture 8;
  s = (lazyArg (_: 4));
  t = builtins.map (constant 7) [ 1 2 3 ];
  u = compose neg neg true;
  v = counter 200;
  w = builtins.foldl' (a: x: if negPred x then a + 1 else a) 0 [ 1 2 3 4 5 ];
}
