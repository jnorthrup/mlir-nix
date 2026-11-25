# a list literal of Booleans from `?`
[ ({ a = { b = 1; }; } ? a.b) ({ a = 1; } ? a.b) ({ } ? a) ]
