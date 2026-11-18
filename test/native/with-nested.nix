# the innermost `with` first
with { a = 1; b = 5; }; with { a = 2; }; a + b
