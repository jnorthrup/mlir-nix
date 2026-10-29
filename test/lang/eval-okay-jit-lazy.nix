# Warm eligible arithmetic with already-forced integers, then exercise calls
# that must retain Nix laziness or fall back to the interpreter.
let
  inputs = builtins.genList (x: x) 80;
  warm = f: builtins.foldl'
    (acc: x: builtins.seq x (builtins.seq (f x) acc)) 0 inputs;
  arithmetic = x: builtins.sub (builtins.mul (builtins.add x 1) 3) 2;
  constant = x: 7;
  dead = throw "JIT forced unreachable code";
  recursive = recursive;
  branch = x: if true then x else dead;
  capture = let unused = dead; in x: if false then unused else x;
  deadBinding = x:
    let unused = builtins.add dead x;
    in builtins.add x 1;
in
assert warm arithmetic == 0;
assert arithmetic 80 == 241;
assert arithmetic (-2) == -5;
assert arithmetic 0.5 == 2.5;
assert builtins.tryEval (arithmetic dead) == { success = false; value = false; };
assert warm constant == 0;
assert constant dead == 7;
assert constant recursive == 7;
assert warm branch == 0;
assert branch 13 == 13;
assert warm capture == 0;
assert capture 17 == 17;
assert warm deadBinding == 0;
assert deadBinding 19 == 20;
assert builtins.length [ (arithmetic dead) ] == 1;
true
