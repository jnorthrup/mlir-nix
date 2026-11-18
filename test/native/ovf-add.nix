# + overflows on the fifth step: the sum so far and the operand (Nix 2.24's message; mlnix printed the wrapped sum until this change)
builtins.foldl' (a: x: a + x) 9223372036854775800 (builtins.genList (i: i) 10)
