# mapAttrs: f name value for each name, the values computed as they are printed
builtins.mapAttrs (n: v: "${n}=${v}") { a = "x"; b = "y"; }
