# refused: nix.list
# (list literals are not in this cut)
[ ({ a = { b = 1; }; } ? a.b) ({ a = 1; } ? a.b) ({ } ? a) ]
