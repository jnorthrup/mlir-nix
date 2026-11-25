# removeAttrs with a known list of names
builtins.removeAttrs { a = 1; b = 2; c = 3; } [ "a" "c" ]
