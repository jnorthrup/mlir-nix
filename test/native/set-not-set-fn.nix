# refused: a set expected where the value is a function
# (Nix's error prints the lambda's position)
let x = y: y; in x.a
