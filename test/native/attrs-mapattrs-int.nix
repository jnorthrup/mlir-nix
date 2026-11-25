# mapAttrs over integers
builtins.mapAttrs (n: v: v + 1) { a = 1; b = 2; }
